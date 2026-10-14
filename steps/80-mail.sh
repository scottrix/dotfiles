#!/usr/bin/env bash
# neomutt settings, colours and mailcap, with no accounts; mail-account-add adds them.
set -euo pipefail
# shellcheck source=lib/common.sh
. "$DOTFILES_DIR/lib/common.sh"

if [ "$MAIL" != neomutt ]; then
    say "mail client is $MAIL; nothing to set up"
    exit 0
fi

dir=$HOME/.config/neomutt
link home/.config/neomutt/neomuttrc "$dir/neomuttrc"
link home/.config/neomutt/settings "$dir/settings"
link home/.config/neomutt/colours "$dir/colours"
# shellcheck disable=SC2016
render neomutt/mailcap '${BROWSER_CMD}' | put "$dir/mailcap"
[ -e "$dir/accounts.rc" ] || printf '# accounts added by mail-account-add\n' | put "$dir/accounts.rc" 600
[ -e "$dir/alias" ] || printf '# alias NAME "Full Name" <address>\n' | put "$dir/alias" 600
link bin/mail-account-add "$HOME/bin/mail-account-add"
[ -d "$HOME/.cache/neomutt" ] || run mkdir -p "$HOME/.cache/neomutt"
