#!/usr/bin/env bash
# Wi-Fi by iwd (with its own DHCP), ethernet by dhcpcd, DNS through openresolv.
# If connman or wpa_supplicant runs the network, hand over to iwd + dhcpcd, and
# put the old stack back if that leaves the machine offline. Any other network
# manager (NetworkManager, netifrc, ...) is left alone with a hint.
set -euo pipefail
# shellcheck source=lib/common.sh
. "$DOTFILES_DIR/lib/common.sh"

# Paths are overridable for tests/test-network-step.sh only.
NET_ETC=${NET_ETC:-/etc}
CONNMAN_DIR=${CONNMAN_DIR:-/var/lib/connman}
IWD_DIR=${IWD_DIR:-/var/lib/iwd}
ONLINE_TRIES=${ONLINE_TRIES:-90}
ROLLBACK_TRIES=${ROLLBACK_TRIES:-30}
PRECHECK_TRIES=${PRECHECK_TRIES:-10}
DENY_WIFI='denyinterfaces wlan* wlp*'

sys_put "$NET_ETC/iwd/main.conf" << 'CONF'
[General]
EnableNetworkConfiguration=true

[Network]
NameResolvingService=resolvconf
CONF

if grep -qx duid "$NET_ETC/dhcpcd.conf"; then
    sys_backup "$NET_ETC/dhcpcd.conf"
    srun sed -i 's/^duid$/clientid/' "$NET_ETC/dhcpcd.conf"
fi
sys_line "$NET_ETC/dhcpcd.conf" "$DENY_WIFI"

# A switch that is cut off (Ctrl-C, a dropped SSH session) leaves this behind,
# so a re-run checks the switch again instead of trusting it.
marker=$DOTFILES_STATE/network-switch-in-progress
# 0 when the old network stack is kept: then iwd and dhcpcd mustn't start at boot
use_iwd=1

# online [TRIES]  can we reach archlinux.org? tries about every 1-4 s
online() {
    local tries=${1:-$ONLINE_TRIES} i
    for ((i = 1; i <= tries; i++)); do
        curl -fsS -o /dev/null --max-time 3 https://archlinux.org 2> /dev/null && return 0
        sleep 1
    done
    return 1
}

started() { rc-service "$1" status > /dev/null 2>&1; }
enabled() { rc-update show default 2> /dev/null | awk -v s="$1" '$1 == s { f = 1 } END { exit !f }'; }
# note MSG  progress while switching; never fails, even when the terminal has gone
note() { say "$@" 2> /dev/null || true; }

# other_manager  print a network manager this step can't hand over from, if one runs or is enabled
other_manager() {
    local svc
    for svc in NetworkManager wicd; do
        if started "$svc" || pgrep -x "$svc" > /dev/null 2>&1; then
            echo "$svc"
            return 0
        fi
    done
    # enabled in any runlevel; netifrc's net.* scripts (except loopback) manage interfaces too
    rc-update show 2> /dev/null |
        awk '!f && ($1 == "NetworkManager" || $1 == "wicd" || ($1 ~ /^net\./ && $1 != "net.lo")) { print $1; f = 1 } END { exit !f }' &&
        return 0
    # a wpa_supplicant that neither OpenRC nor connman started belongs to something unknown
    if [ ! -e "$marker" ] && ! started connmand && ! started wpa_supplicant &&
        pgrep -x wpa_supplicant > /dev/null 2>&1; then
        echo "wpa_supplicant (not started by OpenRC)"
        return 0
    fi
    return 1
}

# allow_wifi_dhcp  undo the dhcpcd deny line when dhcpcd served Wi-Fi for the old stack
allow_wifi_dhcp() {
    [ "$dhcpcd_was_running" = 1 ] || return 0
    sudo sed -i "/^denyinterfaces wlan\* wlp\*\$/d" "$NET_ETC/dhcpcd.conf" || true
}

# switch_to_iwd  stop the old stack, bring up iwd + dhcpcd; non-zero on any failure
switch_to_iwd() {
    if started "$old"; then sudo rc-service "$old" stop || return 1; fi
    if started wpa_supplicant; then sudo rc-service wpa_supplicant stop || return 1; fi
    sudo pkill -x wpa_supplicant || true
    started iwd || sudo rc-service iwd start || return 1
    if started dhcpcd; then
        # re-read dhcpcd.conf, which now leaves Wi-Fi to iwd
        sudo rc-service dhcpcd restart || return 1
    else
        sudo rc-service dhcpcd start || return 1
    fi
    sudo resolvconf -u || true
}

# rollback  best effort: stop iwd, bring the old stack back as it was, then fail
rollback() {
    trap '' INT TERM HUP
    sudo rc-service iwd stop || true
    if [ "$old" = connmand ]; then sudo rc-service connmand start || true; fi
    if [ "$old" = wpa_supplicant ] ||
        { [ "$wpa_was_running" = 1 ] && rc-service -e wpa_supplicant > /dev/null 2>&1; }; then
        sudo rc-service wpa_supplicant start || true
    fi
    if [ "$dhcpcd_was_running" = 1 ]; then
        allow_wifi_dhcp
        sudo rc-service dhcpcd restart || true
    else
        sudo rc-service dhcpcd stop || true
    fi
    rm -f "$marker"
    trap - INT TERM HUP
    if online "$ROLLBACK_TRIES"; then
        die "could not switch to iwd, so $name is back and online. Plug in ethernet (or add Wi-Fi with iwctl) and resume with: install --from 30-network"
    fi
    die "could not switch to iwd; $name restarted but no network yet; check with $check_cmd. Plug in ethernet (or add Wi-Fi with iwctl) and resume with: install --from 30-network"
}
interrupted() {
    note "interrupted: putting $name back"
    rollback
}

# The stack to hand over from: a running connman or wpa_supplicant, an earlier
# switch that never finished, or connman enabled but stopped (as after one).
old="" wpa_was_running=0 dhcpcd_was_running=0
other=$(other_manager) || other=""
if [ -n "$other" ]; then
    use_iwd=0
elif started connmand; then
    old=connmand
elif started wpa_supplicant; then
    old=wpa_supplicant
elif [ -e "$marker" ]; then
    read -r old wpa_was_running dhcpcd_was_running < "$marker" || true
    case $old in connmand | wpa_supplicant) ;; *) old=connmand ;; esac
elif enabled connmand; then
    old=connmand
fi
if [ -n "$old" ] && [ ! -e "$marker" ]; then
    if started wpa_supplicant || pgrep -x wpa_supplicant > /dev/null 2>&1; then wpa_was_running=1; fi
    if started dhcpcd; then dhcpcd_was_running=1; fi
fi
if [ "$old" = connmand ]; then name=connman check_cmd=connmanctl; else name=wpa_supplicant check_cmd=wpa_cli; fi

if [ -n "$other" ]; then
    warn "$other manages the network, so iwd and dhcpcd are set up but not started or enabled. To switch by hand: stop and disable $other, then sudo rc-update add iwd default; sudo rc-update add dhcpcd default; and reboot"
elif [ -n "$old" ]; then
    if [ "$DRY_RUN" != 1 ] && started "$old" && ! online "$PRECHECK_TRIES"; then
        # the check can't work here (captive portal, proxy, blocked site), so it would roll back anyway
        allow_wifi_dhcp
        warn "can't reach https://archlinux.org through $name, so the network stays on $name (iwd and dhcpcd are set up but not enabled). Fix the connection and resume with: install --from 30-network"
        use_iwd=0
    elif [ "$DRY_RUN" = 1 ]; then
        say "[dry-run] would switch from $name to iwd + dhcpcd (copying connman's Wi-Fi networks), and put $name back if that leaves the machine offline"
    else
        if [ "$old" = connmand ]; then
            copied=$(sudo bash -c ". '$DOTFILES_DIR/lib/connman2iwd.sh' && connman_to_iwd '$CONNMAN_DIR' '$IWD_DIR'")
            # shellcheck disable=SC2001  # per-line basename of a newline list
            [ -z "$copied" ] || say "copied Wi-Fi networks from connman: $(sed 's|.*/||' <<< "$copied" | tr '\n' ' ')"
        fi
        mkdir -p "$(dirname "$marker")"
        printf '%s %s %s\n' "$old" "$wpa_was_running" "$dhcpcd_was_running" > "$marker"
        # from here on, any way out either finishes the switch or puts the old stack back
        trap interrupted INT TERM HUP
        trap '' PIPE
        note "switching from $name to iwd + dhcpcd"
        if switch_to_iwd &&
            note "checking the connection (up to $(((ONLINE_TRIES * 4 + 59) / 60)) min)..." &&
            online; then
            trap '' INT TERM HUP
            for svc in connmand wpa_supplicant; do
                if enabled "$svc"; then sudo rc-update del "$svc" default || true; fi
            done
            rm -f "$marker"
            trap - INT TERM HUP PIPE
            say "switched from $name to iwd + dhcpcd"
        else
            rollback
        fi
    fi
else
    # wpa_supplicant isn't running but may still be enabled; it would fight iwd at boot
    if enabled wpa_supplicant && ! started wpa_supplicant; then srun rc-update del wpa_supplicant default; fi
    started iwd || srun rc-service iwd start
    started dhcpcd || srun rc-service dhcpcd start
    srun resolvconf -u || true
fi

if [ "$use_iwd" = 1 ]; then
    svc_add iwd default
    svc_add dhcpcd default
fi
svc_add sshd default
svc_add bluetoothd default
