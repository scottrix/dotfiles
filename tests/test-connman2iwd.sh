#!/usr/bin/env bash
# Tests for copying connman's saved Wi-Fi networks into iwd.
# shellcheck disable=SC2317  # test functions are invoked indirectly via t()
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
fail=0
log=$(mktemp)

setup() {
    T=$(mktemp -d)
    # shellcheck source=lib/connman2iwd.sh
    . "$here/lib/connman2iwd.sh"
    net() {  # net DIRNAME NAME [PASSPHRASE]
        mkdir -p "$T/connman/$1"
        { echo "[$1]"; echo "Name=$2"; [ -z "${3:-}" ] || echo "Passphrase=$3"; } > "$T/connman/$1/settings"
    }
}

t() {
    local name=$1 rc; shift
    set +e
    ( set -e; setup; "$@" ) > "$log" 2>&1
    rc=$?
    set -e
    if [ "$rc" = 0 ]; then echo "ok   $name"; else echo "FAIL $name"; sed 's/^/     /' "$log"; fail=1; fi
}

plain_name() { [ "$(iwd_name 'Home Net_5-G')" = 'Home Net_5-G' ]; }
hex_name() { [ "$(iwd_name 'Café!')" = '=436166c3a921' ]; }
copies_psk() {
    net wifi_aa_486f6d65_managed_psk Home 's3cret pass'
    connman_to_iwd "$T/connman" "$T/iwd" > /dev/null
    [ "$(cat "$T/iwd/Home.psk")" = $'[Security]\nPassphrase=s3cret pass' ] &&
        [ "$(stat -c %a "$T/iwd/Home.psk")" = 600 ]
}
special_ssid_uses_hex() {
    net wifi_aa_x_managed_psk 'Café!' pw
    connman_to_iwd "$T/connman" "$T/iwd" > /dev/null
    [ -f "$T/iwd/=436166c3a921.psk" ]
}
skips_open_networks() {
    net wifi_aa_y_managed_none Open
    net wifi_aa_z_managed_psk NoPass
    connman_to_iwd "$T/connman" "$T/iwd" > /dev/null
    [ ! -e "$T/iwd" ] || [ -z "$(ls -A "$T/iwd")" ]
}
never_overwrites() {
    net wifi_aa_486f6d65_managed_psk Home new
    mkdir -p "$T/iwd"; printf 'mine\n' > "$T/iwd/Home.psk"
    [ -z "$(connman_to_iwd "$T/connman" "$T/iwd")" ] && [ "$(cat "$T/iwd/Home.psk")" = mine ]
}
no_connman_dir() { [ -z "$(connman_to_iwd "$T/missing" "$T/iwd")" ]; }

t "safe SSID keeps its name" plain_name
t "other SSIDs are hex-encoded" hex_name
t "copies a WPA passphrase, mode 600" copies_psk
t "special-character SSID file uses hex" special_ssid_uses_hex
t "skips open and passwordless networks" skips_open_networks
t "never overwrites an iwd network" never_overwrites
t "no connman directory is fine" no_connman_dir
exit $fail
