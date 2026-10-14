#!/usr/bin/env bash
# Tests for steps/40-session.sh against a pristine lightdm.conf with fake system commands.
# shellcheck disable=SC2317  # test functions are invoked indirectly via t()
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
fail=0
log=$(mktemp)

setup() {
    T=$(mktemp -d)
    F=$T/fake; mkdir -p "$F/bin" "$T/home"
    CMDLOG=$F/cmds; : > "$CMDLOG"
    cp "$here/tests/fixtures/lightdm.conf" "$T/lightdm.conf"
    : > "$F/system"
    local c
    for c in sudo rc-update; do
        cat > "$F/bin/$c" << 'FAKE'
#!/usr/bin/env bash
c=$(basename "$0"); F=$FAKE
case "$c" in
sudo) echo "sudo $*" >> "$F/cmds"; "$@"; exit ;;
rc-update)
    case "$1" in
    show) cat "$F/system" ;;
    add) echo "rc-update $*" >> "$F/cmds"; echo "$2 | $3" >> "$F/system" ;;
    --user) echo "rc-update $*" >> "$F/cmds"
            mkdir -p "$HOME/.config/rc/runlevels/default"; touch "$HOME/.config/rc/runlevels/default/$3" ;;
    esac ;;
esac
FAKE
        chmod +x "$F/bin/$c"
    done
}

run_step() {
    env FAKE="$F" PATH="$F/bin:$PATH" HOME="$T/home" DOTFILES_DIR="$here" \
        LIGHTDM_CONF="$T/lightdm.conf" XORG_KB_CONF="$T/xorg.conf.d/00-keyboard.conf" KB_LAYOUT=gb \
        BACKUP_DIR="$T/bak" WARNINGS_FILE="$T/warn" \
        "$@" bash "$here/steps/40-session.sh"
}
seat() { sed -n '/^\[Seat:\*\]/,/^\[[^S]/p' "$T/lightdm.conf"; }

sets_options() {
    run_step DRY_RUN=0 > /dev/null
    seat | grep -qx 'user-session=labwc' && seat | grep -qx 'greeter-session=lightdm-gtk-greeter' &&
        [ "$(grep -c '^user-session=' "$T/lightdm.conf")" = 1 ] &&
        [ -e "$T/lightdm.conf.dotfiles-bak" ] &&
        cmp -s "$T/lightdm.conf.dotfiles-bak" "$here/tests/fixtures/lightdm.conf"
}
writes_dmrc() {
    run_step DRY_RUN=0 > /dev/null
    [ "$(cat "$T/home/.dmrc")" = "$(printf '[Desktop]\nSession=labwc')" ]
}
second_run_is_quiet() {
    local out before after
    run_step DRY_RUN=0 > /dev/null
    before=$(cat "$T/lightdm.conf" "$T/home/.dmrc" "$T/xorg.conf.d/00-keyboard.conf"; ls -A "$T" "$T/home")
    : > "$CMDLOG"
    out=$(run_step DRY_RUN=0 2>&1)
    after=$(cat "$T/lightdm.conf" "$T/home/.dmrc" "$T/xorg.conf.d/00-keyboard.conf"; ls -A "$T" "$T/home")
    [ -z "$out" ] && [ "$before" = "$after" ] && [ ! -e "$T/bak" ] &&
        ! grep -q 'rc-update' "$CMDLOG"
}
dry_run_changes_nothing() {
    local before after out
    before=$(cat "$T/lightdm.conf"; ls -A "$T" "$T/home")
    out=$(run_step DRY_RUN=1 2>&1)
    after=$(cat "$T/lightdm.conf"; ls -A "$T" "$T/home")
    [ "$before" = "$after" ] && [ ! -e "$T/home/.dmrc" ] && [ ! -e "$T/lightdm.conf.dotfiles-bak" ] &&
        [ ! -e "$T/xorg.conf.d" ] &&
        ! grep -Eq 'rc-update (add|--user)|sudo (sed|cp)' "$CMDLOG" &&
        grep -q 'dry-run' <<< "$out"
}
greeter_keyboard_layout() {
    run_step DRY_RUN=0 KB_LAYOUT=de > /dev/null
    local f=$T/xorg.conf.d/00-keyboard.conf
    grep -qx '    Option "XkbLayout" "de"' "$f" && grep -qx '    MatchIsKeyboard "on"' "$f" &&
        grep -qx 'Section "InputClass"' "$f" && grep -qx 'EndSection' "$f"
}
user_services_only_when_missing() {
    local d=$T/home/.config/rc/runlevels/default
    mkdir -p "$d"; touch "$d/pipewire" "$d/wireplumber"
    run_step DRY_RUN=0 > /dev/null
    grep -qx 'rc-update --user add dbus default' "$CMDLOG" &&
        grep -qx 'rc-update --user add pipewire-pulse default' "$CMDLOG" &&
        ! grep -q 'rc-update --user add pipewire default' "$CMDLOG" &&
        ! grep -q 'rc-update --user add wireplumber default' "$CMDLOG" &&
        [ "$(grep -c -e '--user add' "$CMDLOG")" = 2 ]
}
all_four_user_services() {
    run_step DRY_RUN=0 > /dev/null
    local s
    for s in dbus pipewire pipewire-pulse wireplumber; do
        grep -qx "rc-update --user add $s default" "$CMDLOG" || return 1
    done
}
warns_on_other_dm() {
    echo 'sddm | default' >> "$F/system"
    run_step DRY_RUN=0 > /dev/null 2>&1
    grep -q 'sddm is also enabled' "$T/warn"
}

t() {
    local name=$1 rc; shift
    set +e
    ( set -e; setup; "$@" ) > "$log" 2>&1
    rc=$?
    set -e
    if [ "$rc" = 0 ]; then echo "ok   $name"; else echo "FAIL $name"; sed 's/^/     /' "$log"; fail=1; fi
}

t "user-session and greeter-session land in [Seat:*]" sets_options
t ".dmrc written in HOME" writes_dmrc
t "second run changes nothing and prints nothing" second_run_is_quiet
t "dry run changes nothing" dry_run_changes_nothing
t "greeter (Xorg) gets the chosen keyboard layout" greeter_keyboard_layout
t "user services added only when links are missing" user_services_only_when_missing
t "all four user services added on a fresh home" all_four_user_services
t "other display manager is warned about" warns_on_other_dm
exit $fail
