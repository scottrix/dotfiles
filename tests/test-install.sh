#!/usr/bin/env bash
# Tests for install's option handling and step runner, using fake steps.
# shellcheck disable=SC2317  # test functions are invoked indirectly via t()
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
fail=0
log=$(mktemp)

setup() {
    T=$(mktemp -d)
    export HOME=$T/home DOTFILES_DIR=$T/repo DOTFILES_SKIP_PREFLIGHT=1 DOTFILES_CHOICES=$T/choices
    mkdir -p "$HOME" "$DOTFILES_DIR/steps"
    cp -r "$here/install" "$here/lib" "$DOTFILES_DIR/"
    for s in 10-a 20-b 30-c; do
        # shellcheck disable=SC2016
        printf '#!/usr/bin/env bash\necho "ran %s $BROWSER_ID dry=$DRY_RUN" >> "$HOME/ran"\n' "$s" > "$DOTFILES_DIR/steps/$s.sh"
    done
}
inst() { "$DOTFILES_DIR/install" --no-update --yes "$@"; }

t() {
    local name=$1 rc; shift
    set +e
    ( set -e; setup; "$@" ) > "$log" 2>&1
    rc=$?
    set -e
    if [ "$rc" = 0 ]; then echo "ok   $name"; else echo "FAIL $name"; sed 's/^/     /' "$log"; fail=1; fi
}

help_exits_0() { "$DOTFILES_DIR/install" --help | grep -q -- --dry-run; }
bad_option_fails() { ! inst --bogus; }
runs_all_in_order() { inst; [ "$(cut -d' ' -f2 "$HOME/ran" | tr '\n' ' ')" = "10-a 20-b 30-c " ]; }
passes_choices() { DF_BROWSER=chrome inst --only 10-a; grep -qx "ran 10-a google-chrome dry=0" "$HOME/ran"; }
only_runs_one() { inst --only 20-b; [ "$(cat "$HOME/ran")" = "ran 20-b firefox dry=0" ]; }
from_runs_rest() { inst --from 20-b; [ "$(cut -d' ' -f2 "$HOME/ran" | tr '\n' ' ')" = "20-b 30-c " ]; }
unknown_step_fails() { ! inst --only 99-nope && [ ! -e "$HOME/ran" ]; }
dry_run_flag_exported() { inst --dry-run --only 10-a; grep -q "dry=1" "$HOME/ran"; }
dry_run_saves_nothing() { inst --dry-run --only 10-a; [ ! -e "$DOTFILES_CHOICES" ]; }
saves_choices() { DF_MAIL=none inst --only 10-a; grep -qx "MAIL=none" "$DOTFILES_CHOICES"; }
failing_step_stops_with_hint() {
    printf '#!/usr/bin/env bash\nexit 3\n' > "$DOTFILES_DIR/steps/20-b.sh"
    out=$(inst 2>&1) && return 1
    grep -q -- "--from 20-b" <<< "$out" && ! grep -q "ran 30-c" "$HOME/ran"
}
warnings_in_summary() {
    # shellcheck disable=SC2016
    printf '#!/usr/bin/env bash\n. "$DOTFILES_DIR/lib/common.sh"\nwarn "pkg x skipped" 2>/dev/null\n' > "$DOTFILES_DIR/steps/20-b.sh"
    out=$(inst)
    grep -q "pkg x skipped" <<< "$out"
}
no_tty_fifo_uses_defaults() {
    mkfifo "$T/ff"
    exec 7<> "$T/ff"
    DOTFILES_NO_TTY=1 timeout 10 "$DOTFILES_DIR/install" --no-update --only 10-a <&7
    grep -qx "ran 10-a firefox dry=0" "$HOME/ran"
    grep -qx "MAIL=neomutt" "$DOTFILES_CHOICES" && grep -qx "KB_LAYOUT=gb" "$DOTFILES_CHOICES"
}
no_tty_script_text_not_answers() {
    printf 'line one\nrm -rf x\n' | DOTFILES_NO_TTY=1 timeout 10 "$DOTFILES_DIR/install" --no-update --only 10-a
    grep -qx "KB_LAYOUT=gb" "$DOTFILES_CHOICES"
}
# preflight with a fake Artix/OpenRC system and a fake sudo; SUDO_NEEDS_PW=1 makes sudo want a password
fake_preflight() {
    mkdir -p "$T/bin"
    printf 'ID=artix\n' > "$T/os-release"
    printf '#!/bin/sh\nexit 0\n' > "$T/bin/openrc"
    # shellcheck disable=SC2016  # expands in the fake, not here
    printf '#!/bin/sh\n[ -z "$SUDO_NEEDS_PW" ] || { echo "sudo: a password is required" >&2; exit 1; }\n' > "$T/bin/sudo"
    chmod +x "$T/bin/openrc" "$T/bin/sudo"
}
preflight_inst() {
    PATH="$T/bin:$PATH" DOTFILES_SKIP_PREFLIGHT=0 DOTFILES_OS_RELEASE="$T/os-release" DOTFILES_NO_TTY=1 \
        DOTFILES_SUDO_LOOP=1 "$DOTFILES_DIR/install" --no-update --only 10-a < /dev/null
}
no_tty_password_sudo_explains() {
    [ ! -d /run/systemd/system ] || { echo "skip: systemd host"; return 0; }
    fake_preflight
    out=$(SUDO_NEEDS_PW=1 preflight_inst 2>&1) && return 1
    printf '%s\n' "$out"
    grep -q 'sudo needs a password and there is no terminal: use ssh -t, or passwordless sudo' <<< "$out" &&
        [ ! -e "$HOME/ran" ]
}
no_tty_passwordless_sudo_runs() {
    [ ! -d /run/systemd/system ] || { echo "skip: systemd host"; return 0; }
    fake_preflight
    SUDO_NEEDS_PW='' preflight_inst
    grep -qx "ran 10-a firefox dry=0" "$HOME/ran"
}
# a download cut off anywhere must run nothing: --help shows whether the script body ran
truncated_download_runs_nothing() {
    local size n k
    size=$(wc -c < "$here/install"); n=$(wc -l < "$here/install")
    for ((k = 1; k < n; k++)); do
        if head -n "$k" "$here/install" | bash -s -- --help 2> /dev/null | grep -q usage; then
            echo "cut after line $k ran"; return 1
        fi
    done
    for ((k = size - 12; k < size - 1; k++)); do
        if head -c "$k" "$here/install" | bash -s -- --help 2> /dev/null | grep -q usage; then
            echo "cut after byte $k ran"; return 1
        fi
    done
    bash -s -- --help < "$here/install" | grep -q usage
}

t "--help" help_exits_0
t "unknown option fails" bad_option_fails
t "runs every step in order" runs_all_in_order
t "steps see the resolved choices" passes_choices
t "--only runs one step" only_runs_one
t "--from runs the rest" from_runs_rest
t "unknown step fails before running anything" unknown_step_fails
t "--dry-run reaches the steps" dry_run_flag_exported
t "--dry-run doesn't save answers" dry_run_saves_nothing
t "answers are saved" saves_choices
t "a failing step stops the run with a resume hint" failing_step_stops_with_hint
t "warnings appear in the summary" warnings_in_summary
t "no terminal and open stdin: defaults, no hang" no_tty_fifo_uses_defaults
t "no terminal: piped script text isn't taken as answers" no_tty_script_text_not_answers
t "a truncated download runs nothing" truncated_download_runs_nothing
t "no terminal and sudo wants a password: says so" no_tty_password_sudo_explains
t "no terminal and passwordless sudo: runs" no_tty_passwordless_sudo_runs
exit $fail
