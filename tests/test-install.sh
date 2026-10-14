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
exit $fail
