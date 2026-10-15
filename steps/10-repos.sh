#!/usr/bin/env bash
# Enable the Arch [extra] and [multilib] repos on Artix, upgrade, install pikaur.
set -euo pipefail
# shellcheck source=lib/common.sh
. "$DOTFILES_DIR/lib/common.sh"

srun pacman -Syu --needed --noconfirm artix-archlinux-support base-devel git
# a fresh image may have no keyring yet; --init and --populate are safe to repeat
srun pacman-key --init
srun pacman-key --populate artix archlinux

for repo in extra multilib; do
    grep -q "^\[$repo\]" /etc/pacman.conf && continue
    sys_backup /etc/pacman.conf
    if [ "$DRY_RUN" = 1 ]; then
        say "[dry-run] would add [$repo] to /etc/pacman.conf"
        continue
    fi
    printf '\n[%s]\nInclude = /etc/pacman.d/mirrorlist-arch\n' "$repo" | sudo tee -a /etc/pacman.conf > /dev/null
    say "added [$repo] to /etc/pacman.conf"
done

srun pacman -Syu --noconfirm

if ! command -v pikaur > /dev/null; then
    if [ "$DRY_RUN" = 1 ]; then
        say "[dry-run] would build and install pikaur from the AUR"
    else
        build=$(mktemp -d)
        git clone --depth 1 https://aur.archlinux.org/pikaur.git "$build/pikaur"
        # makepkg -s/-i run "sudo -k pacman", which forgets the cached sudo password
        # and prompts again (and fails under --yes), so install the pieces ourselves.
        (
            cd "$build/pikaur"
            # shellcheck disable=SC1091,SC2154
            deps=$(source ./PKGBUILD && printf '%s\n' "${depends[@]}" "${makedepends[@]}")
            # shellcheck disable=SC2086
            sudo pacman -S --needed --asdeps --noconfirm $deps
            makepkg --noconfirm
            sudo pacman -U --noconfirm ./*.pkg.tar.*
        )
        rm -rf "$build"
    fi
fi
