-- Bento: Omarchy, thoughtfully arranged. Keys, pages, Exposé and gestures.
--
-- install.sh loads this file from ~/.local/state/omarchy/toggles/hypr/, which
-- Omarchy loads after ~/.config/hypr/bindings.lua. Each feature lives in its
-- own module and reads its settings from defaults.json, overridden by
-- ~/.config/bento/settings.json (the Bento app writes that file and reloads
-- Hyprland). The key map, with reasons, is docs/keymap.md.

local here = debug.getinfo(1, "S").source:gsub("^@", "")
local repo = _G.bento_repo or here:match("^(.*)/hypr/[^/]+$") or "."

local S = dofile(repo .. "/hypr/settings.lua")(repo)
local lib = dofile(repo .. "/hypr/lib.lua")
lib.repo = repo
_G.bento = { repo = repo, settings = S }

-- Order matters: keyboard.lua re-registers Omarchy's Alt bindings on ⌥
-- before pages.lua and windows.lua replace some of them, and windows.lua uses
-- what pages.lua shares.
-- A module that fails doesn't take the others down. Its error goes to
-- ~/.local/state/bento/errors, where bin/bento-apply looks after a reload.
local errors = {}
for _, module in ipairs({ "keyboard", "trackpad", "pages", "windows" }) do
  local ok, err = pcall(function() dofile(repo .. "/hypr/" .. module .. ".lua")(lib, S) end)
  if not ok then errors[#errors + 1] = module .. ": " .. tostring(err) end
end
os.execute("mkdir -p '" .. lib.state .. "'")
local f = io.open(lib.state .. "/errors", "w")
if f then
  f:write(table.concat(errors, "\n"))
  f:close()
end
if #errors > 0 then
  hl.exec_cmd("notify-send -u critical 'Bento' " .. string.format("%q", table.concat(errors, "\n")))
end

-- The Bento app: a floating window, centred.
hl.window_rule({ match = { title = "^Bento$" }, float = true, center = true, size = { 860, 600 } })
