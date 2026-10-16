#!/bin/bash
# Remove everything install.sh put in place. As an Omarchy plugin, run this
# before `omarchy plugin remove`, or the plugin installs Bento again on the next
# shell start. The Magic Keyboard fn mode is separate: system/apple-fnmode.sh.

set -euo pipefail

# -P: the plugin folder may be a symlink to this checkout.
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ghostty_config="$HOME/.config/ghostty/config"

rm -f "$HOME/.local/state/omarchy/toggles/hypr/bento.lua"
rm -f "$HOME/.local/bin/mac-keybindings" "$HOME/.local/bin/mac-paste" "$HOME/.local/bin/bento" "$HOME/.local/bin/bento-apply"
rm -f "$HOME/.local/share/applications/bento.desktop"
rm -rf "$HOME/.local/state/bento"

if [[ -f $ghostty_config ]]; then
  sed -i -e '/^# Added by bento/d' -e "\\|^config-file = ?\"$repo/ghostty/bento.conf\"\$|d" "$ghostty_config"
  command -v omarchy-restart-terminal >/dev/null && omarchy-restart-terminal >/dev/null 2>&1 || true
fi

# The bar goes back to Omarchy's workspace numbers.
shell_json="$HOME/.config/omarchy/shell.json"
if [[ -f $shell_json ]] && grep -q '"io.github.benjaminsehl.bento"' "$shell_json"; then
  new=$(jq 'if .bar.layout then .bar.layout |= with_entries(.value |= map(if .id == "io.github.benjaminsehl.bento" then .id = "omarchy.workspaces" else . end)) else . end' "$shell_json")
  printf '%s\n' "$new" > "$shell_json"
fi

hyprctl reload >/dev/null

echo "Bento removed. Your settings stay in ~/.config/bento."
