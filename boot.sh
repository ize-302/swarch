#!/bin/bash
# swarch bootstrap: clones the repo and hands over to install.sh.
#
#   curl -fsSL https://raw.githubusercontent.com/ize-302/swarch/main/boot.sh | bash
#
# Options for install.sh go after `bash -s --`, e.g. `| bash -s -- --no-sddm`.
set -euo pipefail

SWARCH_REPO="${SWARCH_REPO:-https://github.com/ize-302/swarch.git}"
SWARCH_DIR="${SWARCH_DIR:-$HOME/.local/share/swarch}"

# Everything runs from main, called on the last line, so a download that got
# cut off part way does nothing
main() {
  if [ ! -f /etc/arch-release ]; then
    echo "swarch only supports Arch Linux." >&2
    exit 1
  fi

  if ! command -v git >/dev/null; then
    echo "[+] Installing git..."
    sudo pacman -S --needed --noconfirm git
  fi

  if [ -d "$SWARCH_DIR/.git" ]; then
    echo "[+] Updating $SWARCH_DIR..."
    git -C "$SWARCH_DIR" pull --ff-only
  else
    echo "[+] Cloning swarch into $SWARCH_DIR..."
    mkdir -p "$(dirname "$SWARCH_DIR")"
    git clone "$SWARCH_REPO" "$SWARCH_DIR"
  fi

  # Piped from curl, stdin is this script. Give the installer the terminal
  # back so it can ask questions.
  if (exec </dev/tty) 2>/dev/null; then
    exec "$SWARCH_DIR/install.sh" "$@" </dev/tty
  fi
  exec "$SWARCH_DIR/install.sh" "$@"
}

main "$@"
