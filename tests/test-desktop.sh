#!/usr/bin/env bash
# Run steps/50-desktop.sh into a temp home and check the result.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
fail=0

run_step() {  # run_step BROWSER MAIL
    T=$(mktemp -d)
    export HOME=$T/home DOTFILES_DIR=$here DRY_RUN=0 BACKUP_DIR=$T/backup WARNINGS_FILE=$T/w
    mkdir -p "$HOME"
    # shellcheck source=lib/common.sh
    . "$here/lib/common.sh"
    # shellcheck source=lib/choices.sh
    . "$here/lib/choices.sh"
    BROWSER=$1 MAIL=$2 KB_LAYOUT=gb
    resolve_choices
    bash "$here/steps/50-desktop.sh" > /dev/null
}

expect() {  # expect NAME CMD...
    local name=$1; shift
    if "$@" > /dev/null 2>&1; then echo "ok   $name"; else echo "FAIL $name"; fail=1; fi
}

(
    run_step chrome neomutt
    bash "$here/tests/check-installed.sh" desktop
    c=$HOME/.config
    expect "chrome rule on Web" grep -Pzq 'identifier="google-chrome" matchOnce="true">\s*<action name="SendToDesktop" to="2"' "$c/labwc/rc.xml"
    expect "mail rule on Mail" grep -Pzq 'identifier="mail" matchOnce="true">\s*<action name="SendToDesktop" to="3"' "$c/labwc/rc.xml"
    expect "startup runs chrome" grep -qx 'google-chrome-stable &>/dev/null &' "$HOME/bin/labwc_startup"
    expect "startup runs neomutt" grep -qx 'foot --app-id=mail neomutt &>/dev/null &' "$HOME/bin/labwc_startup"
    expect "menu has Chrome" grep -q '<item label="Chrome">' "$c/labwc/menu.xml"
    expect "keyboard layout" grep -qx 'XKB_DEFAULT_LAYOUT=gb' "$c/labwc/environment"
    expect "re-run changes nothing" bash -c "bash '$here/steps/50-desktop.sh' | grep -q . && exit 1 || exit 0"
) || fail=1

(
    run_step firefox none
    c=$HOME/.config
    expect "no mail rule" bash -c "! grep -q 'identifier=\"mail\"' '$c/labwc/rc.xml'"
    expect "no mail in startup" bash -c "! grep -q neomutt '$HOME/bin/labwc_startup'"
    expect "no Mail menu item" bash -c "! grep -q 'label=\"Mail\"' '$c/labwc/menu.xml'"
    expect "rc.xml still valid" xmllint --noout "$c/labwc/rc.xml"
) || fail=1

exit $fail
