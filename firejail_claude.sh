#!/usr/bin/env bash
#
# firejail_claude.sh - Run Claude Code in a Firejail sandbox
#
# This script provides filesystem and capability isolation for Claude Code
# on Linux systems using Firejail's security sandbox.
#
# Prerequisites:
#   - Firejail installed (apt install firejail / dnf install firejail)
#   - Claude Code installed (npm install -g @anthropic-ai/claude-code)
#
# Usage:
#   ./firejail_claude.sh [claude arguments...]
#
# Examples:
#   ./firejail_claude.sh                    # Interactive mode
#   ./firejail_claude.sh -p "explain this"  # With prompt
#   ./firejail_claude.sh --help             # Claude help
#

set -euo pipefail

# Resolve Claude binary location
CLAUDE_BIN="$(which claude 2>/dev/null || echo "")"
if [ -z "$CLAUDE_BIN" ]; then
    echo "Error: 'claude' not found in PATH" >&2
    echo "Install with: npm install -g @anthropic-ai/claude-code" >&2
    exit 1
fi

# Resolve to actual binary if it's a symlink
CLAUDE_BIN="$(readlink -f "$CLAUDE_BIN")"

# Working directory - where Claude can read/write project files
WORK_DIR="$(pwd)"

# Ensure required directories exist
mkdir -p "$HOME/.claude"
mkdir -p "$HOME/.npm"

# Build dynamic whitelist arguments
WHITELIST_ARGS=()

# Writable directories - Claude needs to modify these
WHITELIST_ARGS+=(--whitelist="$HOME/.claude")      # Claude state/config
WHITELIST_ARGS+=(--whitelist="$HOME/.npm")         # NPM cache
WHITELIST_ARGS+=(--whitelist="$WORK_DIR")          # Current project

# Read-only paths - Claude can read but not modify
[ -f "$HOME/.gitconfig" ] && WHITELIST_ARGS+=(--read-only="$HOME/.gitconfig")
[ -d "$HOME/.config/git" ] && WHITELIST_ARGS+=(--read-only="$HOME/.config/git")
[ -f "$HOME/.ssh/known_hosts" ] && WHITELIST_ARGS+=(--read-only="$HOME/.ssh/known_hosts")
[ -d "$HOME/.local" ] && WHITELIST_ARGS+=(--read-only="$HOME/.local")
[ -d "$HOME/.nvm" ] && WHITELIST_ARGS+=(--read-only="$HOME/.nvm")
[ -d "$HOME/.volta" ] && WHITELIST_ARGS+=(--read-only="$HOME/.volta")

# Node.js runtime paths (read-only)
[ -d "/usr/lib/node_modules" ] && WHITELIST_ARGS+=(--read-only="/usr/lib/node_modules")
[ -d "/usr/local/lib/node_modules" ] && WHITELIST_ARGS+=(--read-only="/usr/local/lib/node_modules")

# SSH Agent forwarding - required for git operations over SSH
SSH_ARGS=()
if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
    SSH_AGENT_DIR="$(dirname "$SSH_AUTH_SOCK")"
    WHITELIST_ARGS+=(--whitelist="$SSH_AGENT_DIR")
    SSH_ARGS+=(--env=SSH_AUTH_SOCK="$SSH_AUTH_SOCK")
fi

# Environment variables to pass through
ENV_ARGS=(
    --env=HOME="$HOME"
    --env=USER="$USER"
    --env=TERM="${TERM:-xterm-256color}"
    --env=LANG="${LANG:-en_US.UTF-8}"
    --env=PATH="$PATH"
)

# Pass through API keys if set
[ -n "${ANTHROPIC_API_KEY:-}" ] && ENV_ARGS+=(--env=ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY")

# Firejail security options
SECURITY_ARGS=(
    --noprofile                # Don't use default profiles, we define everything
    --caps.drop=all            # Drop all Linux capabilities
    --nonewprivs               # Prevent privilege escalation via execve
    --noroot                   # Disable root user inside sandbox
    --seccomp                  # Enable seccomp syscall filtering
    --private-tmp              # Private /tmp filesystem
    --private-dev              # Minimal /dev (null, zero, urandom, etc.)
    --nodvd                    # No DVD/CD access
    --nosound                  # No audio access
    --no3d                     # No GPU/3D acceleration
    --notv                     # No TV devices
    --nou2f                    # No U2F devices
    --novideo                  # No video capture devices
    --disable-mnt              # No access to /mnt, /media
    --shell=none               # Don't start a shell, run command directly
)

# Network is allowed (required for Claude API)
# Add --net=none here to disable if running fully offline

echo "Starting Claude in Firejail sandbox..."
echo "Working directory: $WORK_DIR"
echo "Writable: ~/.claude, ~/.npm, \$PWD"
echo "---"

exec firejail \
    "${SECURITY_ARGS[@]}" \
    "${WHITELIST_ARGS[@]}" \
    "${ENV_ARGS[@]}" \
    "${SSH_ARGS[@]}" \
    "$CLAUDE_BIN" "$@"
