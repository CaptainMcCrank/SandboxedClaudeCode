# claude.firejail.profile
#
# Firejail profile for Claude Code
#
# Installation:
#   Copy to ~/.config/firejail/claude.profile
#   Then run: firejail claude
#
# Or use directly:
#   firejail --profile=claude.firejail.profile claude
#

# ============================================================================
# SECURITY HARDENING
# ============================================================================

# Drop all capabilities - Claude doesn't need elevated privileges
caps.drop all

# Prevent privilege escalation
nonewprivs
noroot

# Enable seccomp syscall filtering with default blocklist
seccomp

# Disable potentially dangerous features
nodvd
nosound
no3d
notv
nou2f
novideo
nogroups

# Memory protections
# memory-deny-write-execute  # Uncomment if Claude works with it

# ============================================================================
# FILESYSTEM ISOLATION
# ============================================================================

# Start with a restrictive base
include disable-common.inc
include disable-programs.inc
include disable-shell.inc

# Private temporary filesystem (isolated /tmp)
private-tmp

# Minimal /dev (only null, zero, full, random, urandom, tty, etc.)
private-dev

# Disable access to removable media
disable-mnt

# ============================================================================
# WHITELIST - WRITABLE PATHS
# ============================================================================

# Claude's configuration and state directory
whitelist ${HOME}/.claude
# Allow creating the directory if it doesn't exist
mkdir ${HOME}/.claude

# NPM cache for package operations
whitelist ${HOME}/.npm
mkdir ${HOME}/.npm

# Current working directory - where Claude does its work
# Note: ${PWD} is resolved at firejail startup
whitelist ${PWD}

# ============================================================================
# WHITELIST - READ-ONLY PATHS
# ============================================================================

# Git configuration
read-only ${HOME}/.gitconfig
read-only ${HOME}/.config/git

# SSH known hosts (for git operations)
read-only ${HOME}/.ssh/known_hosts

# Node.js version managers (read-only access to runtime)
read-only ${HOME}/.nvm
read-only ${HOME}/.volta
read-only ${HOME}/.local

# Local binaries and libraries
read-only ${HOME}/.local/bin
read-only ${HOME}/.local/lib

# ============================================================================
# NETWORK
# ============================================================================

# Network access is REQUIRED for Claude API calls
# Do not add: net none

# DNS access
# (enabled by default)

# ============================================================================
# ENVIRONMENT
# ============================================================================

# Preserve essential environment variables
# (firejail preserves most by default, but we're explicit)

# Shell settings
shell none

# ============================================================================
# D-BUS
# ============================================================================

# Disable D-Bus access (Claude doesn't need desktop integration)
dbus-user none
dbus-system none

# ============================================================================
# ADDITIONAL HARDENING (OPTIONAL)
# ============================================================================

# Uncomment these for additional security at potential cost of functionality:

# Disable all network except specific hosts:
# netfilter /etc/firejail/claude-net.filter

# Private /etc (may break some functionality):
# private-etc alternatives,ca-certificates,crypto-policies,host.conf,hostname,hosts,ld.so.cache,ld.so.conf,ld.so.conf.d,ld.so.preload,locale,locale.alias,locale.conf,localtime,login.defs,mime.types,nsswitch.conf,passwd,pki,protocols,resolv.conf,rpc,services,ssl,xdg

# Restrict /proc information:
# private-proc
