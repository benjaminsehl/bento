#!/bin/bash
# Hook omac into the places Omarchy loads from. Everything points back at this
# checkout, so editing it and running `hyprctl reload` is the whole update
# (re-run install.sh after changing xkb/ or ghostty/).
#
# Safe to re-run: a run that finds everything in place changes nothing. If
# Hyprland reports config errors after loading omac, it unhooks itself again.

set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
toggles="$HOME/.local/state/omarchy/toggles/hypr"
state="$HOME/.local/state/omac"
bin="$HOME/.local/bin"
ghostty_config="$HOME/.config/ghostty/config"
ghostty_line="config-file = ?\"$repo/ghostty/omac.conf\""

fail() { echo "omac: $*" >&2; exit 1; }

[[ -f $repo/hypr/omac.lua ]] || fail "run install.sh from an omac checkout"

omarchy_path=${OMARCHY_PATH:-/usr/share/omarchy}
[[ -f $omarchy_path/default/hypr/toggles.lua ]] || fail "needs Omarchy 4 or newer (Lua Hyprland config)"
for cmd in hyprctl xkbcli omarchy-menu-keybindings omarchy-menu-select gawk; do
  command -v "$cmd" >/dev/null || fail "missing $cmd"
done

if compgen -G "$toggles/macifier-*.lua" >/dev/null; then
  fail "Macifier is active; run 'omarchy-macifier preset off' first"
fi

mkdir -p "$toggles" "$state" "$bin"
changed=no

# Keymaps: one per keyboard type, compiled from xkb/symbols/omac.
for variant in apple pc; do
  out="$state/keymap-$variant.xkb"
  new=$(xkbcli compile-keymap --include "$repo/xkb" --include-defaults --layout omac --variant "$variant") \
    || fail "could not compile the $variant keymap"
  if [[ ! -f $out || $(<"$out") != "$new" ]]; then
    printf '%s\n' "$new" > "$out"
    changed=yes
  fi
done

# Omarchy lists the toggles directory with `find -type f`, which skips
# symlinks, so the hook is a real file that loads the checkout.
hook=$(printf -- '-- Written by omac install.sh.\ndofile([[%s]])' "$repo/hypr/omac.lua")
if [[ ! -f $toggles/omac.lua || $(<"$toggles/omac.lua") != "$hook" ]]; then
  printf '%s\n' "$hook" > "$toggles/omac.lua"
  changed=yes
fi
rm -f "$toggles/omarchy-mac.lua"

if [[ $(readlink "$bin/mac-keybindings" 2>/dev/null) != "$repo/bin/mac-keybindings" ]]; then
  ln -sfn "$repo/bin/mac-keybindings" "$bin/mac-keybindings"
  changed=yes
fi
# Earlier omac linked a paste helper; Ghostty pastes images itself now.
[[ -L $bin/mac-paste ]] && rm -f "$bin/mac-paste"

# Ghostty: include omac's Mac keys after the user's own config.
if [[ -f $ghostty_config ]] && ! grep -qxF "$ghostty_line" "$ghostty_config"; then
  printf '\n# Added by omac install.sh: Mac keys under the omac layout.\n%s\n' "$ghostty_line" >> "$ghostty_config"
  changed=yes
  command -v omarchy-restart-terminal >/dev/null && omarchy-restart-terminal >/dev/null 2>&1 || true
fi

if [[ $changed == no ]]; then
  echo "omac is already installed."
  exit 0
fi

hyprctl reload >/dev/null
errors=$(hyprctl configerrors)
if [[ -n ${errors//[[:space:]]/} ]]; then
  rm -f "$toggles/omac.lua"
  hyprctl reload >/dev/null
  echo "$errors" >&2
  fail "Hyprland reported errors, so omac unhooked itself again"
fi

echo "omac installed."
