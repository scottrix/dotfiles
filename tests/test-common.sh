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
# Fake rc-update (show only) and sudo (logs its args) on PATH; no real system touched.
fake_openrc() {
    mkdir -p "$T/bin"
    cat > "$T/bin/rc-update" <<'EOF'
#!/bin/sh
printf '                 net.lo | default\n                 sshd | default\n'
EOF
    cat > "$T/bin/sudo" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$T/sudo.log"
EOF
    chmod +x "$T/bin/rc-update" "$T/bin/sudo"
    export PATH="$T/bin:$PATH"
}
# Fake sudo that runs its command, for the system-file helpers.
fake_sudo() {
    mkdir -p "$T/bin"
    printf '#!/bin/sh\nexec "$@"\n' > "$T/bin/sudo"
    chmod +x "$T/bin/sudo"
    export PATH="$T/bin:$PATH"
}
# A dry run says what it would do and never prints the words that report a real change.
dry_run_says_would() {
    fake_sudo
    echo mine > "$HOME/x"; echo old > "$T/sys"
    out=$(
        export DRY_RUN=1
        link home/a "$HOME/x"
        echo new | put "$HOME/x"
        backup "$HOME/x"
        echo new | sys_put "$T/sys"
        echo new | sys_put "$T/sys2"
        sys_line "$T/sys" 'a line'
    )
    printf '%s\n' "$out"
    [ "$(cat "$HOME/x")" = mine ] && [ "$(cat "$T/sys")" = old ] && [ ! -e "$T/sys2" ] &&
        [ ! -e "$T/sys.dotfiles-bak" ] && [ ! -e "$BACKUP_DIR" ] &&
        ! grep -Eq 'linked|wrote|backed up|added' <<< "$out" &&
        [ "$(grep -c '^    \[dry-run\] would ' <<< "$out")" = "$(wc -l <<< "$out")" ] &&
        grep -q "would link $HOME/x" <<< "$out" && grep -q "would write $T/sys2" <<< "$out" &&
        grep -q "would back up $HOME/x" <<< "$out" && grep -q "would back up $T/sys to $T/sys.dotfiles-bak" <<< "$out"
}
sys_line_after_missing_newline() {
    fake_sudo
    printf 'option ntp_servers' > "$T/conf"
    sys_line "$T/conf" 'denyinterfaces wlan*'
    sys_line "$T/conf" 'denyinterfaces wlan*'
    [ "$(cat "$T/conf")" = "$(printf 'option ntp_servers\ndenyinterfaces wlan*')" ] &&
        [ "$(tail -c1 "$T/conf" | od -An -c | tr -d ' ')" = '\n' ]
}
sys_line_appends_once() {
    fake_sudo
    printf 'a\n' > "$T/conf"
    sys_line "$T/conf" b; sys_line "$T/conf" b
    [ "$(cat "$T/conf")" = "$(printf 'a\nb')" ] && [ "$(cat "$T/conf.dotfiles-bak")" = a ]
}
svc_add_enables_missing() { fake_openrc; svc_add net default; grep -qx 'rc-update add net default' "$T/sudo.log"; }
svc_add_skips_enabled() { fake_openrc; svc_add sshd default; [ ! -e "$T/sudo.log" ]; }

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
t "dry run prints only '[dry-run] would ...'" dry_run_says_would
t "sys_line starts a new line when the file lacks a final newline" sys_line_after_missing_newline
t "sys_line appends once and keeps the original" sys_line_appends_once
t "svc_add enables a service whose name prefixes an enabled one" svc_add_enables_missing
t "svc_add skips an already enabled service" svc_add_skips_enabled
exit $fail
