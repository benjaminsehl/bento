#!/bin/bash
# Remove everything install.sh put in place. As an Omarchy plugin, run this
# before `omarchy plugin remove`, or the plugin installs omac again on the next
# shell start. The Magic Keyboard fn mode is separate: system/apple-fnmode.sh.

set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ghostty_config="$HOME/.config/ghostty/config"

rm -f "$HOME/.local/state/omarchy/toggles/hypr/omac.lua"
rm -f "$HOME/.local/bin/mac-keybindings" "$HOME/.local/bin/mac-paste"
rm -rf "$HOME/.local/state/omac"

if [[ -f $ghostty_config ]]; then
  sed -i -e '/^# Added by omac install.sh/d' -e "\\|^config-file = ?\"$repo/ghostty/omac.conf\"\$|d" "$ghostty_config"
  command -v omarchy-restart-terminal >/dev/null && omarchy-restart-terminal >/dev/null 2>&1 || true
fi

hyprctl reload >/dev/null

echo "omac removed."
