#!/usr/bin/env bash
# Build a fresh Artix OpenRC VM (connman networking, like a stock install) and
# boot it in a window on this desktop, for trying the installer by hand.
# Copy the repo to the machine you test on, then run it there:
# usage: tests/vm.sh build   create /var/tmp/dotfiles-vm/disk.img (needs sudo, artools-base)
#        tests/vm.sh run     boot it; ssh -p 2222 tester@localhost (password: tester)
set -euo pipefail
dir=/var/tmp/dotfiles-vm
disk=$dir/disk.img

build() {
    command -v basestrap > /dev/null || sudo pacman -S --needed --noconfirm artools-base
    mkdir -p "$dir"
    [ ! -e "$disk" ] || { echo "$disk exists; delete it to rebuild" >&2; exit 1; }
    truncate -s 20G "$disk"
    loop=$(sudo losetup -fP --show "$disk")
    mnt=$(mktemp -d)
    trap 'sudo umount -R "$mnt" 2>/dev/null; sudo losetup -d "$loop"' EXIT
    printf 'label: dos\n,,L,*\n' | sudo sfdisk -q "$loop"
    sudo mkfs.ext4 -q "${loop}p1"
    sudo mount "${loop}p1" "$mnt"
    # Artix repos only, as on a stock install
    conf=$(mktemp)
    sed '/^\[extra\]/,/^$/d; /^\[multilib\]/,/^$/d' /etc/pacman.conf > "$conf"
    sudo basestrap -C "$conf" "$mnt" base base-devel openrc elogind-openrc linux linux-firmware \
        grub sudo vim connman connman-openrc openssh openssh-openrc
    fstabgen -U "$mnt" | sudo tee -a "$mnt/etc/fstab" > /dev/null
    sudo artix-chroot "$mnt" /bin/bash -e << EOF
echo dotfiles-vm > /etc/hostname
echo en_GB.UTF-8 UTF-8 > /etc/locale.gen && locale-gen > /dev/null
echo LANG=en_GB.UTF-8 > /etc/locale.conf
ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
echo 'keymap="uk"' > /etc/conf.d/keymaps
useradd -m -G wheel tester && echo tester:tester | chpasswd
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
rc-update add connmand default && rc-update add sshd default
grub-install --target=i386-pc $loop
grub-mkconfig -o /boot/grub/grub.cfg
EOF
    echo "built $disk"
}

run() {
    qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 6G \
        -drive file="$disk",format=raw,if=virtio \
        -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22 \
        -device virtio-vga-gl -display gtk,gl=on \
        -name "dotfiles test VM"
}

case ${1:-} in
    build) build ;;
    run) run ;;
    *) sed -n '2,7p' "$0"; exit 2 ;;
esac
