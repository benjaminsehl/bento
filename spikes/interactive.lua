-- Hands-on spike: temporary bindings and gestures to try by hand.
--
-- Load:   hyprctl eval 'dofile("<repo>/spikes/interactive.lua")'
-- Remove: hyprctl reload   (everything here is gone after a reload)
--
-- Every result goes to /tmp/omac-spike.log and shows a notification.

local LOG = "/tmp/omac-spike.log"

local function log(msg)
  local f = io.open(LOG, "a")
  f:write(os.date("%H:%M:%S ") .. msg .. "\n")
  f:close()
  hl.exec_cmd("notify-send -t 2000 'spike' '" .. msg:gsub("'", "") .. "'")
end

log("loaded")

-- A. Control for spike 1: a real Ctrl+F12 press must fire this, while the
--    synthetic one already didn't.
hl.bind("CTRL + F12", function() log("A: real Ctrl+F12 fired the binding") end)

-- B. Gestures. omac's 3-finger sideways stays until the reload.
hl.config({ input = { touchpad = { tap_to_click = false } } })
hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
for _, g in ipairs({
  { 3, "up" }, { 4, "up" }, { 4, "down" },
  { 4, "pinchin" }, { 4, "pinchout" }, { 5, "pinchin" }, { 5, "pinchout" },
}) do
  local fingers, direction = g[1], g[2]
  hl.gesture({
    fingers = fingers,
    direction = direction,
    action = function() log("B: " .. fingers .. " fingers " .. direction) end,
  })
end

-- C. ⌘-click: free Super+left-click so Chrome sees it.
hl.unbind("SUPER + mouse:272")

-- D. Key codes: ⌃⌥⌘K logs every key for 20 seconds, then stops by itself, so
--    nothing else you type is recorded.
local armed = false
hl.on("input.keyboard.key", function(...)
  if not armed then return end
  local parts = {}
  for _, a in ipairs({ ... }) do
    if type(a) == "table" then
      for k, v in pairs(a) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
    elseif type(a) == "userdata" then
      for _, k in ipairs({ "key", "keycode", "code", "keysym", "sym", "name", "state", "pressed", "mods", "modifiers", "utf8" }) do
        local ok, v = pcall(function() return a[k] end)
        if ok and v ~= nil then parts[#parts + 1] = k .. "=" .. tostring(v) end
      end
    else
      parts[#parts + 1] = tostring(a)
    end
  end
  local f = io.open(LOG, "a")
  f:write(os.date("%H:%M:%S ") .. "D: " .. table.concat(parts, " ") .. "\n")
  f:close()
end)

hl.bind("CTRL + ALT + SUPER + K", function()
  armed = true
  log("D: logging keys for 20 s")
  hl.timer(function()
    armed = false
    log("D: stopped logging keys")
  end, { timeout = 20000, type = "oneshot" })
end)
