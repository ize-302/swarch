# swarch

A small, opinionated SwayFX desktop for Arch Linux. One command on a fresh
install gets you a tiling Wayland session with a bar, launcher, lock screen,
notifications and a themed login screen. Nothing else: no bundled apps, no
editor setup, no shell changes.

## What you get

- **SwayFX** window manager (Sway with blur, rounded corners and shadows)
- **Waybar** status bar
- **Quickshell** app launcher, power menu, clipboard history and lock screen
- **Dunst** notifications, **Alacritty** terminal
- **SDDM** login screen with a matching theme
- Audio (PipeWire), network and bluetooth applets, JetBrains Mono Nerd Font

## Requirements

- Arch Linux (a minimal `archinstall` system is enough)
- A normal user with `sudo`
- An internet connection

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/ize-302/swarch/main/boot.sh | bash
```

This clones the repo to `~/.local/share/swarch` and runs `install.sh`. If you
would rather read the script first:

```sh
git clone https://github.com/ize-302/swarch.git
cd swarch
./install.sh
```

Then reboot, or log out and pick **Sway** at the login screen.

### What the installer does

1. Installs the packages listed at the top of `install.sh` with `pacman`.
2. Builds `swayfx` from the AUR with `makepkg` (no AUR helper is installed).
   If `sway` is installed you are asked to let `swayfx` replace it. Later
   `swayfx` updates are up to you, through an AUR helper or by removing the
   package and running the installer again.
3. Copies `config/` into `~/.config` and `bin/` into `~/.local/bin`. Anything
   it would overwrite is first copied to
   `~/.local/state/swarch/backup/<timestamp>/`.
4. Installs the SDDM theme to `/usr/share/sddm/themes/custom` and selects it.
5. Enables NetworkManager, bluetooth and SDDM. NetworkManager is skipped if
   another network service is already enabled, and SDDM is skipped if you
   already use another display manager.

### Options

| Option | Effect |
| --- | --- |
| `--no-packages` | Don't install packages or enable services, only place configs |
| `--no-sddm` | Skip the SDDM login manager and its theme |
| `--link` | Symlink configs to the checkout instead of copying them |

With the one-liner, options go after `bash -s --`:

```sh
curl -fsSL https://raw.githubusercontent.com/ize-302/swarch/main/boot.sh | bash -s -- --no-sddm
```

## Your own settings

Settings that belong to one machine go in `~/.config/sway/local.d/*.conf`. The
installer never touches that directory. For example
`~/.config/sway/local.d/outputs.conf`:

```
# Find output names with: swaymsg -t get_outputs
output DP-2 pos 0 0
output eDP-1 pos 1920 0 scale 1.4

# Turn the laptop screen off/on with the lid
bindswitch --reload --locked lid:on output eDP-1 disable
bindswitch --reload --locked lid:off output eDP-1 enable
```

No wallpaper is set. To set one, uncomment the `output * bg` line in
`~/.config/sway/config`, or better, add it to a file in `local.d` so updates
don't undo it:

```
output * bg ~/Pictures/wallpaper.jpg fill
```

Edits to the installed files themselves are kept until the next update, which
replaces them (after saving a copy in the backup directory).

## Update

```sh
cd ~/.local/share/swarch
git pull
./install.sh
```

Running the one-liner again does the same.

## Uninstall

```sh
./uninstall.sh
```

Moves the swarch configs out of `~/.config` and `~/.local/bin` into
`~/.local/state/swarch/removed-<timestamp>/` and removes the SDDM theme.
Packages and services are left alone. `--no-sddm` keeps the theme, `-y` skips
the question.

## Keys

`Super` is the modifier.

| Keys | Action |
| --- | --- |
| `Super+Return` | Terminal |
| `Super+Space` | App launcher |
| `Super+Escape` | Power menu |
| `Super+c` | Clipboard history |
| `Super+x` | Close window |
| `Super+f` | Fullscreen |
| `Super+Shift+Space` | Toggle floating |
| `Super+h/j/k/l` or arrows | Move focus |
| `Super+Shift+h/j/k/l` or arrows | Move window |
| `Super+1..0` | Switch workspace |
| `Super+Shift+1..0` | Move window to workspace |
| `Super+b` / `Super+v` | Split horizontally / vertically |
| `Super+r` | Resize mode |
| `Super+minus` / `Super+Shift+minus` | Show scratchpad / send to scratchpad |
| `Super+n` | Network connections |
| `Super+Shift+b` | Bluetooth manager |
| `Super+Shift+r` | Reload config |
| `Super+Shift+e` | Exit |

The rest is in `config/sway/config`.

## Working on swarch

`./install.sh --link` symlinks `~/.config` entries to the checkout, so changes
you make show up in `git diff`. In that mode `config/sway/local.d/` lives
inside the checkout and is ignored by git.

## Licence

MIT, see `LICENSE`: do what you like with it, as long as the copyright notice
stays in your copy.

One exception: the SDDM theme in `sddm/theme/` is based on
[SilentSDDM](https://github.com/uiriansan/SilentSDDM) and stays
GPL-3.0-or-later, see `sddm/theme/LICENSE`.
