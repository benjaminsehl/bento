#!/bin/bash
# Restore Omarchy's default SUPER + N workspace bindings.
set -euo pipefail
rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/toggles/hypr/pages.lua"
hyprctl reload >/dev/null
echo "Uninstalled: SUPER + N goes to workspace N again."
