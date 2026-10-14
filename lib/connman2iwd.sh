# shellcheck shell=bash
# Copy Wi-Fi passphrases saved by connman into iwd network files, so switching
# a Wi-Fi-only machine from connman to iwd keeps it online.

# iwd_name SSID  iwd's file name stem: the SSID itself if it only uses
# letters, digits, space, _ and -; otherwise "=" and the SSID's bytes in hex
iwd_name() {
    if [[ $1 =~ ^[A-Za-z0-9_\ -]+$ ]]; then
        printf '%s' "$1"
    else
        printf '=%s' "$(printf '%s' "$1" | od -An -tx1 | tr -d ' \n')"
    fi
}

# connman_to_iwd SRC DEST  e.g. /var/lib/connman /var/lib/iwd; prints files written
connman_to_iwd() {
    local src=$1 dest=$2 settings name pass file
    for settings in "$src"/wifi_*_managed_psk/settings; do
        [ -f "$settings" ] || continue
        name=$(sed -n 's/^Name=//p' "$settings" | head -n 1)
        pass=$(sed -n 's/^Passphrase=//p' "$settings" | head -n 1)
        if [ -z "$name" ] || [ -z "$pass" ]; then continue; fi
        file=$dest/$(iwd_name "$name").psk
        [ -e "$file" ] && continue
        mkdir -p "$dest"
        (umask 077 && printf '[Security]\nPassphrase=%s\n' "$pass" > "$file")
        printf '%s\n' "$file"
    done
}
