#!/usr/bin/env bash
# Test bin/mail-account-add with a throwaway GPG home and fake answers.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
fail=0
T=$(mktemp -d)
export HOME=$T XDG_CONFIG_HOME=$T/.config GNUPGHOME=$T/gnupg
trap 'gpgconf --kill gpg-agent 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$XDG_CONFIG_HOME/neomutt" && mkdir -m 700 "$GNUPGHOME"
# a smartcard daemon that hangs would stall every decrypt on some machines
echo disable-scdaemon > "$GNUPGHOME/gpg-agent.conf"
printf '# accounts added by mail-account-add\n' > "$XDG_CONFIG_HOME/neomutt/accounts.rc"
gpg --batch --passphrase '' --quick-generate-key "Test <test@example.com>" default default never 2> /dev/null

expect() {
    local name=$1; shift
    if "$@" > /dev/null 2>&1; then echo "ok   $name"; else echo "FAIL $name"; fail=1; fi
}
add() {  # add NAME: answers for every prompt, IMAP password imap-pw, SMTP password Enter (= same)
    printf '%s\n' "$1" "me@example.com" "Me" "imap.example.com" "" "" "smtp.example.com" "" "" "imap-pw" "" |
        "$here/bin/mail-account-add"
}
d=$XDG_CONFIG_HOME/neomutt

add work > "$T/out1" 2>&1 || { echo "FAIL first add"; cat "$T/out1"; exit 1; }
expect "account file written" test -f "$d/account.work"
expect "folder uses host and default port" grep -qx 'set folder = "imaps://imap.example.com:993/"' "$d/account.work"
expect "imap user defaults to from" grep -qx 'set imap_user = "me@example.com"' "$d/account.work"
expect "smtps url on 465" grep -qx 'set smtp_url = "smtps://smtp.example.com:465/"' "$d/account.work"
expect "imap password is not in plain text" bash -c "! grep -rq imap-pw '$d'"
expect "imap password decrypts" bash -c "[ \"\$(gpg --batch -dq '$d/pass.work.imap.gpg')\" = imap-pw ]"
expect "smtp password defaults to imap" bash -c "[ \"\$(gpg --batch -dq '$d/pass.work.smtp.gpg')\" = imap-pw ]"
expect "account file mode 600" test "$(stat -c %a "$d/account.work")" = 600
expect "sourced from accounts.rc" grep -qx "source \"\$XDG_CONFIG_HOME/neomutt/account.work\"" "$d/accounts.rc"
expect "F2 switches to it" grep -q '^macro index <f2> .*account.work' "$d/accounts.rc"
add home > /dev/null 2>&1
expect "second account gets F3" grep -q '^macro index <f3> .*account.home' "$d/accounts.rc"
expect "duplicate name refused" bash -c "! (printf 'work\n' | '$here/bin/mail-account-add') 2>/dev/null"
expect "bad name refused" bash -c "! (printf 'a b\n' | '$here/bin/mail-account-add') 2>/dev/null"
if command -v neomutt > /dev/null; then
    expect "neomutt reads the account file" bash -c "timeout 20 neomutt -n -F '$d/account.work' -Q imap_user < /dev/null"
fi
exit $fail
