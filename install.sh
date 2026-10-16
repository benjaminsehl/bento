#!/bin/bash
# Hook omac into the places Omarchy loads from. Everything points back at this
# checkout, so editing it and running `hyprctl reload` is the whole update
# (re-run install.sh after changing xkb/). Settings, and what follows from them
# (the bar's page dots, Ghostty's Mac keys), are bin/omac-apply's job.
#
# Safe to re-run: a run that finds everything in place changes nothing. If
# Hyprland reports config errors after loading omac, it unhooks itself again.

set -euo pipefail

# -P: the plugin folder may be a symlink to this checkout.
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
toggles="$HOME/.local/state/omarchy/toggles/hypr"
state="$HOME/.local/state/omac"
bin="$HOME/.local/bin"
apps="$HOME/.local/share/applications"

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

mkdir -p "$toggles" "$state" "$bin" "$apps"
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
hook=$(printf -- '-- Written by omac install.sh.\n_G.omac_repo = [[%s]]\ndofile([[%s]])' "$repo" "$repo/hypr/omac.lua")
if [[ ! -f $toggles/omac.lua || $(<"$toggles/omac.lua") != "$hook" ]]; then
  printf '%s\n' "$hook" > "$toggles/omac.lua"
  changed=yes
fi
rm -f "$toggles/omarchy-mac.lua"
# Pages used to be its own plugin (omarchy-pages); omac has it now.
if [[ -f $toggles/pages.lua ]]; then rm -f "$toggles/pages.lua"; changed=yes; fi

for tool in mac-keybindings omac omac-apply; do
  if [[ $(readlink "$bin/$tool" 2>/dev/null) != "$repo/bin/$tool" ]]; then
    ln -sfn "$repo/bin/$tool" "$bin/$tool"
    changed=yes
  fi
done

# The omac app, in the app launcher.
desktop=$(cat <<EOF
[Desktop Entry]
Type=Application
Name=omac
Comment=Mac keys, pages, Exposé and gestures for Omarchy
Exec=$bin/omac
Icon=$repo/docs/images/icon-light.svg
Categories=Settings;
Keywords=mac;keyboard;trackpad;gestures;pages;expose;preferences;
EOF
)
if [[ ! -f $apps/omac.desktop || $(<"$apps/omac.desktop") != "$desktop" ]]; then
  printf '%s\n' "$desktop" > "$apps/omac.desktop"
  changed=yes
fi
# Earlier omac linked a paste helper; Ghostty pastes images itself now.
[[ -L $bin/mac-paste ]] && rm -f "$bin/mac-paste"

if [[ $changed == no ]]; then
  echo "omac is already installed."
  exit 0
fi

# Apply the settings (bar, Ghostty) and reload Hyprland. If it still reports
# errors with the settings put back, take omac out again.
"$repo/bin/omac-apply" || true
errors=$(hyprctl configerrors)
if [[ -n ${errors//[[:space:]]/} ]]; then
  rm -f "$toggles/omac.lua"
  hyprctl reload >/dev/null
  echo "$errors" >&2
  fail "Hyprland reported errors, so omac unhooked itself again"
fi

echo "omac installed."
