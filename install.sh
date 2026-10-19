#!/bin/bash
# swarch's installer, for Arch Linux. Installs the packages swarch needs
# (swayfx from the AUR through paru or yay, setting up paru if neither is
# there), links config/ into ~/.config and home/ into $HOME, and sets up the
# SDDM login screen.
#
#   ./install.sh             install
#   ./install.sh --dry-run   say what it would do, change nothing
#   ./install.sh --backup    move files in the way to ~/.swarch-backup-<time>/
#                            instead of stopping
#   ./install.sh --no-packages   skip installing packages
set -e

cd "$(dirname "${BASH_SOURCE[0]}")"

dry=
backup=
packages=1
for arg in "$@"; do
  case "$arg" in
  --dry-run) dry=1 ;;
  --backup) backup=1 ;;
  --no-packages) packages= ;;
  -h | --help)
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "Unknown option: $arg (see --help)" >&2
    exit 1
    ;;
  esac
done

say() { echo "[+] $*"; }
note() { echo "[!] $*"; }
# Runs a command, or only prints it on a dry run
run() {
  if [ -n "$dry" ]; then
    echo "    would run: $*"
  else
    "$@"
  fi
}

# From the repos, each for what uses it
repo_packages=(
  # The shell (config/quickshell), the bar, the lock and the desktop
  # background (sway's `output * bg` runs swaybg)
  quickshell qt6-5compat waybar swayidle swaylock swaybg
  # Screenshots, recording and the clipboard
  grim slurp swappy wf-recorder wl-clipboard cliphist
  # The desktop portal: apps share the screen and open file pickers through
  # it. swayfx's own sway-portals.conf has wlr do screenshots and screen
  # sharing, gtk the rest
  xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk
  # Sound, media keys and brightness
  # (pactl and paplay come from libpulse)
  pipewire pipewire-pulse wireplumber libpulse playerctl brightnessctl
  sound-theme-freedesktop
  # Notifications (notify-send)
  libnotify
  # Network and Bluetooth: the control panel, nm-connection-editor (Super+N),
  # blueman, and the pairing agent (home/.local/bin/bluetooth-agent)
  networkmanager nm-connection-editor bluez bluez-utils blueman
  python python-dbus python-gobject
  # Asks for passwords for apps that need them (started in config/sway/config)
  polkit-gnome
  # Apps the bar and keys open; alacritty opens in tmux
  alacritty tmux btop
  # The file manager: trash and network places (gvfs), thumbnails (tumbler,
  # and for videos, PDFs, WebP and office files), extract and compress in the
  # right-click menu, audio tags
  thunar gvfs tumbler ffmpegthumbnailer poppler-glib webp-pixbuf-loader libgsf
  thunar-archive-plugin xarchiver thunar-media-tags-plugin
  # Downloads tmux's plugins
  git
  # Look: GTK theme, icons, cursor, fonts, gsettings
  adw-gtk-theme papirus-icon-theme adwaita-cursors adwaita-fonts
  ttf-jetbrains-mono-nerd noto-fonts-emoji glib2 gsettings-desktop-schemas
  # The login screen
  sddm qt6-wayland rsync
  # This installer
  stow
)
# From the AUR (sway with blur, shadows and rounded corners; replaces sway)
aur_packages=(swayfx)

[ "$(id -u)" -ne 0 ] || { note "Run this as your own user, not root: it asks for sudo itself."; exit 1; }
command -v pacman >/dev/null || { note "swarch is for Arch Linux (no pacman here)."; exit 1; }
[ -n "$dry" ] && say "Dry run: nothing will be changed."

# --- Packages ---------------------------------------------------------------

if [ -n "$packages" ]; then
  missing=()
  for p in "${repo_packages[@]}"; do
    pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    say "Installing ${#missing[@]} packages: ${missing[*]}"
    run sudo pacman -S --needed "${missing[@]}"
  else
    say "Packages from the repos: all installed."
  fi

  aur_missing=()
  for p in "${aur_packages[@]}"; do
    pacman -Q "$p" >/dev/null 2>&1 || aur_missing+=("$p")
  done
  if [ ${#aur_missing[@]} -gt 0 ]; then
    helper=$(command -v paru || command -v yay || true)
    if [ -z "$helper" ]; then
      # swayfx needs scenefx, also from the AUR, which makepkg alone can't
      # fetch; so set up paru first. paru-bin is paru already built, so
      # this doesn't pull in Rust and compile it
      say "No paru or yay: installing paru (paru-bin from the AUR) to get ${aur_missing[*]}"
      run sudo pacman -S --needed base-devel git
      build=$(mktemp -d)
      run git clone https://aur.archlinux.org/paru-bin.git "$build/paru-bin"
      if [ -n "$dry" ]; then
        echo "    would run: (cd $build/paru-bin && makepkg -si)"
      else
        (cd "$build/paru-bin" && makepkg -si)
      fi
      rm -rf "$build"
      helper=paru
    fi
    say "Installing from the AUR with $(basename "$helper"): ${aur_missing[*]}"
    run "$helper" -S --needed "${aur_missing[@]}"
  else
    say "Packages from the AUR: all installed."
  fi
fi

command -v stow >/dev/null || { note "stow isn't installed (run without --no-packages)."; [ -n "$dry" ] || exit 1; }

# --- Links ------------------------------------------------------------------

# Each file linked on its own (--no-folding), so ~/.config/sway and the rest
# stay real folders: ~/.config/sway/config.d/ can hold your own settings, and
# other things' files can sit beside these. Quickshell makes its own
# .qmlls.ini (an editor's settings) where it runs, so that isn't linked.
stow_ignore='\.qmlls\.ini'

# config/tmux is a starting point. If ~/.config/tmux is already something
# else's (your own dotfiles), that one stays and swarch's isn't linked; its
# plugins are still downloaded, if that config loads tpm
keep_tmux=
config_ignore=()
tmux_conf="$HOME/.config/tmux/tmux.conf"
if [ -e "$tmux_conf" ] && [ "$(readlink -f "$tmux_conf")" != "$(readlink -f config/tmux/tmux.conf)" ]; then
  keep_tmux=1
  config_ignore=(--ignore=tmux)
  say "Keeping your own ~/.config/tmux, swarch's tmux.conf isn't linked"
fi

# Files already where one of swarch's goes, that aren't swarch's own links. A
# folder on the way that's a link itself (~/.config/sway pointing into some
# other dotfiles repo) counts as the thing in the way, so --backup moves the
# link rather than files inside someone else's repo.
conflicts=()
declare -A seen
add_conflict() {
  [ -n "${seen[$1]}" ] && return
  seen[$1]=1
  conflicts+=("$1")
}
for pkg in config home; do
  [ "$pkg" = config ] && target="$HOME/.config" || target="$HOME"
  while IFS= read -r -d '' src; do
    rel=${src#"$pkg"/}
    case "$rel" in */.qmlls.ini) continue ;; esac
    case "$pkg/$rel" in config/tmux/*) [ -n "$keep_tmux" ] && continue ;; esac
    dir=$target
    linked=
    IFS=/ read -ra parts <<<"$(dirname "$rel")"
    for part in "${parts[@]}"; do
      [ "$part" = . ] && continue
      dir="$dir/$part"
      if [ -L "$dir" ]; then
        add_conflict "$dir"
        linked=1
        break
      fi
    done
    [ -n "$linked" ] && continue
    dest="$target/$rel"
    if [ -L "$dest" ]; then
      [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ] || add_conflict "$dest"
    elif [ -e "$dest" ]; then
      add_conflict "$dest"
    fi
  done < <(find "$pkg" \( -type f -o -type l \) -print0)
done

if [ ${#conflicts[@]} -gt 0 ]; then
  if [ -n "$backup" ]; then
    stash="$HOME/.swarch-backup-$(date +%Y%m%d-%H%M%S)"
    say "Moving ${#conflicts[@]} files in the way to $stash"
    for f in "${conflicts[@]}"; do
      run mkdir -p "$stash/$(dirname "${f#"$HOME"/}")"
      run mv "$f" "$stash/${f#"$HOME"/}"
    done
  else
    note "These are where swarch's files go, so nothing was linked:"
    printf '      %s\n' "${conflicts[@]}"
    note "Move them aside, or run again with --backup to have them moved."
    exit 1
  fi
fi

say "Linking config/ into ~/.config and home/ into ~"
run mkdir -p "$HOME/.config"
if [ -n "$dry" ]; then
  # Stow's own dry run, which also catches anything the check above missed;
  # not while files that --backup would have moved are still in the way
  if [ ${#conflicts[@]} -eq 0 ] && command -v stow >/dev/null; then
    stow -n --no-folding --ignore="$stow_ignore" "${config_ignore[@]}" -t "$HOME/.config" config
    stow -n --no-folding --ignore="$stow_ignore" -t "$HOME" home
  fi
else
  stow --no-folding --ignore="$stow_ignore" "${config_ignore[@]}" -t "$HOME/.config" config
  stow --no-folding --ignore="$stow_ignore" -t "$HOME" home
fi

# --- tmux plugins -------------------------------------------------------------

# tpm, which config/tmux/tmux.conf loads, and the plugins it lists. Done with
# a tmux server of its own, so one that's already running isn't touched
tpm="$HOME/.config/tmux/plugins/tpm"
if [ ! -d "$tpm" ] && { [ -z "$keep_tmux" ] || grep -q 'plugins/tpm/tpm' "$tmux_conf"; }; then
  say "Downloading tmux's plugins"
  run git clone -q --depth 1 https://github.com/tmux-plugins/tpm "$tpm"
  if [ -z "$dry" ]; then
    sock=$(mktemp -d)
    env -u TMUX TMUX_TMPDIR="$sock" "$tpm/bin/install_plugins" >/dev/null
    rm -rf "$sock"
  else
    echo "    would run: $tpm/bin/install_plugins"
  fi
fi

# --- Login screen -------------------------------------------------------------

# SDDM runs as its own user and can't read $HOME, so the theme needs a
# root-owned copy
if [ -d /usr/share/sddm/themes ] || [ -n "$dry" ]; then
  say "Installing the SDDM login theme"
  run sudo rsync -a --delete --chown=root:root config/sddm/themes/custom/ /usr/share/sddm/themes/custom/
  # Selects the theme. Settings in /etc/sddm.conf, if present, win over this
  run sudo install -Dm644 etc/sddm.conf.d/custom-theme.conf /etc/sddm.conf.d/custom-theme.conf
  # The sway the greeter runs in
  run sudo install -Dm644 etc/sddm/sway.conf /etc/sddm/sway.conf
  # From when the greeter ran on X
  run sudo rm -f /etc/sddm/Xsetup
  # Somewhere outside $HOME that SDDM can read, for ~/.local/bin/wallpaper
  # to copy the current wallpaper to
  run sudo install -d -m755 -o "$USER" -g "$(id -gn)" /var/lib/sddm-wallpaper
  # Until the first sway login puts a wallpaper there, the default
  if [ ! -e /var/lib/sddm-wallpaper/current ]; then
    run cp home/.local/share/swarch/default-wallpaper.jpg /var/lib/sddm-wallpaper/current
  fi
else
  note "SDDM isn't installed, so the login theme was skipped."
fi

# --- Services ----------------------------------------------------------------

# The login screen at the next boot. Another login manager already set up
# (display-manager.service is taken) is left alone, with a note
if [ "$(systemctl is-enabled sddm 2>/dev/null)" != enabled ]; then
  current=$(readlink /etc/systemd/system/display-manager.service 2>/dev/null || true)
  if [ -z "$current" ]; then
    say "Enabling SDDM for the next boot"
    run sudo systemctl enable sddm
  else
    dm=$(basename "$current" .service)
    note "$dm is the login manager. To use swarch's login screen:"
    note "  sudo systemctl disable $dm && sudo systemctl enable sddm"
  fi
fi

if [ "$(systemctl is-enabled bluetooth 2>/dev/null)" != enabled ]; then
  say "Enabling Bluetooth"
  run sudo systemctl enable --now bluetooth
fi

# Folders open in Thunar: browsers' "Show in folder", and xdg-open on a folder
if [ "$(xdg-mime query default inode/directory 2>/dev/null)" != thunar.desktop ]; then
  say "Making Thunar the file manager"
  run xdg-mime default thunar.desktop inode/directory
fi

# Not switched on here: another network service (iwd, systemd-networkd) may be
# what's running, and switching mid-install could cut the connection
if [ "$(systemctl is-enabled NetworkManager 2>/dev/null)" != enabled ]; then
  note "NetworkManager isn't enabled; the bar's network panel needs it:"
  note "  sudo systemctl enable --now NetworkManager"
fi

# --- Done -----------------------------------------------------------------------

if [ -n "$dry" ]; then
  say "Dry run done: nothing was changed."
else
  say "Installed. Put your displays and other settings in"
  echo "    ~/.config/sway/config.d/, then log in to sway (or restart it)."
fi
