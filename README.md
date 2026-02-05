# Sandboxed Claude Code

Run Claude Code (Anthropic's AI coding assistant) in a security sandbox to limit its access to your system. This repository provides three different sandboxing approaches for different platforms and security requirements.

## Why Sandbox Claude Code?

Claude Code is an AI agent that can read files, write code, and execute commands. While it's designed to be helpful and safe, defense-in-depth security practices suggest limiting any automated tool's access to only what it needs. Sandboxing provides:

- **Filesystem isolation** - Claude can only access your current project, not your entire home directory
- **Capability restriction** - Dropped privileges prevent potential privilege escalation
- **Blast radius reduction** - If something goes wrong, damage is contained
- **Audit clarity** - Clear boundaries make it easier to understand what Claude can and cannot do

## Quick Start

| Platform | Recommended Approach | Command |
|----------|---------------------|---------|
| Linux | Bubblewrap | `./bubblewrap_claude.sh` |
| Linux (alternative) | Firejail | `./firejail_claude.sh` |
| macOS | Apple Container | `./container_claude.sh` |

## Approaches Compared

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          ISOLATION STRENGTH                                 │
│                                                                             │
│  Weaker                                                                     │
│    │                                                                        │
│    │   ┌──────────────┐                                                     │
│    │   │   Firejail   │  Namespaces + Seccomp                               │
│    │   │              │  Easy to configure, good defaults                   │
│    │   └──────────────┘                                                     │
│    │                                                                        │
│    │   ┌──────────────┐                                                     │
│    │   │  Bubblewrap  │  Namespaces (manual config)                         │
│    │   │              │  Maximum control, minimal overhead                  │
│    │   └──────────────┘                                                     │
│    │                                                                        │
│    │   ┌───────────────┐                                                    │
│    │   │Apple Container│  Hypervisor (VM)                                   │
│    │   │               │  Strongest isolation, higher overhead              │
│    ▼   └───────────────┘                                                    │
│  Stronger                                                                   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Comparison Matrix

| Feature | Bubblewrap | Firejail | Apple Container |
|---------|------------|----------|-----------------|
| **Platform** | Linux | Linux | macOS |
| **Isolation Type** | Linux namespaces | Namespaces + seccomp | Lightweight VM |
| **Startup Overhead** | ~5ms | ~10ms | ~500ms-2s |
| **Memory Overhead** | Minimal | Minimal | 256MB+ |
| **Escape Difficulty** | Medium | Medium | Hard |
| **Configuration** | Manual | Profile-based | Containerfile |
| **Syscall Filtering** | Manual | Built-in | N/A (different kernel) |
| **Learning Curve** | Steep | Moderate | Moderate |

---

## 1. Bubblewrap (Linux)

**Best for:** Linux users who want minimal overhead and maximum control.

### How It Works

Bubblewrap (`bwrap`) uses Linux namespaces to create an isolated environment:

```
┌─────────────────────────────────────────────────────────────────┐
│                         HOST SYSTEM                             │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    BWRAP SANDBOX                          │  │
│  │                                                           │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │  │
│  │  │ Mount NS    │  │   PID NS    │  │  User NS    │        │  │
│  │  │             │  │             │  │             │        │  │
│  │  │ /usr (RO)   │  │ Isolated    │  │ Mapped UID  │        │  │
│  │  │ /lib (RO)   │  │ process     │  │             │        │  │
│  │  │ $PWD (RW)   │  │ tree        │  │             │        │  │
│  │  │ ~/.claude(RW│  │             │  │             │        │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘        │  │
│  │                                                           │  │
│  │                    ┌─────────────┐                        │  │
│  │                    │   Claude    │                        │  │
│  │                    │    Code     │                        │  │
│  │                    └─────────────┘                        │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

**Namespace isolation:**
- **Mount namespace** - Custom filesystem view with selective bind mounts
- **PID namespace** - Isolated process tree (can't see/signal host processes)
- **Network** - Shared (required for Claude API)

### Installation

```bash
# Debian/Ubuntu
sudo apt install bubblewrap

# Fedora/RHEL
sudo dnf install bubblewrap

# Arch Linux
sudo pacman -S bubblewrap
```

### Usage

```bash
# Navigate to your project
cd /path/to/your/project

# Run Claude in sandbox
./bubblewrap_claude.sh

# Pass arguments to Claude
./bubblewrap_claude.sh -p "explain this codebase"
```

### Filesystem Access

| Path | Access | Purpose |
|------|--------|---------|
| `/usr`, `/lib`, `/bin` | Read-only | System binaries and libraries |
| `/etc/resolv.conf`, `/etc/hosts` | Read-only | Network configuration |
| `/etc/ssl` | Read-only | TLS certificates |
| `$HOME/.gitconfig` | Read-only | Git identity |
| `$HOME/.ssh/known_hosts` | Read-only | SSH host verification |
| `$SSH_AUTH_SOCK` | Read-write | SSH agent (git auth) |
| `$HOME/.nvm`, `$HOME/.local` | Read-only | Node.js runtime |
| `$HOME/.npm` | Read-write | NPM package cache |
| `$HOME/.claude` | Read-write | Claude configuration |
| `$PWD` | Read-write | **Your project** |
| `/tmp` | tmpfs | Ephemeral scratch space |

### Security Features

```bash
--unshare-pid           # Isolate process namespace
--die-with-parent       # Kill sandbox if parent dies
--ro-bind               # Read-only mounts for system paths
--tmpfs /tmp            # Fresh /tmp on each run
```

---

## 2. Firejail (Linux)

**Best for:** Linux users who want easier configuration with good security defaults.

### How It Works

Firejail wraps bubblewrap-style namespaces with additional security layers:

```
┌─────────────────────────────────────────────────────────────────┐
│                         HOST SYSTEM                             │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   FIREJAIL SANDBOX                        │  │
│  │                                                           │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │              SECCOMP FILTER                         │  │  │
│  │  │  Blocks dangerous syscalls: ptrace, mount, etc.     │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  │                          │                                │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │           CAPABILITY RESTRICTIONS                   │  │  │
│  │  │  caps.drop=all, nonewprivs, noroot                  │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  │                          │                                │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │              NAMESPACE ISOLATION                    │  │  │
│  │  │  Mount, PID, IPC namespaces                         │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  │                          │                                │  │
│  │                    ┌─────────────┐                        │  │
│  │                    │   Claude    │                        │  │
│  │                    │    Code     │                        │  │
│  │                    └─────────────┘                        │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

**Additional protections over raw bubblewrap:**
- **Seccomp BPF** - Syscall filtering blocks dangerous operations
- **Capability dropping** - All Linux capabilities removed
- **No-new-privileges** - Prevents privilege escalation via setuid binaries

### Installation

```bash
# Debian/Ubuntu
sudo apt install firejail

# Fedora/RHEL
sudo dnf install firejail

# Arch Linux
sudo pacman -S firejail
```

### Usage

**Option A: Use the wrapper script**
```bash
./firejail_claude.sh
```

**Option B: Install the profile globally**
```bash
# Copy profile to firejail config
cp claude.firejail.profile ~/.config/firejail/claude.profile

# Run with profile
firejail --profile=claude claude
```

### Security Features

```bash
--caps.drop=all         # Drop ALL Linux capabilities
--nonewprivs            # No privilege escalation via execve
--noroot                # Disable root inside sandbox
--seccomp               # Enable syscall filtering
--private-tmp           # Isolated /tmp
--private-dev           # Minimal /dev
--nodvd --nosound       # Disable hardware access
--no3d --notv --novideo # Disable GPU/media devices
```

### Profile Customization

Edit `claude.firejail.profile` to customize. Common modifications:

```ini
# Disable network (for offline analysis)
net none

# Add additional read-only paths
read-only ${HOME}/reference-docs

# Allow specific additional writable paths
whitelist ${HOME}/scratch-area
```

---

## 3. Apple Container (macOS)

**Best for:** macOS users who want the strongest isolation available.

### How It Works

Apple Container uses macOS's Virtualization.framework to run a lightweight Linux VM:

```
┌─────────────────────────────────────────────────────────────────┐
│                         macOS HOST                              │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              VIRTUALIZATION.FRAMEWORK                     │  │
│  │                                                           │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │               LIGHTWEIGHT VM                        │  │  │
│  │  │                                                     │  │  │
│  │  │  ┌─────────────┐  ┌──────────────────────────────┐  │  │  │
│  │  │  │ Linux Kernel│  │        Userspace             │  │  │  │
│  │  │  │  (custom)   │  │  ┌────────────────────────┐  │  │  │  │
│  │  │  │             │  │  │     Debian minimal     │  │  │  │  │
│  │  │  │             │  │  │  ┌──────────────────┐  │  │  │  │  │
│  │  │  │             │  │  │  │    Node.js       │  │  │  │  │  │
│  │  │  │             │  │  │  │  ┌────────────┐  │  │  │  │  │  │
│  │  │  │             │  │  │  │  │  Claude    │  │  │  │  │  │  │
│  │  │  │             │  │  │  │  │   Code     │  │  │  │  │  │  │
│  │  │  │             │  │  │  │  └────────────┘  │  │  │  │  │  │
│  │  │  │             │  │  │  └──────────────────┘  │  │  │  │  │
│  │  │  │             │  │  └────────────────────────┘  │  │  │  │
│  │  │  └─────────────┘  └──────────────────────────────┘  │  │  │
│  │  │                                                     │  │  │
│  │  │  ┌─────────────────────────────────────────────────┐│  │  │
│  │  │  │              VIRTIO DEVICES                     ││  │  │
│  │  │  │  • virtio-fs: /workspace ←→ $PWD                ││  │  │
│  │  │  │  • virtio-net: NAT networking                   ││  │  │
│  │  │  │  • virtio-vsock: Host communication             ││  │  │
│  │  │  └─────────────────────────────────────────────────┘│  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

**Why VMs provide stronger isolation:**
- **Different kernel** - Kernel exploits in the VM don't affect the host
- **Hardware boundary** - Hypervisor enforces separation at CPU level
- **No shared namespaces** - Complete process/memory isolation
- **Minimal attack surface** - Only virtio devices exposed

### Prerequisites

1. **macOS 13.0 (Ventura) or later**
2. **Apple Container CLI**

```bash
# Clone the repository
git clone https://github.com/apple/swift-container
cd swift-container

# Build
swift build -c release

# Install
sudo cp .build/release/container /usr/local/bin/
```

### Usage

```bash
# First run builds the container image (takes a few minutes)
./container_claude.sh

# Subsequent runs start quickly
./container_claude.sh -p "review this code"
```

### Build Customization

Modify `Containerfile` to customize the image:

```dockerfile
# Change Node.js version
ARG NODE_VERSION=22

# Add additional tools
RUN apt-get install -y ripgrep fd-find

# Change base image
FROM ubuntu:24.04
```

Rebuild after changes:
```bash
container build -t claude-sandbox --no-cache .
```

### Directory Mounts

| Host Path | Container Path | Access |
|-----------|----------------|--------|
| `$PWD` | `/workspace` | Read-write |
| `~/.claude` | `/home/claude/.claude` | Read-write |
| `~/.npm` | `/home/claude/.npm` | Read-write |
| `~/.gitconfig` | `/home/claude/.gitconfig` | Read-only |
| `~/.ssh/known_hosts` | `/home/claude/.ssh/known_hosts` | Read-only |
| `$SSH_AUTH_SOCK` dir | `/run/host-ssh` | Read-write |

---

## Security Model

All three approaches implement the same security model:

### Principle of Least Privilege

```
┌─────────────────────────────────────────────────────────────────┐
│                    CLAUDE'S ACCESS MODEL                        │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    CAN READ                             │    │
│  │  • Current project directory ($PWD)                     │    │
│  │  • Git configuration (identity)                         │    │
│  │  • SSH known_hosts (host verification)                  │    │
│  │  • System binaries and libraries                        │    │
│  │  • Node.js runtime                                      │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   CAN WRITE                             │    │
│  │  • Current project directory ($PWD)                     │    │
│  │  • Claude config (~/.claude)                            │    │
│  │  • NPM cache (~/.npm)                                   │    │
│  │  • Temporary files (/tmp - ephemeral)                   │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   CANNOT ACCESS                         │    │
│  │  ✗ Other home directory contents                        │    │
│  │  ✗ SSH private keys                                     │    │
│  │  ✗ Browser data, passwords, credentials                 │    │
│  │  ✗ Other users' files                                   │    │
│  │  ✗ System configuration (write)                         │    │
│  │  ✗ Hardware devices (except network)                    │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   NETWORK ACCESS                        │    │
│  │  ✓ Outbound HTTPS (Claude API)                          │    │
│  │  ✓ Outbound SSH (git operations)                        │    │
│  │  ✓ DNS resolution                                       │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### What's Protected

| Asset | Protection |
|-------|------------|
| SSH private keys | Not mounted into sandbox |
| Browser profiles | Not accessible |
| Credentials/secrets | Not in scope |
| Other projects | Not mounted |
| System config | Read-only or not mounted |
| Email, documents | Not accessible |

---

## Git Commit Signing (GPG)

If you use GPG to sign git commits, additional configuration is required to make signing work inside the sandbox.

### Why GPG Signing Fails in Sandboxes

GPG commit signing requires several components to work together:

```
┌─────────────────────────────────────────────────────────────────┐
│                    GPG SIGNING FLOW                              │
│                                                                  │
│  1. Git invokes GPG to sign commit                               │
│           │                                                      │
│           ▼                                                      │
│  2. GPG needs to read private key from ~/.gnupg/private-keys-v1.d│
│           │                                                      │
│           ▼                                                      │
│  3. GPG contacts gpg-agent (via socket) for passphrase           │
│           │                                                      │
│           ▼                                                      │
│  4. gpg-agent uses pinentry to prompt user (needs GPG_TTY)       │
│           │                                                      │
│           ▼                                                      │
│  5. Signed commit created                                        │
└─────────────────────────────────────────────────────────────────┘
```

Sandboxes can break this flow by:
- Not binding the `~/.gnupg` directory (missing private keys)
- Not binding the gpg-agent socket (can't communicate with agent)
- Not having `GPG_TTY` set (pinentry can't prompt for passphrase)

### Host System Prerequisites

Before configuring the sandbox, ensure GPG signing works on your host system:

**1. Set GPG_TTY (required for passphrase prompts)**

Add to your shell profile (`~/.bashrc`, `~/.zshrc`, or equivalent):

```bash
export GPG_TTY=$(tty)
```

Then reload your shell or run `source ~/.bashrc`.

**2. Verify GPG signing works on host**

```bash
# Test signing (should prompt for passphrase and succeed)
echo "test" | gpg --clearsign

# Verify your signing key is available
gpg --list-secret-keys
```

**3. Configure git to use your key**

```bash
# Find your key ID
gpg --list-secret-keys --keyid-format=long

# Configure git (use your key ID)
git config --global user.signingkey YOUR_KEY_ID
git config --global commit.gpgsign true
```

### Sandbox-Specific Configuration

#### Bubblewrap

The `bubblewrap_claude.sh` script must bind:

1. **Full `~/.gnupg` directory** (with write access for trustdb updates)
2. **GPG agent socket directory** (usually `/run/user/<uid>/gnupg`)

The script includes this configuration:

```bash
# Bind the .gnupg directory with write access
if [ -d "$HOME/.gnupg" ]; then
  GPG_BINDS="--bind $HOME/.gnupg $HOME/.gnupg"
fi

# Bind the GPG agent socket directory
GPG_SOCKDIR=$(gpgconf --list-dirs socketdir 2>/dev/null)
if [ -n "$GPG_SOCKDIR" ] && [ -d "$GPG_SOCKDIR" ]; then
  GPG_BINDS="$GPG_BINDS --bind $GPG_SOCKDIR $GPG_SOCKDIR"
fi
```

#### Firejail

Add to your firejail profile or command line:

```bash
# Allow access to GPG directory and sockets
firejail --whitelist=${HOME}/.gnupg \
         --whitelist=/run/user/$(id -u)/gnupg \
         claude
```

#### Apple Container

GPG signing inside the VM requires the key to exist within the container. Options:

1. **Forward gpg-agent socket via vsock** (complex)
2. **Copy the key into the container** (security tradeoff)
3. **Sign commits after exiting the container** (recommended)

For most users, we recommend making commits outside the container or using the container for unsigned work.

### Verifying GPG Works in Sandbox

After configuring, test inside the sandbox:

```bash
# Inside sandboxed Claude session, run:
echo "test" | gpg --clearsign

# Should succeed and show signed message
# If it fails, check troubleshooting section below
```

---

## Troubleshooting

### GPG Signing

**"gpg: signing failed: Inappropriate ioctl for device"**

This means GPG can't prompt for your passphrase. Fix:

```bash
# On your HOST system (not in sandbox), add to ~/.bashrc or ~/.zshrc:
export GPG_TTY=$(tty)

# Reload shell
source ~/.bashrc

# Verify it's set
echo $GPG_TTY  # Should show something like /dev/pts/0
```

**"gpg: Note: trustdb not writable"**

The `~/.gnupg` directory is mounted read-only. Ensure the bubblewrap script uses `--bind` (read-write) not `--ro-bind`:

```bash
# Correct (read-write)
--bind $HOME/.gnupg $HOME/.gnupg

# Wrong (read-only, causes this error)
--ro-bind $HOME/.gnupg $HOME/.gnupg
```

**"gpg: signing failed: No secret key"**

The private key material isn't accessible. Verify:

```bash
# Check if private-keys-v1.d is bound
ls ~/.gnupg/private-keys-v1.d/

# If empty or error, the .gnupg directory isn't properly mounted
```

**"gpg: can't connect to the agent"**

The gpg-agent socket isn't accessible:

```bash
# Find socket location
gpgconf --list-dirs socketdir

# Verify socket exists
ls -la $(gpgconf --list-dirs agent-socket)

# Ensure the socket directory is bound in the sandbox script
```

### Bubblewrap

**"bwrap: No such file or directory"**
```bash
# Install bubblewrap
sudo apt install bubblewrap  # Debian/Ubuntu
```

**"Permission denied" on bind mounts**
```bash
# Check if the directory exists
mkdir -p ~/.claude ~/.npm
```

### Firejail

**"Warning: cannot find profile"**
```bash
# Use --noprofile or install the profile
cp claude.firejail.profile ~/.config/firejail/claude.profile
```

**Whitelist not working**
```bash
# Firejail whitelist requires the path to exist
mkdir -p ~/.claude
```

### Apple Container

**"container: command not found"**
```bash
# Build and install from source
git clone https://github.com/apple/swift-container
cd swift-container && swift build -c release
sudo cp .build/release/container /usr/local/bin/
```

**"Image not found"**
```bash
# Rebuild the image
container build -t claude-sandbox .
```

**SSH agent not working in container**
```bash
# Verify SSH_AUTH_SOCK is set and socket exists
echo $SSH_AUTH_SOCK
ls -la $SSH_AUTH_SOCK
```

---

## Advanced Configuration

### Restricting Network Access

**Firejail - Block all network:**
```bash
firejail --net=none claude
```

**Firejail - Allow only specific hosts:**
Create `/etc/firejail/claude-net.filter`:
```
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]
-A OUTPUT -d api.anthropic.com -p tcp --dport 443 -j ACCEPT
-A OUTPUT -d github.com -p tcp --dport 22 -j ACCEPT
-A OUTPUT -d github.com -p tcp --dport 443 -j ACCEPT
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
COMMIT
```

Then use:
```bash
firejail --netfilter=/etc/firejail/claude-net.filter claude
```

### Adding Project-Specific Paths

If Claude needs access to shared libraries or data outside $PWD:

**Bubblewrap:**
```bash
# Add to the script
--ro-bind /path/to/shared/data /path/to/shared/data
```

**Firejail:**
```bash
./firejail_claude.sh --whitelist=/path/to/shared/data
```

**Apple Container:**
```bash
# Add to container_claude.sh mount_args
mounts+=(--mount "type=bind,src=/path/to/shared/data,dst=/data,readonly")
```

---

## Contributing

Improvements welcome! Areas of interest:

- macOS sandbox-exec implementation (App Sandbox)
- Windows equivalent (Windows Sandbox / WSL)
- Integration with Claude Code's native sandboxing
- Automated security testing

---

## Author

**Patrick McCanna**

Code reviewed with assistance from Claude (Anthropic).

## License

MIT License - See individual files for details.

## Acknowledgments

- [Bubblewrap](https://github.com/containers/bubblewrap) - Unprivileged sandboxing tool
- [Firejail](https://github.com/netblue30/firejail) - SUID sandbox program
- [Apple Container](https://github.com/apple/swift-container) - Swift-based container runtime
- [Anthropic Claude Code](https://github.com/anthropics/claude-code) - The AI assistant being sandboxed
