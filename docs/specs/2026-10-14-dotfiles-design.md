# dotfiles — design

Date: 2026-10-14
Repo: `github.com/scottrix/dotfiles` (public)

## Goal

One command on a fresh Artix Linux (OpenRC) install gives Scott's laptop look
and feel, on Wayland:

```
curl -fsSL https://raw.githubusercontent.com/scottrix/dotfiles/main/install | bash
```

The setup it reproduces was built by hand on the work PC on 2026-10-14 as a
Wayland port of the home laptop's Openbox/X11 desktop.

## Scope

In:

- Base system: Arch `[extra]`/`[multilib]` repos, pikaur, iwd + dhcpcd
  networking (replacing connman), LightDM starting labwc, PipeWire,
  alsasound.
- Desktop: labwc (Clearlooks theme, keybinds, menu), three desktops
  **Main, Web, Mail**; waybar with eth/wifi modules and impala; foot,
  swaylock, swayidle, mako, solid wallpaper `#006688`; touchpad
  press-to-click with no tap; GTK middle-click paste.
- Login: 9 foot terminals in a 3×3 grid on Main, browser maximised on Web,
  mail client maximised on Mail.
- Prompts: browser (Firefox / Chrome / LibreWolf), mail client
  (neomutt / Thunderbird / none), keyboard layout (default `gb`).
- Shell and vim: generic `.bashrc`, `.profile`, `.bash_profile`, gpg-agent
  for SSH, `.vimrc` with its plugins.
- Tools: podman with podman-docker and podman-compose, general build tools
  (`base-devel`, `cmake`, `git`), `android-tools` (adb, fastboot).
- neomutt: the home laptop's `settings`, `colours` and `mailcap`, with no
  accounts, plus a `mail-account-add` script. The home `mappings` file holds
  only per-account F-key macros (now written by `mail-account-add`) and an
  `M` macro for `~/bin/viewhtmlmail`, which no longer exists, so it is not
  carried over.

Out:

- Anything work-specific: work repos, SSH hosts, work git identity, work chat
  or issue tracker.
- VS Code, Rust, Node, pyenv, cross compilers.
- Secrets of any kind: keys, passwords, mail accounts, aliases, signatures.
- A private "work" step. Not built now.

## Prerequisites (listed in the README)

- Fresh Artix install with **OpenRC** and a working network connection.
  The installer stops with a clear message on systemd or another distro.
- A normal user with sudo access. Passwordless sudo is optional.
- A GPG key is optional; only `mail-account-add` needs one, and it offers to
  create one.

## Approach

A plain bash installer. No dotfiles manager or config-management tool is
installed first. Chosen over chezmoi (still needs bash for the system side)
and Ansible (heavy to bootstrap from curl).

## Install flow

1. Check prerequisites (Artix, OpenRC, not root, sudo works). Ask for the
   sudo password once and keep sudo alive in the background for the run.
   Install `git` if missing.
2. Clone to `~/.local/share/dotfiles`, or `git pull` if already there.
3. Ask all questions up front, reading from `/dev/tty` so it works when
   piped from curl. Save answers to `~/.config/dotfiles/choices`; a re-run
   offers them as defaults.
4. Run `steps/*.sh` in order, then print a summary with skipped items and
   next steps.

Options:

- `--dry-run`: print every change without making it.
- `--only <step>`: run a single step.
- `--from <step>`: resume from a step.
- `--yes`: accept saved or default answers without prompting.

## Repo layout

```
install                  entry point (curl-able)
lib/common.sh            prompts, backups, dry-run, sudo keep-alive, link/copy helpers
steps/10-repos.sh
steps/20-packages.sh
steps/30-network.sh
steps/40-session.sh
steps/50-desktop.sh
steps/60-audio-input.sh
steps/70-shell.sh
steps/80-mail.sh
packages/base.txt        pacman packages
packages/aur.txt         AUR packages
home/                    files linked into ~, mirroring the ~ layout
templates/               files generated from the user's answers
bin/mail-account-add
README.md
docs/specs/              this document
```

## Steps

| Step | Does |
|---|---|
| 10-repos | Install `artix-archlinux-support`; add `[extra]` and `[multilib]` (using `mirrorlist-arch`) to `/etc/pacman.conf` if absent; `pacman -Syu`; build and install pikaur from the AUR if missing. |
| 20-packages | `pacman -S --needed` everything in `packages/base.txt`; install the chosen browser and mail client (`google-chrome` from the AUR); `pikaur -S --needed` everything in `packages/aur.txt`. |
| 30-network | Write `/etc/iwd/main.conf` (`EnableNetworkConfiguration=true`, `NameResolvingService=resolvconf`); in `/etc/dhcpcd.conf` replace `duid` with `clientid` and add `denyinterfaces wlan* wlp*`; regenerate `resolv.conf` with `resolvconf -u`. If connman is running, switch to iwd + dhcpcd and roll back automatically if connectivity fails. Enable `iwd`, `dhcpcd` and `sshd` in the default runlevel. |
| 40-session | Install and enable LightDM; set `user-session=labwc` in `/etc/lightdm/lightdm.conf`; write `~/.dmrc`. |
| 50-desktop | Link labwc `menu.xml`, `autostart`, `environment` (with `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$UID/bus` to override LightDM's dead dbus-launch bus); generate `rc.xml` (window rules for the browser's and mail client's app ids, keyboard layout in `environment`); link waybar, foot and mako configs (mako styled like waybar: #222222, white text, #006688 border; critical #ff4444 and sticky) and the Clearlooks-3.4 openbox-3 theme; generate `~/bin/labwc_startup`; install `~/bin/lock`. |
| 60-audio-input | `gsettings set org.gnome.desktop.interface gtk-enable-primary-paste true`; install `alsa-utils-openrc` and add `alsasound` to the boot runlevel. Mic gain is hardware-specific and is not set; the README explains it. |
| 70-shell | Link `.bashrc`, `.profile`, `.bash_profile`, `.vimrc`, `~/.gnupg/gpg-agent.conf`, `~/.config/pikaur.conf`. `.bashrc` sources `~/.bashrc.local` if present (never touched by the repo) and sets `DOCKER_HOST` for the podman socket. vim plugins are fetched on first run by vim-plug. |
| 80-mail | neomutt: link `settings`, `colours`; generate `mailcap` (HTML to the chosen browser via `xdg-open`) and `neomuttrc` (sources `accounts.rc`, created empty if missing); install `~/bin/mail-account-add`. Thunderbird: nothing beyond the package. None: skip. |

### Linked versus generated

- Static files are **symlinked** into the clone so `git pull` updates them.
- Files that depend on answers are **generated** from `templates/`:
  `rc.xml`, labwc `environment`, `labwc_startup`, neomutt `mailcap` and
  `neomuttrc`.

### Login layout

`labwc_startup` starts `foot --app-id=startterm-N` for N = 1..9, then the
browser, then the mail client (neomutt runs in `foot --app-id=mail`). `rc.xml`
window rules with `matchOnce="true"` send `startterm-*` to desktop 1 at the
3×3 grid positions (630×360 at x ∈ {0, 640, 1280}, y ∈ {0, 391, 782}), the
browser to desktop 2 maximised, and the mail client to desktop 3 maximised.

App ids:

| Choice | app id |
|---|---|
| Chrome | `google-chrome` |
| Firefox | `firefox` |
| LibreWolf | `librewolf` |
| Thunderbird | `thunderbird` |
| neomutt | `mail` (foot) |

### Touchpad

```xml
<libinput>
  <device category="touchpad">
    <tap>no</tap>
    <clickMethod>clickfinger</clickMethod>
  </device>
</libinput>
```

One, two, three finger press = left, right, middle.

### mail-account-add

Prompts for: short name, from address, real name, IMAP host, IMAP port
(default 993), IMAP user, SMTP URL, SMTP user, password (read without echo).

- If no GPG secret key exists, offers to create one with
  `gpg --quick-generate-key`.
- Encrypts the password to `~/.config/neomutt/pass.<name>.gpg`.
- Writes `~/.config/neomutt/account.<name>` in the same shape as the home
  laptop's account files, with
  ``set imap_pass = "`gpg -dq ~/.config/neomutt/pass.<name>.gpg`"`` and the
  same for `smtp_pass`.
- Appends to `accounts.rc` the `source` and `folder-hook` lines and a macro
  binding the next free key (F2, F3, …) to switch to the account, as the home
  laptop's `mappings` did.
- Refuses to overwrite an existing account of the same name.

## Safety

- The installer never deletes files.
- Any user file it would replace is moved to
  `~/.local/state/dotfiles/backup/<timestamp>/` first. System files are
  copied to `<file>.dotfiles-bak` before editing.
- Edits are idempotent: lines are added only if absent, links replaced only if
  they point elsewhere, packages installed with `--needed`.
- The network switch rolls back to connman if connectivity fails.

## Error handling

- Every script runs with `set -euo pipefail`.
- Each step prints `==> <step>` and finishes with `✓` or `✗`.
- On failure the installer stops and prints how to resume
  (`install --from <step>`).
- An AUR package that fails to build is skipped with a warning and listed in
  the summary; it does not stop the run.

## Testing

1. `shellcheck` on every script.
2. Container: run the installer from a local copy of the repo in an Artix
   podman container on the work PC, with the network and session steps in
   dry-run mode. Check that package lists resolve, AUR builds work, files land
   in the right places, and generated files are valid (`xmllint` for
   `rc.xml` and `menu.xml`, `foot --check-config`, waybar config parses as
   JSONC).
3. Virtual machine: install a fresh Artix OpenRC system in QEMU on the work
   PC and run the real `curl … | bash` after pushing. Covers services,
   network switch and rollback, LightDM, and logging into labwc. The VM's
   display opens as a window on the work PC's desktop (QEMU GTK display) so
   Scott can log in and try the result. The VM disk is kept until Scott
   says it can be deleted.

The work PC's own setup is never used as a test target, because it
intentionally differs (extra desktops and work tools).

## README

- The one-liner and the prerequisites.
- The install questions and what each step does.
- Re-running with `--only`, `--from`, `--dry-run`.
- `mail-account-add`, and machine extras in `~/.bashrc.local`.
- After install:
  - log out and pick labwc;
  - HP laptops: lock the top row to F1–F12 (Fn+Esc or Fn+Shift, or
    "Action Keys Mode" in the BIOS) so Super+F1 maximises;
  - mic gain: `amixer -c <card> sset "Internal Mic Boost" 1`, then
    `sudo alsactl store`;
  - browser password-manager extension.
