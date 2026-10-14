#!/usr/bin/env bash
# Tests for the user-file helpers in lib/common.sh. No sudo needed.
# shellcheck disable=SC2317  # test functions are invoked indirectly via t()
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
fail=0
log=$(mktemp)

setup() {
    T=$(mktemp -d)
    export HOME=$T/home DOTFILES_DIR=$T/repo DRY_RUN=0
    export BACKUP_DIR=$T/backup WARNINGS_FILE=$T/warnings
    mkdir -p "$HOME" "$DOTFILES_DIR/home" "$DOTFILES_DIR/templates" "$DOTFILES_DIR/packages"
    echo repo > "$DOTFILES_DIR/home/a"
    # shellcheck source=lib/common.sh
    . "$here/lib/common.sh"
}

t() {
    local name=$1 rc; shift
    set +e
    ( set -e; setup; "$@" ) > "$log" 2>&1
    rc=$?
    set -e
    if [ "$rc" = 0 ]; then echo "ok   $name"; else echo "FAIL $name"; sed 's/^/     /' "$log"; fail=1; fi
}

link_creates() { link home/a "$HOME/x"; [ "$(readlink "$HOME/x")" = "$DOTFILES_DIR/home/a" ]; }
link_twice_is_noop() { link home/a "$HOME/x"; link home/a "$HOME/x"; [ ! -e "$BACKUP_DIR" ]; }
link_backs_up_real_file() {
    echo mine > "$HOME/x"
    link home/a "$HOME/x"
    [ -L "$HOME/x" ] && [ "$(cat "$BACKUP_DIR/x")" = mine ]
}
link_dry_run_changes_nothing() { DRY_RUN=1 link home/a "$HOME/x"; [ ! -e "$HOME/x" ] && [ ! -L "$HOME/x" ]; }
put_writes_with_mode() { echo hi | put "$HOME/d/f" 750; [ "$(cat "$HOME/d/f")" = hi ] && [ "$(stat -c %a "$HOME/d/f")" = 750 ]; }
put_same_content_is_noop() { echo hi | put "$HOME/f"; echo hi | put "$HOME/f"; [ ! -e "$BACKUP_DIR" ]; }
put_new_content_backs_up() { echo one | put "$HOME/f"; echo two | put "$HOME/f"; [ "$(cat "$HOME/f")" = two ] && [ "$(cat "$BACKUP_DIR/f")" = one ]; }
put_replaces_symlink() { link home/a "$HOME/f"; echo two | put "$HOME/f"; [ ! -L "$HOME/f" ] && [ "$(cat "$HOME/f")" = two ]; }
render_only_named_vars() {
    # shellcheck disable=SC2016
    printf 'a=${X} b=${Y} c=$HOME\n' > "$DOTFILES_DIR/templates/t"
    # shellcheck disable=SC2016
    [ "$(X=1 Y=2 render t '${X}')" = 'a=1 b=${Y} c=$HOME' ]
}
pkgs_from_strips_comments() {
    printf '# head\nfoo   # why\n\n  \nbar\n' > "$DOTFILES_DIR/packages/l"
    [ "$(pkgs_from l | tr '\n' ' ')" = 'foo bar ' ]
}
pkgs_from_empty_list_ok() { printf '# nothing\n' > "$DOTFILES_DIR/packages/l"; [ -z "$(pkgs_from l)" ]; }
warn_records() { warn "careful" 2>/dev/null; grep -qx careful "$WARNINGS_FILE"; }

t "link creates a symlink" link_creates
t "link twice is a no-op" link_twice_is_noop
t "link backs up a real file" link_backs_up_real_file
t "link --dry-run changes nothing" link_dry_run_changes_nothing
t "put writes with mode" put_writes_with_mode
t "put same content is a no-op" put_same_content_is_noop
t "put new content backs up old" put_new_content_backs_up
t "put replaces a symlink" put_replaces_symlink
t "render substitutes only named vars" render_only_named_vars
t "pkgs_from strips comments and blanks" pkgs_from_strips_comments
t "pkgs_from on an empty list" pkgs_from_empty_list_ok
t "warn records the warning" warn_records
exit $fail
