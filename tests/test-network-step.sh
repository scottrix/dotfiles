#!/usr/bin/env bash
# Tests for steps/30-network.sh with fake system commands; nothing real is touched.
# shellcheck disable=SC2317  # test functions are invoked indirectly via t()
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
fail=0
log=$(mktemp)

setup() {
    T=$(mktemp -d)
    F=$T/fake; mkdir -p "$F/bin" "$F/run" "$T/etc/iwd"
    CMDLOG=$F/cmds; : > "$CMDLOG"
    printf 'duid\n' > "$T/etc/dhcpcd.conf"
    printf 'connmand | default\nsshd | default\n' > "$F/default"
    touch "$F/run/connmand" "$F/online"
    local c
    for c in sudo rc-service rc-update pkill pgrep resolvconf curl sleep; do
        cat > "$F/bin/$c" << 'FAKE'
#!/usr/bin/env bash
c=$(basename "$0"); F=$FAKE
case "$c" in
sudo) echo "sudo $*" >> "$F/cmds"; "$@"; exit ;;
curl)
    # INTERRUPT=1: the user presses Ctrl-C (here: TERM) while the step waits on iwd
    if [ -n "${INTERRUPT:-}" ] && [ -e "$F/run/iwd" ]; then kill -TERM "$PPID"; fi
    [ -e "$F/online" ]; exit ;;
sleep) exit 0 ;;
pgrep) [ -e "$F/proc/$2" ]; exit ;;  # pgrep -x NAME
rc-service)
    if [ "$1" = -e ]; then exit 1; fi
    svc=$1 act=$2
    case "$act" in
    status) [ -e "$F/run/$svc" ]; exit ;;
    *) echo "rc-service $svc $act" >> "$F/cmds"
       [ "$svc $act" = "${FAIL:-}" ] && exit 1
       if [ "$act" = start ] || [ "$act" = restart ]; then touch "$F/run/$svc"; fi
       if [ "$act" = stop ]; then rm -f "$F/run/$svc"; fi
       # the old network stack carries the connection: stopping it goes offline, starting it comes back
       case "$svc $act" in
       "connmand stop" | "wpa_supplicant stop") rm -f "$F/online" ;;
       "connmand start" | "wpa_supplicant start") touch "$F/online" ;;
       esac
       # note whether the in-progress marker was there while iwd was started
       if [ "$svc $act" = "iwd start" ] && [ -e "$DOTFILES_STATE/network-switch-in-progress" ]; then touch "$F/marker-seen"; fi
       # IWD_OFFLINE=1: iwd and dhcpcd come up but never get the machine online
       if [ "$svc $act" = "iwd start" ] && [ -z "${IWD_OFFLINE:-}" ]; then touch "$F/online"; fi
       exit 0 ;;
    esac ;;
rc-update)
    case "$1" in
    show) cat "$F/default" ;;
    add) echo "rc-update $*" >> "$F/cmds"; echo "$2 | $3" >> "$F/default" ;;
    del) echo "rc-update $*" >> "$F/cmds"; [ "$2" != "${FAIL_DEL:-}" ] || exit 1
         sed -i "/^$2 |/d" "$F/default" ;;
    esac ;;
*) echo "$c $*" >> "$F/cmds" ;;
esac
FAKE
        chmod +x "$F/bin/$c"
    done
}

# run_step [ENV=VAL...]: run the step with fakes; "online" tells the fake curl whether the net is up
run_step() {
    env FAKE="$F" PATH="$F/bin:$PATH" DOTFILES_DIR="$here" NET_ETC="$T/etc" \
        CONNMAN_DIR="$T/connman" IWD_DIR="$T/iwdnet" ONLINE_TRIES=1 PRECHECK_TRIES=1 ROLLBACK_TRIES=1 \
        DOTFILES_STATE="$T/state" \
        BACKUP_DIR="$T/bak" WARNINGS_FILE="$T/warn" "$@" bash "$here/steps/30-network.sh"
}
running() { [ -e "$F/run/$1" ]; }
in_default() { grep -q "^$1 |" "$F/default"; }

iwd_start_fails() {
    local rc=0
    run_step DRY_RUN=0 FAIL="iwd start" || rc=$?
    [ "$rc" != 0 ] && running connmand && in_default connmand &&
        grep -q 'rc-service connmand start' "$CMDLOG"
}
offline_after_switch() {
    local rc=0
    run_step DRY_RUN=0 IWD_OFFLINE=1 || rc=$?
    [ "$rc" != 0 ] && running connmand && in_default connmand &&
        grep -q 'rc-service connmand start' "$CMDLOG" &&
        ! grep -q 'rc-update del connmand' "$CMDLOG"
}
success_removes_connman() {
    run_step DRY_RUN=0 > /dev/null
    ! in_default connmand && in_default iwd && in_default dhcpcd &&
        grep -q '^clientid$' "$T/etc/dhcpcd.conf" && [ -f "$T/etc/iwd/main.conf" ] &&
        grep -qxF 'denyinterfaces wlan* wlp*' "$T/etc/dhcpcd.conf"
}
dry_run_changes_nothing() {
    local before after
    before=$(cat "$F/default" "$T/etc/dhcpcd.conf"; ls -R "$T/etc")
    run_step DRY_RUN=1 > /dev/null
    after=$(cat "$F/default" "$T/etc/dhcpcd.conf"; ls -R "$T/etc")
    [ "$before" = "$after" ] &&
        ! grep -Eq 'rc-service [a-z]+ (start|stop)|rc-update (add|del)|pkill|resolvconf' "$CMDLOG"
}
marker() { [ -e "$T/state/network-switch-in-progress" ]; }
stale_connman_removed() {
    rm -f "$F/run/connmand" "$F/online"
    run_step DRY_RUN=0 > /dev/null
    ! in_default connmand && running iwd && ! marker
}
# a re-run after an interrupted switch: connman is enabled but stopped, iwd can't get online
stale_connman_offline_rolls_back() {
    local rc=0
    rm -f "$F/run/connmand" "$F/online"
    run_step DRY_RUN=0 IWD_OFFLINE=1 || rc=$?
    [ "$rc" != 0 ] && running connmand && in_default connmand && ! running iwd &&
        grep -q 'rc-service connmand start' "$CMDLOG" && ! grep -q 'rc-update del connmand' "$CMDLOG" &&
        ! marker
}
interrupted_switch_rolls_back() {
    local rc=0 out
    out=$(run_step DRY_RUN=0 IWD_OFFLINE=1 INTERRUPT=1 2>&1) || rc=$?
    printf '%s\n' "$out"
    [ "$rc" != 0 ] && running connmand && in_default connmand && ! running iwd && ! running dhcpcd &&
        ! grep -q 'rc-update del connmand' "$CMDLOG" && ! marker &&
        grep -q 'checking the connection' <<< "$out" && grep -qi 'interrupted' <<< "$out"
}
# the marker alone (connman neither running nor enabled) still means: check, or put connman back
marker_resumes_switch() {
    rm -f "$F/run/connmand" "$F/online"; sed -i '/^connmand |/d' "$F/default"
    mkdir -p "$T/state"; echo 'connmand 0' > "$T/state/network-switch-in-progress"
    local rc=0
    run_step DRY_RUN=0 IWD_OFFLINE=1 || rc=$?
    [ "$rc" != 0 ] && running connmand && ! running iwd && ! marker
}
marker_cleared_on_success() {
    run_step DRY_RUN=0 > /dev/null
    [ -e "$F/marker-seen" ] && ! marker && ! in_default connmand
}
# no connection even before the switch (captive portal, proxy): leave connman alone
offline_before_switch_skips() {
    rm -f "$F/online"
    run_step DRY_RUN=0 > /dev/null 2>&1
    running connmand && in_default connmand && ! running iwd && ! running dhcpcd &&
        ! in_default iwd && ! in_default dhcpcd && in_default sshd &&
        ! grep -q 'connmand stop' "$CMDLOG" && ! marker &&
        grep -q 'stays on connman' "$T/warn"
}

# no connman: another manager (or a wpa_supplicant + dhcpcd setup) runs the network
no_connman() { rm -f "$F/run/connmand"; sed -i '/^connmand |/d' "$F/default"; }
# left_alone: config written and warned about, iwd and dhcpcd neither started nor enabled
left_alone() {
    [ -f "$T/etc/iwd/main.conf" ] && grep -qxF 'denyinterfaces wlan* wlp*' "$T/etc/dhcpcd.conf" &&
        ! grep -Eq 'rc-service (iwd|dhcpcd) (start|restart)|rc-service [a-z_]+ stop' "$CMDLOG" &&
        ! in_default iwd && ! in_default dhcpcd && in_default sshd &&
        grep -q "$1.*rc-update add iwd default" "$T/warn"
}
networkmanager_running() {
    no_connman; touch "$F/run/NetworkManager"
    run_step DRY_RUN=0 > /dev/null 2>&1
    left_alone NetworkManager
}
networkmanager_enabled() {
    no_connman; rm -f "$F/online"; echo 'NetworkManager | default' >> "$F/default"
    run_step DRY_RUN=0 > /dev/null 2>&1
    left_alone NetworkManager
}
netifrc_enabled() {
    no_connman; echo 'net.eth0 | default' >> "$F/default"
    run_step DRY_RUN=0 > /dev/null 2>&1
    left_alone net.eth0
}
stray_wpa_supplicant() {
    no_connman; mkdir -p "$F/proc"; touch "$F/proc/wpa_supplicant"
    run_step DRY_RUN=0 > /dev/null 2>&1
    left_alone wpa_supplicant
}
wpa_setup() {
    no_connman; touch "$F/run/wpa_supplicant" "$F/run/dhcpcd"
    printf 'wpa_supplicant | default\ndhcpcd | default\n' >> "$F/default"
}
wpa_supplicant_handed_over() {
    wpa_setup
    run_step DRY_RUN=0 > /dev/null
    ! running wpa_supplicant && ! in_default wpa_supplicant && running iwd && in_default iwd &&
        in_default dhcpcd && grep -qx 'rc-service wpa_supplicant stop' "$CMDLOG" &&
        grep -qx 'rc-service dhcpcd restart' "$CMDLOG" && ! marker
}
wpa_supplicant_rolled_back() {
    local rc=0
    wpa_setup
    run_step DRY_RUN=0 IWD_OFFLINE=1 || rc=$?
    # dhcpcd served Wi-Fi for wpa_supplicant before, so it gets wlan* back
    [ "$rc" != 0 ] && running wpa_supplicant && in_default wpa_supplicant && ! running iwd &&
        running dhcpcd && ! grep -q 'denyinterfaces' "$T/etc/dhcpcd.conf" &&
        grep -qx 'rc-service wpa_supplicant start' "$CMDLOG" && ! grep -q 'rc-update del' "$CMDLOG" && ! marker
}
wpa_supplicant_offline_before() {
    wpa_setup; rm -f "$F/online"
    run_step DRY_RUN=0 > /dev/null 2>&1
    running wpa_supplicant && in_default wpa_supplicant && ! running iwd && ! in_default iwd &&
        ! grep -q 'denyinterfaces' "$T/etc/dhcpcd.conf" && grep -q 'stays on wpa_supplicant' "$T/warn"
}
# a re-run after a hard kill mid-switch (power loss): marker left, old stack running again after boot
marker_with_old_stack_running_restores_it() {
    local rc=0
    wpa_setup
    printf 'denyinterfaces wlan* wlp*\n' >> "$T/etc/dhcpcd.conf"
    mkdir -p "$T/state"; echo 'wpa_supplicant 1 1 1' > "$T/state/network-switch-in-progress"
    run_step DRY_RUN=0 IWD_OFFLINE=1 || rc=$?
    [ "$rc" != 0 ] && running wpa_supplicant && running dhcpcd && ! running iwd &&
        ! grep -q 'denyinterfaces' "$T/etc/dhcpcd.conf" && ! grep -q 'rc-service dhcpcd stop' "$CMDLOG" && ! marker
}
# the deny line was the user's own before we came: a rollback keeps it
users_deny_line_kept() {
    local rc=0
    wpa_setup
    printf 'denyinterfaces wlan* wlp*\n' >> "$T/etc/dhcpcd.conf"
    run_step DRY_RUN=0 IWD_OFFLINE=1 || rc=$?
    [ "$rc" != 0 ] && running wpa_supplicant && running dhcpcd && grep -qxF 'denyinterfaces wlan* wlp*' "$T/etc/dhcpcd.conf"
}
# rollback can't restart connman: the switch stays marked unfinished
failed_restore_keeps_marker() {
    local rc=0 out
    out=$(run_step DRY_RUN=0 IWD_OFFLINE=1 FAIL="connmand start" 2>&1) || rc=$?
    printf '%s\n' "$out"
    [ "$rc" != 0 ] && marker && grep -q 'still marked unfinished' <<< "$out"
}
wpa_del_failure_tolerated() {
    echo 'wpa_supplicant | default' >> "$F/default"
    run_step DRY_RUN=0 FAIL_DEL=wpa_supplicant > /dev/null
    ! in_default connmand && running iwd
}

t() {
    local name=$1 rc; shift
    set +e
    ( set -e; setup; "$@" ) > "$log" 2>&1
    rc=$?
    set -e
    if [ "$rc" = 0 ]; then echo "ok   $name"; else echo "FAIL $name"; sed 's/^/     /' "$log"; fail=1; fi
}

t "iwd start fails: connman restarted and kept enabled" iwd_start_fails
t "offline after switch: connman restarted and kept enabled" offline_after_switch
t "success: connman leaves the default runlevel" success_removes_connman
t "dry run changes nothing" dry_run_changes_nothing
t "stopped but enabled connman: switch checked, then removed from default" stale_connman_removed
t "connman enabled, not running, offline after iwd start: connman restarted and kept enabled" stale_connman_offline_rolls_back
t "interrupted during the connection check: connman restarted and kept enabled" interrupted_switch_rolls_back
t "in-progress marker alone: switch checked, connman put back when offline" marker_resumes_switch
t "offline before the switch: connman left running and enabled" offline_before_switch_skips
t "NetworkManager running: configured, warned, iwd and dhcpcd left off" networkmanager_running
t "NetworkManager enabled: configured, warned, iwd and dhcpcd left off" networkmanager_enabled
t "netifrc interface enabled: configured, warned, iwd and dhcpcd left off" netifrc_enabled
t "wpa_supplicant outside OpenRC: configured, warned, iwd and dhcpcd left off" stray_wpa_supplicant
t "wpa_supplicant running: handed over to iwd" wpa_supplicant_handed_over
t "wpa_supplicant running, offline after iwd start: wpa_supplicant and dhcpcd put back" wpa_supplicant_rolled_back
t "wpa_supplicant running, offline before the switch: left alone, dhcpcd keeps Wi-Fi" wpa_supplicant_offline_before
t "marker left and old stack running again: rollback uses the marker's flags" marker_with_old_stack_running_restores_it
t "a deny line that was already there survives a rollback" users_deny_line_kept
t "rollback that can't restart connman keeps the marker" failed_restore_keeps_marker
t "success tolerates rc-update del wpa_supplicant failing" wpa_del_failure_tolerated
t "in-progress marker exists during the switch and is removed after" marker_cleared_on_success
exit $fail
