#!/usr/bin/env bash
# Test functions are invoked indirectly through t, hence SC2317.
# shellcheck disable=SC2317
# Tests for lib/choices.sh.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
fail=0
log=$(mktemp)

setup() {
    T=$(mktemp -d)
    export HOME=$T ASSUME_YES=0
    unset DF_BROWSER DF_MAIL DF_KB_LAYOUT
    # shellcheck source=lib/common.sh
    . "$here/lib/common.sh"
    # shellcheck source=lib/choices.sh
    . "$here/lib/choices.sh"
}

t() {
    local name=$1 rc; shift
    set +e
    ( set -e; setup; "$@" ) > "$log" 2>&1
    rc=$?
    set -e
    if [ "$rc" = 0 ]; then echo "ok   $name"; else echo "FAIL $name"; sed 's/^/     /' "$log"; fail=1; fi
}

defaults() { load_choices "$T/none"; [ "$BROWSER $MAIL $KB_LAYOUT" = "firefox neomutt gb" ]; }
saved_round_trip() {
    load_choices "$T/c"; BROWSER=chrome MAIL=none KB_LAYOUT="us intl"
    save_choices "$T/c"; BROWSER=x; load_choices "$T/c"
    [ "$BROWSER $MAIL $KB_LAYOUT" = "chrome none us intl" ]
}
env_overrides_saved() {
    printf 'BROWSER=chrome\n' > "$T/c"
    DF_BROWSER=librewolf load_choices "$T/c"
    [ "$BROWSER" = librewolf ]
}
ask_takes_answer() { BROWSER=firefox; ask BROWSER Browser firefox chrome <<< chrome; [ "$BROWSER" = chrome ]; }
ask_enter_keeps_current() { BROWSER=chrome; ask BROWSER Browser firefox chrome <<< ""; [ "$BROWSER" = chrome ]; }
ask_reprompts_on_bad_answer() { BROWSER=firefox; printf 'opera\nchrome\n' | { ask BROWSER Browser firefox chrome; [ "$BROWSER" = chrome ]; }; }
ask_eof_keeps_current() { BROWSER=chrome; ask BROWSER Browser firefox chrome < /dev/null; [ "$BROWSER" = chrome ]; }
ask_yes_does_not_read() { ASSUME_YES=1; BROWSER=chrome; ask BROWSER Browser firefox chrome <<< firefox; [ "$BROWSER" = chrome ]; }
resolve_chrome() {
    BROWSER=chrome MAIL=neomutt KB_LAYOUT=gb; resolve_choices
    [ "$BROWSER_PKG $BROWSER_FROM $BROWSER_CMD $BROWSER_ID" = "google-chrome aur google-chrome-stable google-chrome" ] &&
        [ "$MAIL_CMD|$MAIL_ID" = "foot --app-id=mail neomutt|mail" ]
}
resolve_librewolf() {
    BROWSER=librewolf MAIL=none KB_LAYOUT=gb; resolve_choices
    [ "$BROWSER_PKG $BROWSER_FROM $BROWSER_CMD $BROWSER_ID" = "librewolf repo librewolf librewolf" ]
}
resolve_none_mail() { BROWSER=firefox MAIL=none KB_LAYOUT=gb; resolve_choices; [ -z "$MAIL_CMD$MAIL_ID" ]; }
resolve_rejects_unknown() { BROWSER=opera MAIL=none KB_LAYOUT=gb; ! ( resolve_choices ) 2>/dev/null; }

t "defaults" defaults
t "saved answers round-trip" saved_round_trip
t "DF_ env overrides saved answers" env_overrides_saved
t "ask takes a valid answer" ask_takes_answer
t "ask: Enter keeps the current value" ask_enter_keeps_current
t "ask re-prompts on a bad answer" ask_reprompts_on_bad_answer
t "ask: no terminal (EOF) keeps the current value" ask_eof_keeps_current
t "ask with --yes doesn't read" ask_yes_does_not_read
t "resolve chrome + neomutt" resolve_chrome
t "resolve librewolf from the repo" resolve_librewolf
t "resolve mail=none" resolve_none_mail
t "resolve rejects an unknown browser" resolve_rejects_unknown
exit $fail
