#!/usr/bin/env bash
# Run steps/50-desktop.sh into a temp home and check the result.
# shellcheck disable=SC2317  # block functions are invoked indirectly via block()
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

expect() {  # expect NAME CMD...  a failed check is reported and recorded; the block goes on
    local name=$1; shift
    if "$@" > /dev/null 2>&1; then echo "ok   $name"; else echo "FAIL $name"; fail=1; fi
}

# block NAME FUNC  run FUNC in a subshell under set -e: any failing command
# (not an expect) stops it, and a failed expect inside it fails the test
block() {
    local rc
    set +e
    ( set -e; fail=0; "$2"; exit "$fail" )
    rc=$?
    set -e
    if [ "$rc" != 0 ]; then
        echo "FAIL $1 (block exited $rc)"
        fail=1
    fi
}

chrome_neomutt() {
    run_step chrome neomutt
    bash "$here/tests/check-installed.sh" desktop || fail=1
    c=$HOME/.config
    expect "chrome rule on Web" grep -Pzq 'identifier="google-chrome" matchOnce="true">\s*<action name="SendToDesktop" to="2"' "$c/labwc/rc.xml"
    expect "mail rule on Mail" grep -Pzq 'identifier="mail" matchOnce="true">\s*<action name="SendToDesktop" to="3"' "$c/labwc/rc.xml"
    expect "startup runs chrome" grep -qx 'google-chrome-stable &>/dev/null &' "$HOME/bin/labwc_startup"
    expect "startup runs neomutt" grep -qx 'foot --app-id=mail neomutt &>/dev/null &' "$HOME/bin/labwc_startup"
    expect "menu has Chrome" grep -q '<item label="Chrome">' "$c/labwc/menu.xml"
    expect "keyboard layout" grep -qx 'XKB_DEFAULT_LAYOUT=gb' "$c/labwc/environment"
    expect "re-run changes nothing" bash -c "bash '$here/steps/50-desktop.sh' | grep -q . && exit 1 || exit 0"
}

firefox_none() {
    run_step firefox none
    c=$HOME/.config
    expect "no mail rule" bash -c "! grep -q 'identifier=\"mail\"' '$c/labwc/rc.xml'"
    expect "no mail in startup" bash -c "! grep -q neomutt '$HOME/bin/labwc_startup'"
    expect "no Mail menu item" bash -c "! grep -q 'label=\"Mail\"' '$c/labwc/menu.xml'"
    expect "rc.xml still valid" xmllint --noout "$c/labwc/rc.xml"
}

# the layout list only exists once 20-packages has run, so 50-desktop checks the answer again
unknown_layout_warned() {
    local rules
    rules=$(mktemp)
    printf '! layout\n  us   English (US)\n  de   German\n\n! variant\n  gb  us: not a layout\n' > "$rules"
    export XKB_RULES=$rules
    run_step firefox none
    expect "unknown layout is warned about" grep -q "keyboard layout 'gb' isn't in the XKB layout list" "$WARNINGS_FILE"
    expect "warning says how to fix it" grep -q 'install --from 40-session' "$WARNINGS_FILE"
    printf '! layout\n  gb   English (UK)\n' > "$rules"
    rm -f "$WARNINGS_FILE"
    bash "$here/steps/50-desktop.sh" > /dev/null
    expect "known layout: no warning" test ! -s "$WARNINGS_FILE"
}

block "chrome + neomutt" chrome_neomutt
block "firefox + none" firefox_none
block "layout checked against the installed XKB list" unknown_layout_warned
exit $fail
