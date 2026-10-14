# dotfiles

Scott's desktop on a fresh [Artix Linux](https://artixlinux.org) (OpenRC) install:
labwc on Wayland with a Clearlooks theme, waybar, foot, PipeWire, iwd, podman, and
optionally neomutt.

```
curl -fsSL https://raw.githubusercontent.com/scottrix/dotfiles/main/install | bash
```

## Before you start

- A fresh Artix install with **OpenRC** and a working network connection.
- A normal user that can use `sudo`. Passwordless sudo is optional; the installer
  asks for your password once and keeps sudo active while it runs. Without a
  terminal to ask on (for example `ssh host 'curl ... | bash'` without `-t`),
  sudo must be passwordless.
- Optional: a GPG key. Only `mail-account-add` needs one, and it offers to make one.

## What it asks

| Question | Choices | Default |
|---|---|---|
| Browser | firefox, chrome, librewolf | firefox |
| Mail client | neomutt, thunderbird, none | neomutt |
| Keyboard layout | any XKB layout | gb |

Answers are saved in `~/.config/dotfiles/choices` and offered as defaults next
time. `DF_BROWSER`, `DF_MAIL` and `DF_KB_LAYOUT` in the environment override them.
If there is no terminal to ask on (for example `ssh host 'curl ... | bash'`
without `-t`), the installer behaves as `--yes` and uses the saved answers or
the defaults.

## What it does

| Step | |
|---|---|
| 10-repos | Enables the Arch `[extra]` and `[multilib]` repos, upgrades, installs pikaur. |
| 20-packages | Installs `packages/base.txt`, `packages/aur.txt`, the browser and the mail client. Firefox and LibreWolf come from the Artix/Arch repos; Chrome is built from the AUR. |
| 30-network | Wi-Fi by iwd, ethernet by dhcpcd, DNS by openresolv. Moves over from connman (copying saved Wi-Fi passwords) or wpa_supplicant, and puts the old setup back if that leaves you offline or the switch is interrupted. If NetworkManager (or another network manager) is in use, it only writes the config and tells you how to switch by hand. Enables sshd and bluetooth. |
| 40-session | LightDM with labwc as the session and your keyboard layout on the login screen; dbus and PipeWire as OpenRC user services. |
| 50-desktop | labwc (theme, keys, menu, desktops Main/Web/Mail), waybar, foot, mako notifications (styled like waybar). At login: 9 terminals on Main, the browser on Web, mail on Mail. |
| 60-audio-input | Middle-click paste in GTK apps (set with gsettings, stored by dconf); ALSA mixer levels kept across reboots. |
| 70-shell | bash, vim with plugins (vim-plug), gpg-agent as the SSH agent. |
| 80-mail | neomutt settings, colours and mailcap with no accounts, and `mail-account-add`. |

Files the installer replaces are moved to `~/.local/state/dotfiles/backup/<time>/`;
system files it edits are first copied to `<file>.dotfiles-bak`. Nothing is deleted.
Running it again is safe.

## Running it again

```
~/.local/share/dotfiles/install               # pull the latest and run everything
~/.local/share/dotfiles/install --dry-run     # show what would change; changes nothing
~/.local/share/dotfiles/install --only 50-desktop
~/.local/share/dotfiles/install --from 30-network
~/.local/share/dotfiles/install --yes         # don't ask; reuse saved answers or defaults
```

`--dry-run` only fetches the installer's own checkout, so git and gettext
must already be installed.

Config files are symlinks into `~/.local/share/dotfiles`, so a `git pull` there
updates them. Files that depend on your answers (labwc `rc.xml`, `menu.xml`,
`environment`, waybar `config.jsonc`, `~/bin/labwc_startup`, the neomutt
`mailcap`) are generated; re-run the installer to regenerate them.

## Keys

| Key | Action |
|---|---|
| Super+1/2/3 | Go to Main / Web / Mail |
| Super+F1 | Maximise / restore the window |
| Super+F2 | Lock the screen |
| Super+Space | Menu |
| Super+Tab | Next window |
| Print | Screenshot of a selected area to `~/Pictures` |

Touchpad: press with one, two or three fingers for left, right and middle click.
Tapping does nothing.

## Mail accounts (neomutt)

```
mail-account-add
```

asks for the account's servers and passwords, stores the IMAP and SMTP passwords
in separate files (`pass.<name>.imap.gpg`, `pass.<name>.smtp.gpg`) encrypted
with your GPG key, and adds the account to `~/.config/neomutt/accounts.rc`. The
account added last opens at startup; F2, F3, … switch accounts in the order you
added them.

## Your own additions

Put machine-only shell settings in `~/.bashrc.local`; the installer never touches it.

## After installing

- Reboot, then log in; LightDM starts labwc.
- **HP laptops:** the top row sends action keys by default, so Super+F1 types
  `p`. Lock it to F1–F12 with Fn+Esc or Fn+Shift, or turn off "Action Keys
  Mode" in the BIOS.
- **Microphone too loud or distorted:** lower the internal mic boost, e.g.
  `amixer -c 1 sset "Internal Mic Boost" 1`, then save it with `sudo alsactl store`.
- Add your password manager's browser extension.
- The terminal grid is laid out for a 1920×1200 screen; on other sizes, change
  the `MoveTo`/`ResizeTo` values in `steps/50-desktop.sh` and re-run
  `install --only 50-desktop`.
