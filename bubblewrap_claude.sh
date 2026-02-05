#!/usr/bin/env bash

# Optional paths - only bind if they exist
OPTIONAL_BINDS=""
[ -d "$HOME/.nvm" ] && OPTIONAL_BINDS="$OPTIONAL_BINDS --ro-bind $HOME/.nvm $HOME/.nvm"
[ -d "$HOME/.config/git" ] && OPTIONAL_BINDS="$OPTIONAL_BINDS --ro-bind $HOME/.config/git $HOME/.config/git"

# SSH agent socket - only bind if SSH_AUTH_SOCK is set and exists
SSH_BINDS=""
SSH_ENV=""
if [ -n "$SSH_AUTH_SOCK" ] && [ -S "$SSH_AUTH_SOCK" ]; then
  SSH_BINDS="--bind $(dirname "$SSH_AUTH_SOCK") $(dirname "$SSH_AUTH_SOCK") --ro-bind $SSH_AUTH_SOCK $SSH_AUTH_SOCK"
  SSH_ENV="--setenv SSH_AUTH_SOCK $SSH_AUTH_SOCK"
fi

# GPG configuration
# Bind the full .gnupg directory (with write access for trustdb updates)
# and the GPG agent socket directory for signing operations
GPG_ENV=""
[ -n "$GPG_SIGNING_KEY_ID" ] && GPG_ENV="--setenv GPG_SIGNING_KEY_ID $GPG_SIGNING_KEY_ID"

GPG_BINDS=""
# Bind the .gnupg directory with write access (needed for trustdb, key operations)
if [ -d "$HOME/.gnupg" ]; then
  GPG_BINDS="--bind $HOME/.gnupg $HOME/.gnupg"
fi

# Bind the GPG agent socket directory (usually /run/user/<uid>/gnupg)
GPG_SOCKDIR=$(gpgconf --list-dirs socketdir 2>/dev/null)
if [ -n "$GPG_SOCKDIR" ] && [ -d "$GPG_SOCKDIR" ]; then
  GPG_BINDS="$GPG_BINDS --bind $GPG_SOCKDIR $GPG_SOCKDIR"
fi

bwrap \
  --ro-bind /usr /usr \
  --ro-bind /lib /lib \
  --ro-bind /lib64 /lib64 \
  --ro-bind /bin /bin \
  --ro-bind /etc/resolv.conf /etc/resolv.conf \
  --ro-bind /etc/hosts /etc/hosts \
  --ro-bind /etc/ssl /etc/ssl \
  --ro-bind /etc/passwd /etc/passwd \
  --ro-bind /etc/group /etc/group \
  --ro-bind "$HOME/.ssh/known_hosts" "$HOME/.ssh/known_hosts" \
  $SSH_BINDS \
  --ro-bind "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_ed25519.pub" \
  --ro-bind /usr/bin/gpg /usr/bin/gpg \
  $GPG_ENV \
  --ro-bind "$HOME/.gitconfig" "$HOME/.gitconfig" \
  $OPTIONAL_BINDS \
  --ro-bind "$HOME/.local" "$HOME/.local" \
  --bind "$HOME/.npm" "$HOME/.npm" \
  --bind "$HOME/.claude" "$HOME/.claude" \
  --bind "$PWD" "$PWD" \
  $GPG_BINDS \
  --tmpfs /tmp \
  --proc /proc \
  --dev /dev \
  --setenv HOME "$HOME" \
  --setenv USER "$USER" \
  $SSH_ENV \
  --share-net \
  --unshare-pid \
  --die-with-parent \
  --chdir "$PWD" \
  "$(which claude)" "$@"
