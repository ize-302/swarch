# swarch

Timeless, beautiful (not bloated) sway+arch desktop setup balancing form and
function.

It's [SwayFX](https://github.com/WillPower3309/swayfx) with a frosted-glass
bar ([waybar](https://github.com/Alexays/Waybar)) and a
[Quickshell](https://quickshell.org) shell that draws everything else in one
style: the app launcher, power menu, clipboard and scratchpad menus, a key
bindings sheet (Super+F1), the sound and network control panel,
notifications and the notification centre, a date panel with a calendar and
a pomodoro timer, the volume and caps lock popups, the lock screen and an
SDDM login theme.

Arch only: SwayFX comes from the AUR.

## Layout

Two [GNU Stow](https://www.gnu.org/software/stow/) packages and the system
files:

- `config/`: what lands in `~/.config` (sway, waybar, quickshell, gtk-3.0,
  gtk-4.0, fontconfig, sddm, swappy, alacritty, tmux,
  xdg-desktop-portal-wlr)
- `home/`: what lands in `$HOME` (the `~/.local/bin` scripts the bar, menus
  and key bindings call)
- `etc/`: files `install.sh` copies into `/etc` for SDDM

## Needs

- Arch Linux, logged in as your own user with sudo.

`swayfx` comes from the AUR, through [paru](https://github.com/Morganamilo/paru)
or [yay](https://github.com/Jguer/yay). If you have neither, `install.sh` sets
up paru first (the prebuilt `paru-bin`, with `base-devel` and `git`).
Everything else `install.sh` installs itself from the Arch repos. The list,
grouped by what uses each package, is at the top of `install.sh`. It covers:

- the shell, bar, lock and background: quickshell, waybar, swayidle,
  swaylock, swaybg;
- screenshots, recording and the clipboard: grim, slurp, swappy,
  wf-recorder, cliphist, and the desktop portal;
- sound, media keys and brightness: pipewire, playerctl, brightnessctl;
- network and Bluetooth: NetworkManager, blueman;
- a password prompt (polkit) for apps that need one;
- alacritty (opening in tmux, with its plugins) and btop;
- the GTK theme, icons, cursor and fonts;
- SDDM.

Wallpapers: put images in `~/Pictures/wallpapers`. One is picked at random
every half hour, and Super+Shift+W moves to the next. Until there are any,
swarch's own is used (`home/.local/share/swarch/default-wallpaper.jpg`).

## Install

```sh
git clone <this repo> ~/swarch
cd ~/swarch
./install.sh --dry-run   # see what it would do first
./install.sh
```

It:

1. installs the missing packages;
2. links `config/` into `~/.config` and `home/` into `~`, each file on its
   own;
3. copies the login theme into `/usr/share/sddm/themes` and `/etc`;
4. turns on SDDM and Bluetooth.

If another login manager is already set up it's left alone, and the
installer prints how to switch. NetworkManager isn't switched on for you (it
could cut an install running over another network service); the installer
says so if it's off.

Running it again is safe: what's already done is skipped.

A file already where one of swarch's goes stops the install, and the
installer lists it. Move it aside, or run with `--backup` to have the files
moved to `~/.swarch-backup-<time>/`. `--no-packages` skips the packages.

## Your own settings

Your displays, keyboard layout, extra key bindings and anything else you want
to change go in `~/.config/sway/config.d/`. Sway reads that folder last, so
they can override swarch. For example, `~/.config/sway/config.d/outputs.conf`:

```
output DP-2 pos 0 0
output eDP-1 pos 1920 0 scale 1.4
```

`swaymsg -t get_outputs` lists the names.

The login screen runs before sway, so it doesn't get these scales. To scale
it too, give Qt the same factors, by output name, in a file of your own in
`/etc/sddm.conf.d/`, e.g. `/etc/sddm.conf.d/scale.conf`:

```
[General]
GreeterEnvironment=QT_SCREEN_SCALE_FACTORS=eDP-1=1.4;DP-2=1
```

## Uninstall

```sh
~/swarch/uninstall.sh
```

This removes swarch's links and the login theme. `~/.config/sway/config.d/` is
left alone.
