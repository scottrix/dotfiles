#!/usr/bin/env bash
# Check an installed home directory: configs exist and parse.
# usage: tests/check-installed.sh [desktop] [shell] [mail]   (default: all)
# shellcheck disable=SC2317  # section functions are invoked indirectly via "$s"
# Checks whose tool isn't installed are skipped, not failed.
set -uo pipefail
c=$HOME/.config
fail=0
check() {
    local name=$1; shift
    if "$@" > /dev/null 2>&1; then echo "ok   $name"; else echo "FAIL $name"; fail=1; fi
}
needs() { command -v "$1" > /dev/null || { echo "skip ${*:2} ($1 not installed)"; return 1; }; }

desktop() {
    for f in labwc/rc.xml labwc/menu.xml labwc/autostart labwc/environment waybar/config.jsonc waybar/style.css foot/foot.ini mako/config; do
        check "$f exists" test -s "$c/$f"
    done
    check "theme exists" test -s "$HOME/.local/share/themes/Clearlooks-3.4/openbox-3/themerc"
    check "lock is executable" test -x "$HOME/bin/lock"
    check "labwc_startup is executable" test -x "$HOME/bin/labwc_startup"
    check "labwc_startup parses" bash -n "$HOME/bin/labwc_startup"
    check "environment sets the user bus" grep -qx "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus" "$c/labwc/environment"
    check "desktops are Main, Web, Mail" grep -Pzq '<name>Main</name>\s*<name>Web</name>\s*<name>Mail</name>' "$c/labwc/rc.xml"
    check "touchpad: no tap, clickfinger" grep -Pzq '<tap>no</tap>\s*<clickMethod>clickfinger</clickMethod>' "$c/labwc/rc.xml"
    check "9 terminal rules" test "$(grep -c 'identifier="startterm-' "$c/labwc/rc.xml")" = 9
    if needs xmllint "XML checks"; then
        check "rc.xml is valid XML" xmllint --noout "$c/labwc/rc.xml"
        check "menu.xml is valid XML" xmllint --noout "$c/labwc/menu.xml"
    fi
    if needs python3 "waybar JSON check"; then
        check "waybar config parses" python3 -c '
import json, re, sys
text = open(sys.argv[1]).read()
json.loads(re.sub(r"^\s*//.*$", "", text, flags=re.M))' "$c/waybar/config.jsonc"
    fi
    if needs foot "foot check"; then check "foot.ini is valid" foot --check-config; fi
    check "mako matches the desktop blue" grep -qx 'border-color=#006688' "$c/mako/config"
}

shell() {
    for f in .bashrc .bash_profile .profile .vimrc .gnupg/gpg-agent.conf .config/pikaur.conf; do
        check "$f exists" test -s "$HOME/$f"
    done
    check ".bashrc parses" bash -n "$HOME/.bashrc"
    check "vim-plug installed" test -s "$HOME/.vim/autoload/plug.vim"
    check "vim plugins installed" test -d "$HOME/.vim/plugged/vim-airline"
    if needs vim "vimrc check"; then
        check "vimrc loads without errors" bash -c "vim -Es -u '$HOME/.vimrc' -i NONE -c 'qa!' < /dev/null"
    fi
}

mail() {
    [ -e "$c/neomutt/neomuttrc" ] || { echo "skip mail (neomutt not configured)"; return 0; }
    for f in neomuttrc settings colours mailcap accounts.rc alias; do
        check "neomutt/$f exists" test -e "$c/neomutt/$f"
    done
    check "mail-account-add is executable" test -x "$HOME/bin/mail-account-add"
    if needs neomutt "neomutt check"; then
        check "neomuttrc loads" bash -c "env -u XDG_CONFIG_HOME -u XDG_CACHE_HOME neomutt -n -F '$c/neomutt/neomuttrc' -Q editor < /dev/null"
    fi
}

sections=("$@")
[ ${#sections[@]} -gt 0 ] || sections=(desktop shell mail)
for s in "${sections[@]}"; do "$s"; done
exit $fail
