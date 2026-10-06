#!/bin/bash
# Takes the swarch configs back out. Nothing is deleted from $HOME: configs
# are moved aside. Packages and services are left as they are.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
repo=$PWD

config_entries=(sway waybar quickshell dunst alacritty fontconfig)
config_files=(gtk-3.0/settings.ini gtk-4.0/settings.ini)
removed="$HOME/.local/state/swarch/removed-$(date +%Y%m%d-%H%M%S)"

with_sddm=1
confirm=1

for arg in "$@"; do
  case "$arg" in
  -y | --yes) confirm=0 ;;
  --no-sddm) with_sddm=0 ;;
  -h | --help)
    echo "Usage: ./uninstall.sh [-y|--yes] [--no-sddm]"
    exit 0
    ;;
  *)
    echo "Unknown option: $arg" >&2
    exit 1
    ;;
  esac
done

if [ "$confirm" = 1 ]; then
  read -r -p "Remove the swarch configs from ~/.config, ~/.local/bin and ~/.gtkrc-2.0? [y/N] " answer </dev/tty
  case "$answer" in
  y | Y | yes) ;;
  *) exit 0 ;;
  esac
fi

remove() {
  local dst=$1 target="$removed/${1#"$HOME"/}"

  if [ -L "$dst" ]; then
    # Only links made by ./install.sh --link
    case "$(readlink -f "$dst")" in
    "$repo"/*) rm "$dst" ;;
    esac
  elif [ -e "$dst" ]; then
    mkdir -p "$(dirname "$target")"
    mv "$dst" "$target"
  fi
}

echo "[+] Removing configs..."
for entry in "${config_entries[@]}"; do
  remove "$HOME/.config/$entry"
done
for file in "${config_files[@]}"; do
  remove "$HOME/.config/$file"
done
remove "$HOME/.gtkrc-2.0"
for file in "$repo"/bin/*; do
  remove "$HOME/.local/bin/$(basename "$file")"
done

# Remove the root-owned copy of the SDDM theme made by install.sh
if [ "$with_sddm" = 1 ] && [ -d /usr/share/sddm/themes/custom ]; then
  echo "[+] Removing SDDM theme..."
  sudo rm -r /usr/share/sddm/themes/custom
  sudo rm -f /etc/sddm.conf.d/custom-theme.conf
  sudo rm -f /etc/sddm/Xsetup
fi

echo
echo "[+] Done."
if [ -d "$removed" ]; then
  echo "    Your configs were moved to $removed"
fi
