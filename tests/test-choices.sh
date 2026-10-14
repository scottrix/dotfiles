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
    export HOME=$T ASSUME_YES=0 XKB_RULES=$T/evdev.lst
    printf '! model\n  pc105  Generic 105-key PC\n\n! layout\n  us   English (US)\n  gb   English (UK)\n  de   German\n\n! variant\n  intl  us: English (US, intl.)\n' > "$XKB_RULES"
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
layout_known() { valid_layout gb && valid_layout gb,us; }
layout_unknown() { ! valid_layout uk && ! valid_layout intl && ! valid_layout pc105 && ! valid_layout 'gb,uk'; }
layout_empty() { ! valid_layout '' && ! valid_layout ',' && ! valid_layout 'gb,' && ! valid_layout 'us intl'; }
layout_no_rules_file() { XKB_RULES=$T/missing; valid_layout anything && ! valid_layout ''; }
ask_layout_reprompts() {
    load_choices "$T/none"
    printf 'firefox\nneomutt\nuk\nde\n' | { ask_choices; [ "$KB_LAYOUT" = de ]; }
}
ask_layout_eof_after_bad_keeps_valid() {
    load_choices "$T/none"; KB_LAYOUT=us
    printf '\n\nuk\n' | { ask_choices; [ "$KB_LAYOUT" = us ]; }
}
yes_bad_layout_dies() {
    ASSUME_YES=1
    load_choices "$T/none"; KB_LAYOUT=uk
    out=$( (ask_choices) 2>&1) && return 1
    grep -q "keyboard layout 'uk'" <<< "$out"
}
yes_empty_layout_dies() { ASSUME_YES=1; load_choices "$T/none"; KB_LAYOUT=''; ! (ask_choices) 2> /dev/null; }

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
t "layout in the XKB list is valid (also as a list)" layout_known
t "layout not in the XKB layout list is invalid" layout_unknown
t "empty layout is invalid" layout_empty
t "without an XKB list any non-empty layout is valid" layout_no_rules_file
t "ask re-asks for an unknown layout" ask_layout_reprompts
t "unknown layout then EOF keeps the last valid one" ask_layout_eof_after_bad_keeps_valid
t "--yes with an unknown layout stops with a clear error" yes_bad_layout_dies
t "--yes with an empty layout stops" yes_empty_layout_dies
exit $fail
