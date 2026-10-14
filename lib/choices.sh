# shellcheck shell=bash
# The install questions: saved answers, asking, and what each answer means.

BROWSERS="firefox chrome librewolf"
MAILERS="neomutt thunderbird none"

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

ask_choices() {
    # shellcheck disable=SC2086
    ask BROWSER "Browser" $BROWSERS
    # shellcheck disable=SC2086
    ask MAIL "Mail client" $MAILERS
    ask KB_LAYOUT "Keyboard layout"
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
        librewolf) BROWSER_PKG=librewolf-bin BROWSER_FROM=aur BROWSER_CMD=librewolf BROWSER_ID=librewolf BROWSER_LABEL=LibreWolf ;;
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
