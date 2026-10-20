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

-- One word for the shell that hl.exec_cmd starts: it's → 'it'\''s'.
function lib.quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- A desktop notification. Omarchy's sender can run a command when it's
-- clicked (exec: the program and its arguments); notify-send stands in where
-- that's missing. urgency: "low", "normal" or "critical".
function lib.notify(urgency, headline, body, exec)
  local function words(list)
    local out = {}
    for _, w in ipairs(list) do out[#out + 1] = lib.quote(w) end
    return table.concat(out, " ")
  end
  -- A leading "-" would read as an option.
  local args = { "-u", urgency, (tostring(headline):gsub("^%-+", "")) }
  if body and body ~= "" then args[#args + 1] = (tostring(body):gsub("^%-+", "")) end
  local sender = lib.omarchy .. "/bin/omarchy-notification-send"
  if lib.exists(sender) then
    hl.exec_cmd(lib.quote(sender) .. " " .. words(args) .. (exec and (" --exec " .. words(exec)) or ""))
  else
    hl.exec_cmd("notify-send " .. words(args))
  end
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

-- ---------------------------------------------------------- the shell
-- Bento's shell side (Overlay.qml) moves the drawer, the scratchpad and
-- Overview with your fingers. It sends a heartbeat every 10 seconds; while
-- it's fresh, Hyprland hands gestures and these keys to it as events
-- (custom>>bento>>...). Without it, Hyprland does them itself.
function lib.shell_alive()
  local seen = _G.bento_shell_seen
  return seen ~= nil and os.time() - seen < 25
end

function lib.emit(message)
  hl.dispatch(hl.dsp.event("bento>>" .. message))
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

-- Omarchy's own animation for hidden workspaces (default/hypr/looknfeel.lua),
-- put back after an instant switch.
local special_animation = { leaf = "specialWorkspace", enabled = true, speed = 3, bezier = "easeOutQuint", style = "slidevert" }

-- Show or hide a hidden workspace in one frame. The shell calls this when its
-- stand-in for the scratchpad comes to rest, so the real one takes over with
-- no animation of its own.
function lib.special_now(name, show)
  local open = lib.open_special()
  if show == (open == name) then return end
  hl.animation({ leaf = "specialWorkspace", enabled = false })
  if show and open then hl.dispatch(hl.dsp.workspace.toggle_special(open)) end
  hl.dispatch(hl.dsp.workspace.toggle_special(name))
  hl.timer(function() hl.animation(special_animation) end, { timeout = 120, type = "oneshot" })
  changed()
end

function lib.show_special(name)
  if name == "scratchpad" and lib.shell_alive() then return lib.emit("scratchpad>>show") end
  local open = lib.open_special()
  if open == name then return end
  if open then hl.dispatch(hl.dsp.workspace.toggle_special(open)) end
  hl.dispatch(hl.dsp.workspace.toggle_special(name))
  changed()
end

function lib.hide_special()
  local open = lib.open_special()
  if open == "scratchpad" and lib.shell_alive() then return lib.emit("scratchpad>>hide") end
  if open then hl.dispatch(hl.dsp.workspace.toggle_special(open)) end
  changed()
end

function lib.toggle_scratchpad()
  if lib.shell_alive() then return lib.emit("scratchpad>>toggle") end
  if lib.open_special() == "scratchpad" then lib.hide_special() else lib.show_special("scratchpad") end
end

-- ------------------------------------------------------------- overlay
-- Overlay.qml has the views "overview", "drawer" and "preferences", and sets
-- _G.bento_view to the one that's open.
function lib.view() return _G.bento_view end

function lib.show(view)
  if lib.shell_alive() then return lib.emit("show>>" .. view) end
  _G.bento_view = view
  hl.exec_cmd("omarchy-shell shell summon " .. lib.plugin .. " '{\"view\":\"" .. view .. "\"}'")
end

function lib.hide_overlay()
  if lib.shell_alive() then return lib.emit("hide") end
  _G.bento_view = nil
  hl.exec_cmd("omarchy-shell shell hide " .. lib.plugin)
end

return lib
