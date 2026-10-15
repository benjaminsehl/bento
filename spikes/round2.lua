-- Hands-on spike, round 2: the ⌘/⌃ swap, the Option layout, Omarchy's Alt
-- bindings mirrored onto Option, a few caret keys, and the Ghostty config.
--
-- Load:   spikes/round2.sh   (compiles the keymaps, then loads this file)
-- Revert: ⌃⌥⌘Esc, or wait 15 minutes, or `hyprctl reload`.
--
-- Results go to /tmp/omac-spike.log and show as notifications.

local REPO = os.getenv("HOME") .. "/Work/tries/2026-10-15-macos-keybindings"
local LOG = "/tmp/omac-spike.log"

local function log(msg)
  local f = io.open(LOG, "a")
  f:write(os.date("%H:%M:%S ") .. msg .. "\n")
  f:close()
  hl.exec_cmd("notify-send -t 2000 'spike' '" .. msg:gsub("'", "") .. "'")
end

-- Safety first: two ways back.
hl.bind("SUPER + CTRL + MOD5 + ESCAPE", function()
  log("reverting")
  hl.exec_cmd("hyprctl reload")
end)
hl.timer(function() hl.exec_cmd("hyprctl reload") end, { timeout = 15 * 60 * 1000, type = "oneshot" })

-- 1. Keyboards: Mac modifiers in Mac positions, Option characters, Caps = F13.
hl.device({ name = "apple-inc.-magic-keyboard-with-touch-id", kb_file = "/tmp/omac-keymap-apple.xkb" })
hl.device({ name = "at-translated-set-2-keyboard", kb_file = "/tmp/omac-keymap-pc.xkb" })

-- 2. Omarchy's Alt bindings, mirrored onto Option (MOD5) by re-reading its own
--    binding files with every bind that uses ALT rewritten.
local real_bind, real_on = hl.bind, hl.on
local mirrored = 0
hl.bind = function(keys, dispatcher, opts)
  if type(keys) == "string" and keys:find("%f[%w]ALT%f[%W]") then
    real_bind(keys:gsub("%f[%w]ALT%f[%W]", "MOD5"), dispatcher, opts)
    mirrored = mirrored + 1
  end
end
hl.on = function() end
local omarchy = os.getenv("OMARCHY_PATH") or "/usr/share/omarchy"
for _, file in ipairs({ "media", "clipboard", "tiling", "utilities", "voxtype", "applications" }) do
  local ok, err = pcall(dofile, omarchy .. "/default/hypr/bindings/" .. file .. ".lua")
  if not ok then log("mirror " .. file .. " failed: " .. tostring(err)) end
end
hl.bind, hl.on = real_bind, real_on
log("2: mirrored " .. mirrored .. " Omarchy Alt bindings onto Option")

-- 3. ⌃ + letter reaches apps (Ghostty turns it into control characters):
--    drop Omarchy's and omac's Super+letter bindings for the test.
for c in ("abcdefghijklmnopqrstuvwxyz"):gmatch(".") do
  hl.unbind("SUPER + " .. c:upper())
end
hl.unbind("SUPER + SHIFT + Z")

-- 4. Caret keys.
local function send_once(mods, key)
  hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
  hl.timer(function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
  end, { timeout = 50, type = "oneshot" })
end

local function is_terminal()
  local w = hl.get_active_window()
  for _, tag in ipairs(w and w.tags or {}) do
    if tag:gsub("%*$", "") == "terminal" then return true end
  end
  return false
end

-- keys: what you press (as Linux now sees it), then what apps and terminals get.
local caret = {
  { "CTRL + LEFT", { "", "Home" }, { "CTRL", "LEFT" } },               -- ⌘←
  { "CTRL + RIGHT", { "", "End" }, { "CTRL", "RIGHT" } },              -- ⌘→
  { "CTRL + UP", { "CTRL", "Home" }, { "CTRL", "UP" } },               -- ⌘↑
  { "CTRL + DOWN", { "CTRL", "End" }, { "CTRL", "DOWN" } },            -- ⌘↓
  { "CTRL + SHIFT + LEFT", { "SHIFT", "Home" }, nil },                 -- ⇧⌘←
  { "CTRL + SHIFT + RIGHT", { "SHIFT", "End" }, nil },                 -- ⇧⌘→
  { "MOD5 + LEFT", { "CTRL", "LEFT" }, { "ALT", "LEFT" } },            -- ⌥←
  { "MOD5 + RIGHT", { "CTRL", "RIGHT" }, { "ALT", "RIGHT" } },         -- ⌥→
  { "MOD5 + SHIFT + LEFT", { "CTRL SHIFT", "LEFT" }, nil },            -- ⇧⌥←
  { "MOD5 + SHIFT + RIGHT", { "CTRL SHIFT", "RIGHT" }, nil },          -- ⇧⌥→
  { "MOD5 + UP", { "ALT", "UP" }, nil },                               -- ⌥↑
  { "MOD5 + DOWN", { "ALT", "DOWN" }, nil },                           -- ⌥↓
  { "MOD5 + BACKSPACE", { "CTRL", "BackSpace" }, { "ALT", "BackSpace" } }, -- ⌥⌫
}
for _, c in ipairs(caret) do
  local keys, app, term = c[1], c[2], c[3]
  hl.unbind(keys)
  hl.bind(keys, function()
    local to = is_terminal() and term or app
    if to then send_once(to[1], to[2]) end
  end)
end

-- ⌘⌫: delete to line start (terminals: Ghostty's own ⌘⌫).
hl.bind("CTRL + BACKSPACE", function()
  if is_terminal() then
    send_once("CTRL", "BackSpace")
  else
    send_once("SHIFT", "Home")
    hl.timer(function() send_once("", "BackSpace") end, { timeout = 80, type = "oneshot" })
  end
end)

-- ⌃← / ⌃→: previous / next workspace (omac had them as caret keys).
hl.unbind("SUPER + LEFT")
hl.unbind("SUPER + RIGHT")
hl.bind("SUPER + LEFT", hl.dsp.focus({ workspace = "e-1" }))
hl.bind("SUPER + RIGHT", hl.dsp.focus({ workspace = "e+1" }))

-- 5. Caps Lock is F13 now.
hl.bind("F13", function() log("5: Caps Lock down (F13)") end)
hl.bind("F13", function() log("5: Caps Lock up (F13)") end, { release = true })

log("round 2 loaded: ⌃⌥⌘Esc reverts")
