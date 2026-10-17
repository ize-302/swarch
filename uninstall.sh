#!/bin/bash
set -e

cd "$(dirname "${BASH_SOURCE[0]}")"

# Only swarch's own links go; ~/.config/sway/config.d/ and anything else
# beside them stays
stow --no-folding --ignore='\.qmlls\.ini' -v -t "$HOME/.config" -D config
stow --no-folding --ignore='\.qmlls\.ini' -v -t "$HOME" -D home

# Remove the root-owned copy of the SDDM theme made by install.sh
if [ -d /usr/share/sddm/themes/custom ]; then
  echo "[+] Removing SDDM theme..."
  sudo rm -r /usr/share/sddm/themes/custom
  sudo rm -f /etc/sddm.conf.d/custom-theme.conf
  sudo rm -f /etc/sddm/Xsetup
fi
