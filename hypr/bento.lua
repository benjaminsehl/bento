-- Bento: Omarchy, thoughtfully arranged. Keys, pages, Overview and gestures.
--
-- install.sh loads this file from ~/.local/state/omarchy/toggles/hypr/, which
-- Omarchy loads after ~/.config/hypr/bindings.lua. Each feature lives in its
-- own module and reads its settings from defaults.json, overridden by
-- ~/.config/bento/settings.json (the Bento app writes that file and reloads
-- Hyprland). The key map, with reasons, is docs/keymap.md.

local here = debug.getinfo(1, "S").source:gsub("^@", "")
local repo = _G.bento_repo or here:match("^(.*)/hypr/[^/]+$") or "."

-- Is Bento on in Omarchy? Asked of ~/.config/omarchy/shell.json with the
-- shell's own rule (PluginRegistry.isEnabled): listed in the bar or in
-- "plugins", and not in "disabledPlugins". "unknown" when the shell would
-- throw the file away too. The config comes back with the answer.
local ID = "io.github.benjaminsehl.bento"
local function has(list, test)
  if type(list) ~= "table" then return false end
  for k, v in pairs(list) do
    if type(k) == "number" and test(v) then return true end
  end
  return false
end
local function in_bar(config, id)
  local bar = type(config.bar) == "table" and config.bar or {}
  local layout = type(bar.layout) == "table" and bar.layout or {}
  local function is(entry) return entry == id or (type(entry) == "table" and entry.id == id) end
  for _, section in ipairs({ "left", "center", "right" }) do
    if has(layout[section], is) then return true end
  end
  return false
end
local function shell_status()
  local f = io.open((os.getenv("HOME") or "") .. "/.config/omarchy/shell.json", "r")
  if not f then return "unknown" end
  local text = f:read("a")
  f:close()
  if not text or not text:find("%S") then return "unknown" end
  local config = dofile(repo .. "/hypr/json.lua").decode(text)
  if type(config) ~= "table" or config.version ~= 1 then return "unknown" end
  if has(config.disabledPlugins, function(v) return v == ID end) then return "disabled", config end
  if type(config.bar) == "table" and config.bar.id == ID then return "enabled", config end
  if in_bar(config, ID) then return "enabled", config end
  if has(config.plugins, function(e) return type(e) == "table" and e.id == ID end) then return "enabled", config end
  return "disabled", config
end

-- Bento before stub 2 turned page dots off by renaming its bar entry to
-- omarchy.workspaces, which Omarchy counts as disabled, so its keys lived on
-- through the old hook alone. Such an install still loads through that hook
-- (no _G.bento_stub) and never chose to turn Bento off. Its settings, when
-- that is what this is.
local function dots_off_before_stub_2(config)
  if _G.bento_stub ~= nil or type(config) ~= "table" then return nil end
  if has(config.disabledPlugins, function(v) return v == ID end) then return nil end
  if not in_bar(config, "omarchy.workspaces") then return nil end
  local settings = dofile(repo .. "/hypr/settings.lua")(repo)
  if type(settings) == "table" and type(settings.pages) == "table" and settings.pages.dots == false then
    return settings
  end
end

-- Off: this load is stock Omarchy's. Nothing below runs, and bin/bento-cleanup
-- (detached, so the load doesn't wait) takes the hook away for good once
-- Omarchy has settled. Unsure: load as usual.
local ok, status, config = pcall(shell_status)
local legacy = nil
if ok and status == "disabled" then
  local checked, settings = pcall(dots_off_before_stub_2, config)
  if checked then legacy = settings end
end
if ok and status == "disabled" and not legacy then
  pcall(function()
    local cleanup = (os.getenv("HOME") or "") .. "/.local/state/bento/bento-cleanup"
    local f = io.open(cleanup, "r")
    if f then f:close() else cleanup = repo .. "/bin/bento-cleanup" end
    os.execute("setsid -f bash '" .. (cleanup:gsub("'", "'\\''")) .. "' --settle </dev/null >/dev/null 2>&1")
  end)
  return
end

if legacy then
  -- Load as usual, and ask the shell to put Bento back where the rename left
  -- omarchy.workspaces (Omarchy swaps a clone in for its source in place).
  -- The Service it starts runs install.sh, which writes stub 2. At login the
  -- shell isn't up yet, so keep asking for a minute; the next load asks again.
  pcall(os.execute, [[setsid -f bash -c 'for try in $(seq 30); do [ "$(omarchy-shell shell enablePlugin ]] .. ID
    .. [[ "{}" 2>/dev/null)" = ok ] && exit; sleep 2; done' </dev/null >/dev/null 2>&1]])
elseif _G.bento_stub == nil then
  -- Loaded through a hook from before stub 2: after an update the shell keeps
  -- the Service from before, which never reruns install.sh. Let install.sh
  -- write stub 2 and the cleanup's copy, in the background. The reload it
  -- makes loads stub 2, so this happens once.
  pcall(function()
    os.execute("setsid -f bash '" .. ((repo .. "/install.sh"):gsub("'", "'\\''")) .. "' </dev/null >/dev/null 2>&1")
  end)
end

local S = legacy or dofile(repo .. "/hypr/settings.lua")(repo)
local lib = dofile(repo .. "/hypr/lib.lua")
lib.repo = repo
-- The shell reaches in here too: Overlay.qml hands the scratchpad over to
-- Hyprland with special_now when its stand-in comes to rest.
_G.bento = { repo = repo, settings = S, special_now = lib.special_now }

-- The state directory first: setups.lua writes its state file there.
os.execute("mkdir -p " .. lib.quote(lib.state))

-- Order matters: keyboard.lua re-registers Omarchy's Alt bindings on ⌥
-- before pages.lua and windows.lua replace some of them, setups.lua can give a
-- keyboard another keymap through what keyboard.lua shares, and windows.lua
-- uses what pages.lua shares.
-- A module that fails doesn't take the others down. Its error goes to
-- ~/.local/state/bento/errors, where bin/bento-apply looks after a reload.
local errors = {}
for _, module in ipairs({ "keyboard", "setups", "trackpad", "pages", "windows" }) do
  local ok, err = pcall(function() dofile(repo .. "/hypr/" .. module .. ".lua")(lib, S) end)
  if not ok then errors[#errors + 1] = module .. ": " .. tostring(err) end
end
local f = io.open(lib.state .. "/errors", "w")
if f then
  f:write(table.concat(errors, "\n"))
  f:close()
end
if #errors > 0 then
  lib.notify("critical", "Bento", table.concat(errors, "\n"))
end

-- Bento's surfaces (Overview, the drawer, the scratchpad) move themselves.
-- Hyprland fading them in and out on top of that shows as flicker, so don't,
-- as Omarchy does for its own (default/hypr/apps/omarchy-shell.lua).
hl.layer_rule({ match = { namespace = "^bento-" }, no_anim = true, animation = "none" })

-- The Bento app: a floating window, centred.
hl.window_rule({ match = { title = "^Bento$" }, float = true, center = true, size = { 860, 600 } })
