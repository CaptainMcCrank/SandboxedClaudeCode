#!/usr/bin/env bash

# Optional paths - only bind if they exist
OPTIONAL_BINDS=""
[ -d "$HOME/.nvm" ] && OPTIONAL_BINDS="$OPTIONAL_BINDS --ro-bind $HOME/.nvm $HOME/.nvm"
[ -d "$HOME/.config/git" ] && OPTIONAL_BINDS="$OPTIONAL_BINDS --ro-bind $HOME/.config/git $HOME/.config/git"

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
  --bind "$(dirname $SSH_AUTH_SOCK)" "$(dirname $SSH_AUTH_SOCK)" \
  --ro-bind "$HOME/.gitconfig" "$HOME/.gitconfig" \
  $OPTIONAL_BINDS \
  --ro-bind "$HOME/.local" "$HOME/.local" \
  --bind "$HOME/.npm" "$HOME/.npm" \
  --bind "$HOME/.claude" "$HOME/.claude" \
  --bind "$PWD" "$PWD" \
  --tmpfs /tmp \
  --proc /proc \
  --dev /dev \
  --setenv HOME "$HOME" \
  --setenv USER "$USER" \
  --setenv SSH_AUTH_SOCK "$SSH_AUTH_SOCK" \
  --share-net \
  --unshare-pid \
  --die-with-parent \
  --chdir "$PWD" \
  "$(which claude)" "$@"
