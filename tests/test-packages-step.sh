#!/usr/bin/env bash
# Tests for steps/20-packages.sh with fake pacman, pikaur and sudo; nothing is installed.
# shellcheck disable=SC2317  # test functions are invoked indirectly via t()
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
fail=0
log=$(mktemp)

setup() {
    T=$(mktemp -d)
    F=$T/fake; mkdir -p "$F/bin"
    : > "$F/installed"
    local c
    for c in sudo pacman pikaur; do
        cat > "$F/bin/$c" << 'FAKE'
#!/usr/bin/env bash
c=$(basename "$0"); F=$FAKE
case "$c" in
sudo) "$@"; exit ;;
pacman)
    case "$1" in
    -Q) grep -qx "$2" "$F/installed"; exit ;;
    -Qq) cat "$F/installed"; exit ;;
    -S) echo "PACMAN $*"; exit 0 ;;
    esac ;;
pikaur) exit 0 ;;
esac
FAKE
        chmod +x "$F/bin/$c"
    done
}

run_step() {
    env FAKE="$F" PATH="$F/bin:$PATH" DOTFILES_DIR="$here" DRY_RUN=0 MAIL=none \
        BROWSER_FROM=repo BROWSER_PKG=firefox BACKUP_DIR="$T/bak" WARNINGS_FILE="$T/warn" \
        bash "$here/steps/20-packages.sh" 2>&1
}

pulseaudio_warned_before_pacman() {
    printf 'pulseaudio\npulseaudio-bluetooth\nlibpulse\n' > "$F/installed"
    out=$(run_step)
    printf '%s\n' "$out"
    grep -qF 'sudo pacman -Rdd pulseaudio pulseaudio-bluetooth' "$T/warn" &&
        [ "$(grep -n -m1 'pulseaudio' <<< "$out" | cut -d: -f1)" -lt "$(grep -n -m1 '^PACMAN -S' <<< "$out" | cut -d: -f1)" ] &&
        ! grep -q -- '-R' <<< "$(grep '^PACMAN' <<< "$out")"
}
jack2_warned() {
    printf 'jack2\n' > "$F/installed"
    run_step
    grep -qF 'sudo pacman -Rdd jack2' "$T/warn"
}
nothing_to_warn() {
    printf 'libpulse\n' > "$F/installed"
    run_step
    [ ! -s "$T/warn" ]
}

t() {
    local name=$1 rc; shift
    set +e
    ( set -e; setup; "$@" ) > "$log" 2>&1
    rc=$?
    set -e
    if [ "$rc" = 0 ]; then echo "ok   $name"; else echo "FAIL $name"; sed 's/^/     /' "$log"; fail=1; fi
}

t "pulseaudio: warned with the removal command before pacman runs, not removed" pulseaudio_warned_before_pacman
t "jack2: warned with the removal command" jack2_warned
t "no pulseaudio or jack2: no warning" nothing_to_warn
exit $fail
