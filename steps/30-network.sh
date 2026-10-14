#!/usr/bin/env bash
# Wi-Fi by iwd (with its own DHCP), ethernet by dhcpcd, DNS through openresolv.
# If connman is running, hand over to iwd + dhcpcd, and put connman back if
# that leaves the machine offline.
set -euo pipefail
# shellcheck source=lib/common.sh
. "$DOTFILES_DIR/lib/common.sh"

# Paths are overridable for tests/test-network-step.sh only.
NET_ETC=${NET_ETC:-/etc}
CONNMAN_DIR=${CONNMAN_DIR:-/var/lib/connman}
IWD_DIR=${IWD_DIR:-/var/lib/iwd}
ONLINE_TRIES=${ONLINE_TRIES:-90}

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
sys_line "$NET_ETC/dhcpcd.conf" 'denyinterfaces wlan*'

# A switch that is cut off (Ctrl-C, a dropped SSH session) leaves this behind,
# so a re-run checks the switch again instead of trusting it.
marker=$DOTFILES_STATE/network-switch-in-progress
ROLLBACK_TRIES=${ROLLBACK_TRIES:-30}
PRECHECK_TRIES=${PRECHECK_TRIES:-10}
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

# switch_to_iwd  stop connman, bring up iwd + dhcpcd; non-zero on any failure
switch_to_iwd() {
    if started connmand; then sudo rc-service connmand stop || return 1; fi
    sudo pkill -x wpa_supplicant || true
    started iwd || sudo rc-service iwd start || return 1
    started dhcpcd || sudo rc-service dhcpcd start || return 1
    sudo resolvconf -u || true
}

# rollback  best effort: stop iwd + dhcpcd, bring connman (and wpa_supplicant) back, then fail
rollback() {
    trap '' INT TERM HUP
    sudo rc-service dhcpcd stop || true
    sudo rc-service iwd stop || true
    sudo rc-service connmand start || true
    if [ "$wpa_was_running" = 1 ] && rc-service -e wpa_supplicant > /dev/null 2>&1; then
        sudo rc-service wpa_supplicant start || true
    fi
    rm -f "$marker"
    trap - INT TERM HUP
    if online "$ROLLBACK_TRIES"; then
        die "could not switch to iwd, so connman is back and online. Plug in ethernet (or add Wi-Fi with iwctl) and resume with: install --from 30-network"
    fi
    die "could not switch to iwd; connman restarted but no network yet; check with connmanctl. Plug in ethernet (or add Wi-Fi with iwctl) and resume with: install --from 30-network"
}
interrupted() {
    note "interrupted: putting connman back"
    rollback
}

# Hand over from connman when it runs, when it is enabled but stopped (as after
# an interrupted switch), or when an earlier switch never finished.
if started connmand || enabled connmand || [ -e "$marker" ]; then
    if [ "$DRY_RUN" != 1 ] && started connmand && ! online "$PRECHECK_TRIES"; then
        # the check can't work here (captive portal, proxy, blocked site), so it would roll back anyway
        warn "can't reach https://archlinux.org through connman, so the network stays on connman (iwd and dhcpcd are set up but not enabled). Fix the connection and resume with: install --from 30-network"
        use_iwd=0
    elif [ "$DRY_RUN" = 1 ]; then
        say "[dry-run] would copy connman Wi-Fi networks to iwd, switch from connman to iwd + dhcpcd, and put connman back if that leaves the machine offline"
    else
        wpa_was_running=0
        if started wpa_supplicant || pgrep -x wpa_supplicant > /dev/null 2>&1; then wpa_was_running=1; fi
        # an earlier, unfinished switch knows whether wpa_supplicant ran before it
        if [ -e "$marker" ]; then read -r _ wpa_was_running < "$marker" || true; fi
        copied=$(sudo bash -c ". '$DOTFILES_DIR/lib/connman2iwd.sh' && connman_to_iwd '$CONNMAN_DIR' '$IWD_DIR'")
        # shellcheck disable=SC2001  # per-line basename of a newline list
        [ -z "$copied" ] || say "copied Wi-Fi networks from connman: $(sed 's|.*/||' <<< "$copied" | tr '\n' ' ')"
        mkdir -p "$(dirname "$marker")"
        printf 'connmand %s\n' "$wpa_was_running" > "$marker"
        # from here on, any way out either finishes the switch or puts connman back
        trap interrupted INT TERM HUP
        trap '' PIPE
        note "switching from connman to iwd + dhcpcd"
        if switch_to_iwd &&
            note "checking the connection (up to $(((ONLINE_TRIES * 4 + 59) / 60)) min)..." &&
            online; then
            trap '' INT TERM HUP
            sudo rc-update del connmand default || true
            if enabled wpa_supplicant; then
                sudo rc-update del wpa_supplicant default
            fi
            rm -f "$marker"
            trap - INT TERM HUP PIPE
            say "switched from connman to iwd + dhcpcd"
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
