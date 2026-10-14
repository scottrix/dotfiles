#!/usr/bin/env bash
# Wi-Fi by iwd (with its own DHCP), ethernet by dhcpcd, DNS through openresolv.
# If connman is running, hand over to iwd + dhcpcd, and put connman back if
# that leaves the machine offline.
set -euo pipefail
# shellcheck source=lib/common.sh
. "$DOTFILES_DIR/lib/common.sh"

sys_put /etc/iwd/main.conf << 'CONF'
[General]
EnableNetworkConfiguration=true

[Network]
NameResolvingService=resolvconf
CONF

if grep -qx duid /etc/dhcpcd.conf; then
    sys_backup /etc/dhcpcd.conf
    srun sed -i 's/^duid$/clientid/' /etc/dhcpcd.conf
fi
sys_line /etc/dhcpcd.conf 'denyinterfaces wlan*'

online() {
    for _ in $(seq 1 90); do
        curl -fsS -o /dev/null --max-time 3 https://archlinux.org 2> /dev/null && return 0
        sleep 1
    done
    return 1
}

started() { rc-service "$1" status > /dev/null 2>&1; }

if started connmand; then
    if [ "$DRY_RUN" = 1 ]; then
        say "[dry-run] copy connman Wi-Fi networks to iwd, switch from connman to iwd + dhcpcd"
    else
        copied=$(sudo bash -c ". '$DOTFILES_DIR/lib/connman2iwd.sh' && connman_to_iwd /var/lib/connman /var/lib/iwd")
        [ -z "$copied" ] || say "copied Wi-Fi networks from connman: $(xargs -n 1 basename <<< "$copied" | tr '\n' ' ')"
        sudo rc-service connmand stop
        sudo pkill -x wpa_supplicant || true
        sudo rc-service iwd start
        sudo rc-service dhcpcd start
        sudo resolvconf -u || true
        if online; then
            sudo rc-update del connmand default || true
            if rc-update show default | grep -qw wpa_supplicant; then
                sudo rc-update del wpa_supplicant default
            fi
            say "switched from connman to iwd + dhcpcd"
        else
            sudo rc-service dhcpcd stop || true
            sudo rc-service iwd stop || true
            sudo rc-service connmand start
            die "no network after leaving connman, so connman is back. Plug in ethernet (or add Wi-Fi with iwctl) and resume with: install --from 30-network"
        fi
    fi
else
    started iwd || srun rc-service iwd start
    started dhcpcd || srun rc-service dhcpcd start
    srun resolvconf -u || true
fi

svc_add iwd default
svc_add dhcpcd default
svc_add sshd default
svc_add bluetoothd default
