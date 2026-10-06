#!/bin/bash
# swarch installer: SwayFX + waybar + Quickshell desktop for Arch Linux.
# Safe to run again; that is also how you update after a `git pull`.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
repo=$PWD

packages=(
  # bar, menus and lock screen, terminal, notifications
  waybar quickshell alacritty tmux dunst libnotify
  # session
  swayidle swaylock swaybg polkit polkit-gnome xorg-xwayland
  xdg-desktop-portal-wlr xdg-desktop-portal-gtk
  # clipboard
  cliphist wl-clipboard
  # hardware keys
  brightnessctl playerctl
  # audio
  pipewire pipewire-pulse wireplumber libpulse
  # network and bluetooth
  networkmanager network-manager-applet nm-connection-editor
  bluez bluez-utils blueman
  # fonts
  ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji
  cantarell-fonts adwaita-fonts
  # GTK icons (the theme itself, arc-gtk-theme, is in the AUR)
  papirus-icon-theme
  # needed by this script and to build swayfx
  rsync git base-devel
)
sddm_packages=(sddm qt6-virtualkeyboard qt6-svg xorg-server xorg-xrandr)
aur_packages=(swayfx arc-gtk-theme)

# Entries of config/ that land in ~/.config. Everything in bin/ lands in
# ~/.local/bin.
config_entries=(sway waybar quickshell dunst alacritty fontconfig)
# Single files: what else lives in those directories (GTK bookmarks, gtk.css)
# is yours. config/gtk-2.0/gtkrc lands in ~/.gtkrc-2.0.
config_files=(gtk-3.0/settings.ini gtk-4.0/settings.ini)

backup="$HOME/.local/state/swarch/backup/$(date +%Y%m%d-%H%M%S)"
dm_unit=/etc/systemd/system/display-manager.service

with_packages=1
with_sddm=1
link=0

usage() {
  cat <<EOF
Usage: ./install.sh [options]

  --no-packages  Don't install packages or enable services, only place configs
  --no-sddm      Skip the SDDM login manager and its theme
  --link         Symlink configs to this checkout instead of copying them
  -h, --help     Show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
  --no-packages) with_packages=0 ;;
  --no-sddm) with_sddm=0 ;;
  --link) link=1 ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown option: $arg" >&2
    usage >&2
    exit 1
    ;;
  esac
done

if [ "$EUID" -eq 0 ]; then
  echo "Run this as your normal user, not root. It calls sudo where needed." >&2
  exit 1
fi
if [ ! -f /etc/arch-release ]; then
  echo "swarch only supports Arch Linux." >&2
  exit 1
fi

# Leave another login manager alone
if [ "$with_sddm" = 1 ] && [ -e "$dm_unit" ] &&
  [ "$(basename "$(readlink -f "$dm_unit")")" != sddm.service ]; then
  echo "[!] Another display manager is enabled, skipping SDDM."
  with_sddm=0
fi

# Builds an AUR package with makepkg, which pulls its dependencies from the
# official repos. No AUR helper needed.
aur_install() {
  local pkg=$1 tmp dep
  local -a confirm=(--noconfirm) flags=()

  tmp="$(mktemp -d)"
  git clone --depth 1 "https://aur.archlinux.org/$pkg.git" "$tmp/$pkg"

  # swayfx's PKGBUILD has named versioned scenefx packages (scenefx0.5) that
  # only ever existed in the AUR. The library itself is `scenefx` in extra.
  dep="$(sed -nE 's/.*"(scenefx[0-9.]+)".*/\1/p' "$tmp/$pkg/PKGBUILD" | head -1)"
  if [ -n "$dep" ] && ! pacman -Si "$dep" >/dev/null 2>&1 &&
    ! pacman -Qq "$dep" >/dev/null 2>&1; then
    echo "    $dep is not in the repos, building against scenefx instead"
    sed -i "s/\"$dep\"/\"scenefx\"/" "$tmp/$pkg/PKGBUILD"
  fi

  # swayfx replaces sway, which pacman has to ask about
  if pacman -Qq sway >/dev/null 2>&1; then
    confirm=()
  fi
  # arc-gtk-theme's tarball is signed with a key that is not in your keyring.
  # Its checksum in the PKGBUILD is still verified.
  if [ "$pkg" = arc-gtk-theme ]; then
    flags+=(--skippgpcheck)
    # Its GNOME Shell gresource step lists directories as input files, which
    # current meson refuses. The GTK themes don't need it.
    sed -i 's/-Dgnome_shell_gresource=true/-Dgnome_shell_gresource=false/' "$tmp/$pkg/PKGBUILD"
  fi
  (cd "$tmp/$pkg" && makepkg -si "${flags[@]}" "${confirm[@]}")
  rm -rf "$tmp"
}

install_packages() {
  local pkg
  local -a missing

  echo "[+] Installing packages..."
  if [ "$with_sddm" = 1 ]; then
    packages+=("${sddm_packages[@]}")
  fi
  # Only what is not already satisfied: a package you have that provides one
  # of these (papirus-icon-theme-git, say) would otherwise be a conflict
  mapfile -t missing < <(pacman -T "${packages[@]}")
  if [ "${#missing[@]}" -gt 0 ]; then
    sudo pacman -S --needed --noconfirm "${missing[@]}"
  fi

  for pkg in "${aur_packages[@]}"; do
    if ! pacman -T "$pkg" >/dev/null 2>&1; then
      echo "[+] Building $pkg from the AUR..."
      aur_install "$pkg"
    fi
  done
}

# Keeps a copy of whatever is about to be replaced
save() {
  local dst=$1 target="$backup/${1#"$HOME"/}"
  mkdir -p "$(dirname "$target")"
  cp -a "$dst" "$target"
  echo "    kept a copy of $dst"
}

# True if copying src over dst would change a file that is already there
would_overwrite() {
  local src=$1 dst=$2
  if [ -d "$src" ]; then
    [ ! -d "$dst" ] || [ -n "$(rsync -rcn --existing --out-format=%n "$src/" "$dst/")" ]
  else
    ! cmp -s "$src" "$dst"
  fi
}

deploy() {
  local src=$1 dst=$2

  if [ -L "$dst" ]; then
    if [ "$link" = 1 ] && [ "$dst" -ef "$src" ]; then
      return 0
    fi
    # Never copy through a link: that would write into wherever it points
    mkdir -p "$backup"
    echo "$dst -> $(readlink "$dst")" >>"$backup/replaced-links.txt"
    echo "    replaced link $dst -> $(readlink "$dst")"
    rm "$dst"
  elif [ -e "$dst" ]; then
    if [ "$link" = 1 ]; then
      save "$dst"
      rm -rf "$dst"
    elif would_overwrite "$src" "$dst"; then
      save "$dst"
    fi
  fi

  mkdir -p "$(dirname "$dst")"
  if [ "$link" = 1 ]; then
    ln -sr "$src" "$dst"
  elif [ -d "$src" ]; then
    # No --delete: files only you have, such as sway/local.d, stay
    rsync -a "$src/" "$dst/"
  else
    rsync -a "$src" "$dst"
  fi
}

install_configs() {
  local entry file dir

  echo "[+] Installing configs..."
  for entry in "${config_entries[@]}"; do
    deploy "$repo/config/$entry" "$HOME/.config/$entry"
  done
  for file in "${config_files[@]}"; do
    deploy "$repo/config/$file" "$HOME/.config/$file"
  done
  deploy "$repo/config/gtk-2.0/gtkrc" "$HOME/.gtkrc-2.0"
  for file in "$repo"/bin/*; do
    deploy "$file" "$HOME/.local/bin/$(basename "$file")"
  done

  # Quickshell only generates the QML language server config (for editors)
  # where this file already exists
  for dir in "$HOME"/.config/quickshell/*/; do
    [ -e "$dir.qmlls.ini" ] || [ -L "$dir.qmlls.ini" ] || touch "$dir.qmlls.ini"
  done
}

# SDDM runs as its own user and can't read $HOME, so the theme needs a
# root-owned copy
install_sddm_theme() {
  echo "[+] Installing SDDM theme..."
  sudo rsync -a --delete --chown=root:root sddm/theme/ /usr/share/sddm/themes/custom/
  # Selects the theme. Settings in /etc/sddm.conf, if present, win over this
  sudo install -Dm644 sddm/custom-theme.conf /etc/sddm.conf.d/custom-theme.conf
  # Arranges the outputs for the greeter, needs xorg-xrandr
  sudo install -Dm755 sddm/Xsetup /etc/sddm/Xsetup
}

enable_services() {
  local unit other=

  echo "[+] Enabling services..."
  for unit in systemd-networkd iwd dhcpcd connman; do
    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
      other=$unit
    fi
  done
  if [ -n "$other" ]; then
    echo "[!] $other already manages the network, leaving NetworkManager disabled."
  else
    sudo systemctl enable NetworkManager.service
  fi
  sudo systemctl enable bluetooth.service
  if [ "$with_sddm" = 1 ] && [ ! -e "$dm_unit" ]; then
    sudo systemctl enable sddm.service
  fi
  systemctl --user enable pipewire-pulse.socket wireplumber.service 2>/dev/null || true
}

if [ "$with_packages" = 1 ]; then
  install_packages
fi
install_configs
if [ "$with_sddm" = 1 ] && [ -d /usr/share/sddm ]; then
  install_sddm_theme
fi
if [ "$with_packages" = 1 ]; then
  enable_services
fi

echo
echo "[+] Done."
if [ -d "$backup" ]; then
  echo "    Replaced files were saved in $backup"
fi
echo "    Machine-specific sway settings go in ~/.config/sway/local.d/*.conf"
echo "    Reboot, or log out and pick Sway at the login screen."
