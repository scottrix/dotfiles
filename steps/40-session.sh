#!/usr/bin/env bash
# LightDM starting a labwc session, its greeter using the chosen keyboard
# layout, and the OpenRC user services (dbus, PipeWire) that labwc's
# autostart uses.
set -euo pipefail
# shellcheck source=lib/common.sh
. "$DOTFILES_DIR/lib/common.sh"

# Overridable for tests/test-session-step.sh only.
conf=${LIGHTDM_CONF:-/etc/lightdm/lightdm.conf}
xorg_kb_conf=${XORG_KB_CONF:-/etc/X11/xorg.conf.d/00-keyboard.conf}

# seat_option KEY VALUE  set KEY=VALUE in [Seat:*] by replacing its first (commented) line
seat_option() {
    sudo grep -qx "$1=$2" "$conf" && return 0
    sys_backup "$conf"
    srun sed -i "0,/^#\?$1=.*/s//$1=$2/" "$conf"
    [ "$DRY_RUN" = 1 ] || sudo grep -qx "$1=$2" "$conf" || die "couldn't set $1 in $conf"
    say "set $1=$2 in $conf"
}
seat_option greeter-session lightdm-gtk-greeter
seat_option user-session labwc

printf '[Desktop]\nSession=labwc\n' | put "$HOME/.dmrc"

# The greeter runs on Xorg, which doesn't read labwc's environment: give it
# the same layout, so a password types the same at login as in the session.
sys_put "$xorg_kb_conf" << CONF
# Written by dotfiles (40-session): keyboard layout for the LightDM greeter.
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "${KB_LAYOUT:?KB_LAYOUT is not set}"
EndSection
CONF

for dm in sddm gdm lxdm xdm; do
    if rc-update show default 2> /dev/null | grep -qw "$dm"; then
        warn "$dm is also enabled; disable it with: sudo rc-update del $dm default"
    fi
done

svc_add elogind boot
svc_add dbus default
svc_add lightdm default

for svc in dbus pipewire pipewire-pulse wireplumber; do
    [ -e "$HOME/.config/rc/runlevels/default/$svc" ] || run rc-update --user add "$svc" default
done
