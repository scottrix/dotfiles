#!/usr/bin/env bash
# Middle-click paste in GTK apps (Chrome too), and keeping the ALSA mixer
# levels across reboots. Touchpad settings are in labwc's rc.xml.
set -euo pipefail
# shellcheck source=lib/common.sh
. "$DOTFILES_DIR/lib/common.sh"

key="org.gnome.desktop.interface gtk-enable-primary-paste"
# shellcheck disable=SC2086
if [ "$(gsettings get $key 2> /dev/null)" != true ]; then
    if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
        run gsettings set $key true
    else
        run dbus-run-session -- gsettings set $key true
    fi
    say "turned on middle-click paste"
fi

svc_add alsasound boot
