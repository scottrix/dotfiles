#!/usr/bin/env bash
# Clean-install test in an Artix OpenRC container. Packages, AUR builds and
# user files are real; 30-network and 40-session run as --dry-run because a
# container has no running init system.
# usage: tests/container.sh [firefox|chrome|librewolf] [neomutt|thunderbird|none]
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
browser=${1:-firefox} mail=${2:-neomutt}

podman run --rm -i -v "$repo:/src:ro,Z" docker.io/artixlinux/artixlinux:base-openrc \
    bash -s "$browser" "$mail" << 'EOF'
set -euo pipefail
pacman -Syu --noconfirm --needed sudo git gettext > /dev/null
useradd -m tester
echo 'tester ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/tester
install -d -o tester -g tester /home/tester/.local /home/tester/.local/share
cp -r /src /home/tester/.local/share/dotfiles
chown -R tester:tester /home/tester/.local/share/dotfiles
as_tester() {
    su - tester -c "DF_BROWSER=$1 DF_MAIL=$2 ~/.local/share/dotfiles/install --no-update --yes ${*:3}"
}
for step in 10-repos 20-packages; do as_tester "$1" "$2" --only "$step"; done
for step in 30-network 40-session; do as_tester "$1" "$2" --dry-run --only "$step"; done
for step in 50-desktop 60-audio-input 70-shell 80-mail; do as_tester "$1" "$2" --only "$step"; done
su - tester -c 'bash ~/.local/share/dotfiles/tests/check-installed.sh'
echo "== second run changes nothing"
out=$(as_tester "$1" "$2" --only 50-desktop; as_tester "$1" "$2" --only 70-shell; as_tester "$1" "$2" --only 80-mail)
if grep -E 'linked|wrote|backed up' <<< "$out"; then echo "FAIL second run changed files"; exit 1; fi
echo "CONTAINER TEST PASSED"
EOF
