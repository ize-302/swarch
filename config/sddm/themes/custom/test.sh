#!/usr/bin/env bash
# Opens the theme in a window. SDDM won't log in from test mode, so the
# spinner keeps going after Enter.
cd "$(dirname "$0")" && exec sddm-greeter-qt6 --test-mode --theme .
