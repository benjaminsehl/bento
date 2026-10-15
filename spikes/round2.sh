#!/bin/bash
# Compile omac's keymaps and load the round 2 spike into the running Hyprland.
# Everything it does is undone by `hyprctl reload` (or ⌃⌥⌘Esc once loaded).
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

for variant in apple pc; do
  xkbcli compile-keymap --include "$repo/xkb" --include-defaults \
    --layout omac --variant "$variant" > "/tmp/omac-keymap-$variant.xkb"
done

rm -f /tmp/omac-spike.log
hyprctl eval "dofile(\"$repo/spikes/round2.lua\")"
hyprctl configerrors
