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

online() {
    local i
    for ((i = 1; i <= ONLINE_TRIES; i++)); do
        curl -fsS -o /dev/null --max-time 3 https://archlinux.org 2> /dev/null && return 0
        sleep 1
    done
    return 1
}

started() { rc-service "$1" status > /dev/null 2>&1; }
enabled() { rc-update show default 2> /dev/null | awk -v s="$1" '$1 == s { f = 1 } END { exit !f }'; }

# switch_to_iwd  stop connman, bring up iwd + dhcpcd; non-zero on any failure
switch_to_iwd() {
    sudo rc-service connmand stop || return 1
    sudo pkill -x wpa_supplicant || true
    sudo rc-service iwd start || return 1
    sudo rc-service dhcpcd start || return 1
    sudo resolvconf -u || true
}

# rollback  best effort: stop iwd + dhcpcd, bring connman (and wpa_supplicant) back, then fail
rollback() {
    sudo rc-service dhcpcd stop || true
    sudo rc-service iwd stop || true
    sudo rc-service connmand start || true
    if [ "$wpa_was_running" = 1 ] && rc-service -e wpa_supplicant > /dev/null 2>&1; then
        sudo rc-service wpa_supplicant start || true
    fi
    if online; then
        die "could not switch to iwd, so connman is back and online. Plug in ethernet (or add Wi-Fi with iwctl) and resume with: install --from 30-network"
    fi
    die "could not switch to iwd; connman restarted but no network yet; check with connmanctl. Plug in ethernet (or add Wi-Fi with iwctl) and resume with: install --from 30-network"
}

if started connmand; then
    if [ "$DRY_RUN" = 1 ]; then
        say "[dry-run] copy connman Wi-Fi networks to iwd, switch from connman to iwd + dhcpcd"
    else
        wpa_was_running=0
        if started wpa_supplicant || pgrep -x wpa_supplicant > /dev/null 2>&1; then wpa_was_running=1; fi
        copied=$(sudo bash -c ". '$DOTFILES_DIR/lib/connman2iwd.sh' && connman_to_iwd '$CONNMAN_DIR' '$IWD_DIR'")
        # shellcheck disable=SC2001  # per-line basename of a newline list
        [ -z "$copied" ] || say "copied Wi-Fi networks from connman: $(sed 's|.*/||' <<< "$copied" | tr '\n' ' ')"
        if switch_to_iwd && online; then
            sudo rc-update del connmand default || true
            if enabled wpa_supplicant; then
                sudo rc-update del wpa_supplicant default
            fi
            say "switched from connman to iwd + dhcpcd"
        else
            rollback
        fi
    fi
else
    # connman isn't running but may still be enabled; it would fight iwd at boot
    for svc in connmand wpa_supplicant; do
        if enabled "$svc" && ! started "$svc"; then srun rc-update del "$svc" default; fi
    done
    started iwd || srun rc-service iwd start
    started dhcpcd || srun rc-service dhcpcd start
    srun resolvconf -u || true
fi

svc_add iwd default
svc_add dhcpcd default
svc_add sshd default
svc_add bluetoothd default
