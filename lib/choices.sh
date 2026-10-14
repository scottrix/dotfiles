# shellcheck shell=bash
# The install questions: saved answers, asking, and what each answer means.

BROWSERS="firefox chrome librewolf"
MAILERS="neomutt thunderbird none"
XKB_RULES=${XKB_RULES:-/usr/share/X11/xkb/rules/evdev.lst}

# load_choices FILE  defaults, then saved answers, then DF_* environment overrides
load_choices() {
    BROWSER=firefox MAIL=neomutt KB_LAYOUT=gb
    # shellcheck disable=SC1090
    if [ -f "$1" ]; then . "$1"; fi
    BROWSER=${DF_BROWSER:-$BROWSER}
    MAIL=${DF_MAIL:-$MAIL}
    KB_LAYOUT=${DF_KB_LAYOUT:-$KB_LAYOUT}
}

# ask VAR QUESTION [OPTIONS...]  read an answer from stdin; Enter or EOF keeps VAR
ask() {
    local var=$1 question=$2 answer
    shift 2
    [ "${ASSUME_YES:-0}" = 1 ] && return 0
    while :; do
        if [ $# -gt 0 ]; then
            printf '%s (%s) [%s]: ' "$question" "$*" "${!var}"
        else
            printf '%s [%s]: ' "$question" "${!var}"
        fi
        if ! read -r answer; then
            echo
            return 0
        fi
        answer=${answer:-${!var}}
        if [ $# -eq 0 ] || [[ " $* " == *" $answer "* ]]; then
            printf -v "$var" '%s' "$answer"
            return 0
        fi
        echo "  please answer one of: $*"
    done
}

# valid_layout LAYOUT  one or more comma-separated XKB layouts (gb, gb,us), each
# listed in the '! layout' section of XKB_RULES when that file exists
valid_layout() {
    [[ $1 =~ ^[^,[:space:]]+(,[^,[:space:]]+)*$ ]] || return 1
    [ -f "$XKB_RULES" ] || return 0
    local l parts
    IFS=, read -ra parts <<< "$1"
    for l in "${parts[@]}"; do
        awk -v l="$l" '/^!/ { s = ($2 == "layout"); next } s && $1 == l { f = 1 } END { exit !f }' "$XKB_RULES" ||
            return 1
    done
}

ask_choices() {
    # shellcheck disable=SC2086
    ask BROWSER "Browser" $BROWSERS
    # shellcheck disable=SC2086
    ask MAIL "Mail client" $MAILERS
    # a typo (uk for gb) would make labwc fall back to us without a word
    local good=$KB_LAYOUT tries
    valid_layout "$good" || good=gb
    for ((tries = 1; ; tries++)); do
        ask KB_LAYOUT "Keyboard layout"
        valid_layout "$KB_LAYOUT" && return 0
        if [ "${ASSUME_YES:-0}" = 1 ] || [ "$tries" -ge 5 ]; then
            die "keyboard layout '$KB_LAYOUT' isn't a known XKB layout (see the '! layout' section of $XKB_RULES); answer the question, or set DF_KB_LAYOUT"
        fi
        echo "  '$KB_LAYOUT' isn't a known XKB layout; try e.g. gb, us or de"
        KB_LAYOUT=$good
    done
}

save_choices() {
    mkdir -p "$(dirname "$1")"
    printf 'BROWSER=%q\nMAIL=%q\nKB_LAYOUT=%q\n' "$BROWSER" "$MAIL" "$KB_LAYOUT" > "$1"
}

# resolve_choices  turn the answers into packages, commands and window app ids
resolve_choices() {
    case $BROWSER in
        firefox) BROWSER_PKG=firefox BROWSER_FROM=repo BROWSER_CMD=firefox BROWSER_ID=firefox BROWSER_LABEL=Firefox ;;
        chrome) BROWSER_PKG=google-chrome BROWSER_FROM=aur BROWSER_CMD=google-chrome-stable BROWSER_ID=google-chrome BROWSER_LABEL=Chrome ;;
        librewolf) BROWSER_PKG=librewolf BROWSER_FROM=repo BROWSER_CMD=librewolf BROWSER_ID=librewolf BROWSER_LABEL=LibreWolf ;;
        *) die "unknown browser '$BROWSER' (choose: $BROWSERS)" ;;
    esac
    case $MAIL in
        neomutt) MAIL_CMD="foot --app-id=mail neomutt" MAIL_ID=mail MAIL_LABEL=Mail ;;
        thunderbird) MAIL_CMD=thunderbird MAIL_ID=thunderbird MAIL_LABEL=Thunderbird ;;
        none) MAIL_CMD='' MAIL_ID='' MAIL_LABEL='' ;;
        *) die "unknown mail client '$MAIL' (choose: $MAILERS)" ;;
    esac
    export BROWSER MAIL KB_LAYOUT BROWSER_PKG BROWSER_FROM BROWSER_CMD BROWSER_ID BROWSER_LABEL MAIL_CMD MAIL_ID MAIL_LABEL
}
