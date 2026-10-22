#!/bin/bash
# Hook Bento into the places Omarchy loads from. The Service runs this from the
# plugin folder whenever the shell starts Bento (and after an update), so you
# rarely need to. Editing the checkout and running `hyprctl reload` is the
# whole update otherwise (re-run install.sh after changing xkb/). Settings, and
# what follows from them (Ghostty's Mac keys), are bin/bento-apply's job.
#
# Disabling or removing Bento in Omarchy takes all of it away again
# (bin/bento-cleanup); so does uninstall.sh.
#
# Safe to re-run: a run that finds everything in place changes nothing. If
# loading Bento gives Hyprland config errors it didn't have before, it unhooks
# itself again.
#
# Bento only runs as an Omarchy plugin. To work on a checkout, link it as the
# plugin and enable it (the shell also notices the link by itself):
#   ln -s ~/path/to/bento ~/.config/omarchy/plugins/io.github.benjaminsehl.bento
#   omarchy-shell shell rescanPlugins
#   omarchy plugin enable io.github.benjaminsehl.bento

set -euo pipefail

id=io.github.benjaminsehl.bento
# -P: the plugin folder may be a symlink to this checkout.
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
plugin="$HOME/.config/omarchy/plugins/$id"
toggles="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/toggles/hypr"
state="$HOME/.local/state/bento"
bin="$HOME/.local/bin"
apps="$HOME/.local/share/applications"

fail() { echo "bento: $*" >&2; exit 1; }

[[ -f $repo/hypr/bento.lua ]] || fail "run install.sh from a Bento checkout"
# Omarchy's disable and remove are what take Bento out again, so this has to
# be the copy Omarchy knows as the plugin.
[[ $(realpath -e "$plugin" 2>/dev/null) == "$repo" ]] \
  || fail "Bento is an Omarchy plugin: omarchy plugin add <url> --enable (or link this checkout as the plugin)"

# Run by hand while Omarchy has Bento off, all of this would only last until
# the reload's gate started the cleanup. So ask what the cleanup goes by.
# Not when the Service runs this (no terminal): an enable starts the Service
# before the shell has saved shell.json.
if [[ -t 1 ]] && [[ $(bash "$repo/bin/bento-cleanup" --status 2>/dev/null) == disabled ]]; then
  fail "Bento is off in Omarchy: omarchy plugin enable $id"
fi

omarchy_path=${OMARCHY_PATH:-/usr/share/omarchy}
[[ -f $omarchy_path/default/hypr/toggles.lua ]] || fail "needs Omarchy 4 or newer (Lua Hyprland config)"
for cmd in hyprctl xkbcli omarchy-menu-keybindings omarchy-menu-select gawk; do
  command -v "$cmd" >/dev/null || fail "missing $cmd"
done

if compgen -G "$toggles/macifier-*.lua" >/dev/null; then
  fail "Macifier is active; run 'omarchy-macifier preset off' first"
fi

# One at a time with bento-cleanup, which a disable starts.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/bento.lock"
flock -w 30 9 || fail "a Bento cleanup is still running; try again"

# Hyprland's errors before anything changes, so the check at the end only
# counts the ones Bento brought (another plugin's may be there already).
errors_before=$(hyprctl configerrors 2>/dev/null || true)

mkdir -p "$toggles" "$state" "$bin" "$apps"
changed=no

# Write a file unless it already says that: a temp file next to it, renamed
# over it, so Hyprland never reads half of one. Returns 1 when unchanged.
put() { # file content
  [[ -f $1 && $(<"$1") == "$2" ]] && return 1
  { printf '%s\n' "$2" >"$1.tmp.$$" && mv -f "$1.tmp.$$" "$1"; } || fail "could not write $1"
}

# Keymaps: one per keyboard type, compiled from xkb/symbols/bento.
for variant in apple pc; do
  new=$(xkbcli compile-keymap --include "$repo/xkb" --include-defaults --layout bento --variant "$variant") \
    || fail "could not compile the $variant keymap"
  put "$state/keymap-$variant.xkb" "$new" && changed=yes
done

# The hook Hyprland loads. A real file (Omarchy lists the toggles directory
# with `find -type f`, which skips symlinks) that loads the plugin folder, and
# once that is gone, starts the cleanup instead. It names no checkout, so an
# update leaves it alone.
stub=$(cat <<'EOF'
-- Written by Bento (io.github.benjaminsehl.bento), stub 3. Bento deletes this
-- file when it is disabled or removed in Omarchy; deleting it by hand is safe.
local home = os.getenv("HOME") or ""
local plugin = home .. "/.config/omarchy/plugins/io.github.benjaminsehl.bento"
local state = (os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")) .. "/bento"
local function read(path)
  local h = io.open(path, "r")
  if not h then return nil end
  local s = h:read("a")
  h:close()
  return s
end
local function write(path, s)
  local h = io.open(path, "w")
  if h then h:write(s); h:close() end
end
local function notify(title, body)
  local q = function(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
  pcall(os.execute, "setsid -f sh -c " .. q("sleep 3; notify-send -u critical " .. q(title) .. " " .. q(body))
    .. " </dev/null >/dev/null 2>&1")
end

local f = io.open(plugin .. "/hypr/bento.lua", "r")
if f then
  f:close()
  -- The breaker. Bento's Lua runs inside Hyprland, so a bug in it can take
  -- Hyprland down. Each Hyprland marks its first two minutes with Bento in
  -- `starting`. If the next Hyprland finds another one's mark, that one
  -- stopped while Bento was new to it, so Bento stays off (`paused`) until
  -- `bento resume`, and Hyprland comes up as stock Omarchy.
  local me = os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "?"
  local starting, paused = state .. "/starting", state .. "/paused"
  local ok, skip = pcall(function()
    if read(paused) then return true end
    local other = read(starting)
    if other and other ~= me then
      write(paused, "Hyprland " .. other .. " stopped within two minutes of loading Bento.\n")
      return true
    end
    return false
  end)
  if not ok or skip then
    if read(state .. "/paused-told") ~= me then
      write(state .. "/paused-told", me)
      notify("Bento is paused", "Hyprland stopped soon after loading Bento, so this time it started without it. "
        .. "Run `bento resume` to load Bento again.")
    end
  else
    pcall(os.execute, "mkdir -p '" .. state:gsub("'", "'\\''") .. "'")
    write(starting, me)
    pcall(hl.timer, function() os.remove(starting) end, { timeout = 120000, type = "oneshot" })
    _G.bento_repo, _G.bento_stub = plugin, 3
    -- An error stops at Bento: the rest of your config still loads.
    local loaded, err = pcall(dofile, plugin .. "/hypr/bento.lua")
    if not loaded then
      write(state .. "/errors", "bento.lua: " .. tostring(err))
      notify("Bento didn't load", tostring(err))
    end
  end
else
  -- The plugin is gone: put Omarchy back, in the background.
  pcall(function()
    local cleanup = state .. "/bento-cleanup"
    local c = io.open(cleanup, "r")
    if c then
      c:close()
      os.execute("setsid -f bash '" .. (cleanup:gsub("'", "'\\''")) .. "' --settle </dev/null >/dev/null 2>&1")
    end
  end)
end
EOF
)
put "$toggles/bento.lua" "$stub" && changed=yes

# The cleanup has to outlive the plugin folder, and know which checkout the
# links point into. Neither changes what Hyprland loads.
if ! cmp -s "$repo/bin/bento-cleanup" "$state/bento-cleanup" || [[ ! -x $state/bento-cleanup ]]; then
  { cp "$repo/bin/bento-cleanup" "$state/bento-cleanup.tmp.$$" \
    && chmod 755 "$state/bento-cleanup.tmp.$$" \
    && mv -f "$state/bento-cleanup.tmp.$$" "$state/bento-cleanup"; } || fail "could not copy bento-cleanup"
fi
put "$state/repo" "$repo" || true

rm -f "$toggles/omarchy-mac.lua"
# Pages used to be its own plugin (omarchy-pages); Bento has it now.
if [[ -f $toggles/pages.lua ]]; then rm -f "$toggles/pages.lua"; changed=yes; fi

for tool in mac-keybindings bento bento-apply; do
  if [[ $(readlink "$bin/$tool" 2>/dev/null) != "$repo/bin/$tool" ]]; then
    ln -sfn "$repo/bin/$tool" "$bin/$tool"
    changed=yes
  fi
done

# The Bento app, in the app launcher.
desktop=$(cat <<EOF
[Desktop Entry]
Type=Application
Name=Bento
Comment=Windows, pages, keys and gestures for Omarchy
Exec=$bin/bento
TryExec=$bin/bento
Icon=$repo/docs/images/icon-light.svg
Categories=Settings;
Keywords=bento;keyboard;trackpad;gestures;pages;overview;windows;preferences;
EOF
)
put "$apps/bento.desktop" "$desktop" && changed=yes
# An earlier version linked a paste helper; Ghostty pastes images itself now.
[[ -L $bin/mac-paste ]] && rm -f "$bin/mac-paste"

# Bento must be one entry in the bar and nowhere else: listed in "plugins"
# too, disabling it would leave it running.
if jq -e --arg id "$id" '[.plugins[]? | objects | .id] | index($id)' "$HOME/.config/omarchy/shell.json" >/dev/null 2>&1; then
  echo "bento: Bento is also in \"plugins\" in ~/.config/omarchy/shell.json; take it out there, or disabling it won't turn it off" >&2
fi

if [[ $changed == no ]]; then
  echo "Bento is already installed."
  exit 0
fi

# Apply the settings (Ghostty) and reload Hyprland. This run changed code,
# not settings, so a module error is no reason to touch them (bento.lua
# notifies it). If Hyprland has errors it didn't have before, take Bento out
# again.
"$repo/bin/bento-apply" --no-rollback || true
errors_after=$(hyprctl configerrors 2>/dev/null || true)
new_errors=$(grep -vxF -f <(printf '%s\n' "$errors_before") <<<"$errors_after" | grep -v '^[[:space:]]*$' || true)
if [[ -n $new_errors ]]; then
  rm -f "$toggles/bento.lua"
  hyprctl reload >/dev/null
  echo "$new_errors" >&2
  fail "Hyprland reported errors, so Bento unhooked itself again"
fi

echo "Bento installed."
