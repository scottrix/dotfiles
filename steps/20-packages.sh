#!/usr/bin/env bash
# Install packages/base.txt, packages/aur.txt and the chosen browser and mail client.
set -euo pipefail
# shellcheck source=lib/common.sh
. "$DOTFILES_DIR/lib/common.sh"

mapfile -t pkgs < <(pkgs_from base.txt)
mapfile -t aur < <(pkgs_from aur.txt)

case $MAIL in
    neomutt) pkgs+=(neomutt w3m aspell aspell-en enscript) ;;
    thunderbird) pkgs+=(thunderbird) ;;
esac
if [ "$BROWSER_FROM" = repo ]; then
    pkgs+=("$BROWSER_PKG")
else
    aur+=("$BROWSER_PKG")
fi

# PipeWire replaces these; pacman --noconfirm declines to remove a conflicting
# package and stops, so say why and how before it gets there.
mapfile -t pulse < <(pacman -Qq 2> /dev/null | grep -E '^pulseaudio(-|$)' || true)
if [ ${#pulse[@]} -gt 0 ]; then
    warn "PulseAudio (${pulse[*]}) conflicts with pipewire-pulse, so pacman will stop. Remove it, then resume with install --from 20-packages: sudo pacman -Rdd ${pulse[*]}"
fi
if pacman -Q jack2 > /dev/null 2>&1; then
    warn "jack2 is installed; if pacman reports a conflict with pipewire-jack, remove it, then resume with install --from 20-packages: sudo pacman -Rdd jack2"
fi

srun pacman -S --needed --noconfirm "${pkgs[@]}"

for pkg in "${aur[@]}"; do
    pacman -Q "$pkg" > /dev/null 2>&1 && continue
    run pikaur -S --needed --noconfirm --noedit --nodiff "$pkg" ||
        warn "AUR package $pkg failed to build and was skipped"
done
