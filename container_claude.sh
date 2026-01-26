#!/usr/bin/env bash
#
# container_claude.sh - Run Claude Code in an Apple Container VM sandbox
#
# This script provides strong VM-based isolation for Claude Code on macOS
# using Apple's Container framework (Virtualization.framework).
#
# Prerequisites:
#   - macOS 13.0+ (Ventura or later)
#   - Apple Container CLI (https://github.com/apple/swift-container)
#   - Sufficient disk space for the container image (~500MB)
#
# Usage:
#   ./container_claude.sh [claude arguments...]
#
# Examples:
#   ./container_claude.sh                    # Interactive mode
#   ./container_claude.sh -p "explain this"  # With prompt
#   ./container_claude.sh --help             # Claude help
#
# First run will build the container image (takes a few minutes).
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="claude-sandbox"
CONTAINER_NAME="claude-session-$$"  # Unique name per invocation

# Working directory - maps to /workspace in container
WORK_DIR="$(pwd)"

# Host user info - used to match permissions in container
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Check prerequisites
check_prerequisites() {
    # Check macOS version
    if [[ "$(uname -s)" != "Darwin" ]]; then
        log_error "This script requires macOS"
        exit 1
    fi

    # Check for container CLI
    if ! command -v container &>/dev/null; then
        log_error "'container' CLI not found"
        echo ""
        echo "Install Apple Container from: https://github.com/apple/swift-container"
        echo ""
        echo "Quick install:"
        echo "  git clone https://github.com/apple/swift-container"
        echo "  cd swift-container"
        echo "  swift build -c release"
        echo "  cp .build/release/container /usr/local/bin/"
        exit 1
    fi

    # Check for Containerfile
    if [[ ! -f "$SCRIPT_DIR/Containerfile" ]]; then
        log_error "Containerfile not found in $SCRIPT_DIR"
        exit 1
    fi
}

# Build the container image if it doesn't exist or is outdated
build_image_if_needed() {
    local needs_build=false

    # Check if image exists
    if ! container images 2>/dev/null | grep -q "^${IMAGE_NAME}"; then
        log_info "Container image '$IMAGE_NAME' not found, building..."
        needs_build=true
    fi

    # Check if Containerfile is newer than image (if we can determine this)
    # For now, just build if image doesn't exist

    if $needs_build; then
        log_info "Building container image (this may take a few minutes)..."

        container build \
            -t "$IMAGE_NAME" \
            --build-arg HOST_UID="$HOST_UID" \
            --build-arg HOST_GID="$HOST_GID" \
            "$SCRIPT_DIR"

        log_info "Container image built successfully"
    fi
}

# Ensure required directories exist on host
setup_directories() {
    mkdir -p "$HOME/.claude"
    mkdir -p "$HOME/.npm"
}

# Build mount arguments
build_mount_args() {
    local -n mounts=$1

    # Working directory - read/write access to current project
    mounts+=(--mount "type=bind,src=$WORK_DIR,dst=/workspace")

    # Claude configuration - persistent state
    mounts+=(--mount "type=bind,src=$HOME/.claude,dst=/home/claude/.claude")

    # NPM cache - improves performance for package operations
    mounts+=(--mount "type=bind,src=$HOME/.npm,dst=/home/claude/.npm")

    # Git configuration - read-only
    if [[ -f "$HOME/.gitconfig" ]]; then
        mounts+=(--mount "type=bind,src=$HOME/.gitconfig,dst=/home/claude/.gitconfig,readonly")
    fi

    # Git config directory - read-only
    if [[ -d "$HOME/.config/git" ]]; then
        mounts+=(--mount "type=bind,src=$HOME/.config/git,dst=/home/claude/.config/git,readonly")
    fi

    # SSH known_hosts - read-only (for git over SSH)
    if [[ -f "$HOME/.ssh/known_hosts" ]]; then
        mounts+=(--mount "type=bind,src=$HOME/.ssh/known_hosts,dst=/home/claude/.ssh/known_hosts,readonly")
    fi

    # SSH Agent socket forwarding
    # Note: This requires the socket directory to be accessible
    if [[ -n "${SSH_AUTH_SOCK:-}" ]] && [[ -S "$SSH_AUTH_SOCK" ]]; then
        local ssh_dir
        ssh_dir="$(dirname "$SSH_AUTH_SOCK")"
        mounts+=(--mount "type=bind,src=$ssh_dir,dst=/run/host-ssh")
    fi
}

# Build environment arguments
build_env_args() {
    local -n envs=$1

    # Basic environment
    envs+=(--env "TERM=${TERM:-xterm-256color}")
    envs+=(--env "LANG=en_US.UTF-8")

    # API key (required for Claude to function)
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        envs+=(--env "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY")
    fi

    # SSH Agent socket (remapped path inside container)
    if [[ -n "${SSH_AUTH_SOCK:-}" ]] && [[ -S "$SSH_AUTH_SOCK" ]]; then
        local sock_name
        sock_name="$(basename "$SSH_AUTH_SOCK")"
        envs+=(--env "SSH_AUTH_SOCK=/run/host-ssh/$sock_name")
    fi
}

# Run the container
run_container() {
    local mount_args=()
    local env_args=()

    build_mount_args mount_args
    build_env_args env_args

    log_info "Starting Claude in Apple Container sandbox..."
    log_info "Working directory: $WORK_DIR"
    log_info "Writable: ~/.claude, ~/.npm, \$PWD"
    echo "---"

    # Run with interactive TTY if available
    local tty_args=()
    if [[ -t 0 ]] && [[ -t 1 ]]; then
        tty_args+=(--tty --interactive)
    fi

    exec container run \
        --rm \
        --name "$CONTAINER_NAME" \
        "${tty_args[@]}" \
        "${mount_args[@]}" \
        "${env_args[@]}" \
        "$IMAGE_NAME" \
        "$@"
}

# Cleanup handler
cleanup() {
    # Container should auto-cleanup with --rm, but just in case
    container rm -f "$CONTAINER_NAME" 2>/dev/null || true
}

# Main
main() {
    trap cleanup EXIT

    check_prerequisites
    build_image_if_needed
    setup_directories
    run_container "$@"
}

main "$@"
