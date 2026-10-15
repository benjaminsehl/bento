#!/bin/bash
# Load hypr/pages.lua so SUPER + N goes to the Nth page dot.
# It runs from this checkout, so `omarchy plugin update` and `hyprctl reload` pick up changes.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
toggles="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/toggles/hypr"

mkdir -p "$toggles"
printf -- '-- Written by omarchy-pages install.sh.\ndofile([[%s]])\n' "$repo/hypr/pages.lua" > "$toggles/pages.lua"

hyprctl reload >/dev/null
errors=$(hyprctl configerrors)
if [[ -n $errors && $errors != ok ]]; then
  rm -f "$toggles/pages.lua"
  hyprctl reload >/dev/null
  echo "Hyprland rejected hypr/pages.lua, so it was removed again:" >&2
  echo "$errors" >&2
  exit 1
fi
echo "Installed: SUPER + N now goes to the Nth page dot."
