-- Helpers shared by Bento's modules. Modules can also hang functions on this
-- table for later modules (pages.lua adds lib.pages for windows.lua).
local lib = {}

lib.home = os.getenv("HOME")
lib.omarchy = os.getenv("OMARCHY_PATH") or "/usr/share/omarchy"
lib.state = lib.home .. "/.local/state/bento"
lib.plugin = "io.github.benjaminsehl.bento"

function lib.exists(path)
  local f = io.open(path, "r")
  if f then f:close() end
  return f ~= nil
end

-- Same send technique as Omarchy's clipboard bindings, with the down/up split
-- that works around Hyprland leaving synthetic key state stuck
-- (hyprwm/Hyprland#14099). Sent keys never trigger Hyprland's own bindings.
function lib.send_once(mods, key)
  hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
  hl.timer(function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
  end, { timeout = 50, type = "oneshot" })
end

-- Omarchy's `terminal` window tag; dynamic tags carry a trailing "*".
function lib.is_terminal(window)
  window = window or hl.get_active_window()
  for _, tag in ipairs(window and window.tags or {}) do
    if tag:gsub("%*$", "") == "terminal" then return true end
  end
  return false
end

local browsers = { "chrom", "firefox", "brave", "zen", "helium", "vivaldi" }
function lib.is_browser(window)
  local class = ((window or hl.get_active_window() or {}).class or ""):lower()
  for _, name in ipairs(browsers) do
    if class:find(name, 1, true) then return true end
  end
  return false
end

-- A key that sends one thing to apps and another (or nothing) to terminals.
function lib.send(app, term)
  return function()
    local to = lib.is_terminal() and term or app
    if to then lib.send_once(to[1], to[2]) end
  end
end

function lib.rebind(keys, description, dispatcher, options)
  hl.unbind(keys)
  o.bind(keys, description, dispatcher, options)
end

-- Finger counts from a setting: "3", "4" or "3 and 4".
function lib.fingers(setting)
  local out = {}
  for n in tostring(setting):gmatch("%d") do out[#out + 1] = tonumber(n) end
  return out
end

-- ----------------------------------------------------- hidden workspaces
-- The scratchpad and "minimized" are special workspaces. Showing one hides
-- whichever is open first. Listeners in lib.on_special_change run after.
lib.on_special_change = {}
local function changed()
  for _, fn in ipairs(lib.on_special_change) do
    hl.timer(fn, { timeout = 60, type = "oneshot" })
  end
end

function lib.open_special()
  local ws = hl.get_active_special_workspace()
  return ws and ws.name and (ws.name:gsub("^special:", "")) or nil
end

function lib.show_special(name)
  local open = lib.open_special()
  if open == name then return end
  if open then hl.dispatch(hl.dsp.workspace.toggle_special(open)) end
  hl.dispatch(hl.dsp.workspace.toggle_special(name))
  changed()
end

function lib.hide_special()
  local open = lib.open_special()
  if open then hl.dispatch(hl.dsp.workspace.toggle_special(open)) end
  changed()
end

function lib.toggle_scratchpad()
  if lib.open_special() == "scratchpad" then lib.hide_special() else lib.show_special("scratchpad") end
end

-- ------------------------------------------------------------- overlay
-- Overlay.qml has the views "overview", "drawer" and "preferences", and sets
-- _G.bento_view to the one that's open.
function lib.view() return _G.bento_view end

function lib.show(view)
  _G.bento_view = view
  hl.exec_cmd("omarchy-shell shell summon " .. lib.plugin .. " '{\"view\":\"" .. view .. "\"}'")
end

function lib.hide_overlay()
  _G.bento_view = nil
  hl.exec_cmd("omarchy-shell shell hide " .. lib.plugin)
end

return lib
