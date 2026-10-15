#!/usr/bin/env bash
# bash, vim (plugins through vim-plug), gpg-agent as the SSH agent, pikaur.
set -euo pipefail
# shellcheck source=lib/common.sh
. "$DOTFILES_DIR/lib/common.sh"

link home/.bashrc "$HOME/.bashrc"
link home/.bash_profile "$HOME/.bash_profile"
link home/.profile "$HOME/.profile"
link home/.vimrc "$HOME/.vimrc"
link home/.config/pikaur.conf "$HOME/.config/pikaur.conf"
if [ ! -d "$HOME/.gnupg" ]; then
    run mkdir -p "$HOME/.gnupg"
    run chmod 700 "$HOME/.gnupg"
fi
link home/.gnupg/gpg-agent.conf "$HOME/.gnupg/gpg-agent.conf"

plug=$HOME/.vim/autoload/plug.vim
if [ ! -s "$plug" ]; then
    run curl -fsSLo "$plug" --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/0.14.0/plug.vim
fi
# vim-plug exits 0 even when a clone failed (a network blip), so check the result and retry once
for try in 1 2; do
    [ ! -d "$HOME/.vim/plugged/vim-airline" ] || break
    [ "$try" = 1 ] || say "retrying the vim plugins"
    run vim -Es -u "$HOME/.vimrc" -i NONE -c 'PlugInstall --sync' -c 'qa' < /dev/null || true
    [ "$DRY_RUN" = 1 ] && break
done
if [ "$DRY_RUN" != 1 ] && [ ! -d "$HOME/.vim/plugged/vim-airline" ]; then
    warn "vim plugins didn't install; open vim and run :PlugInstall"
fi
