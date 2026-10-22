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

-- ------------------------------------------------------- after the load
-- An event or a timer only reads and dispatches (docs/safety.md, rule 2).
-- A config change after the load goes the way Omarchy's Scale shortcut
-- sends its rule: `hyprctl eval`, started by hl.exec_cmd, which returns at
-- once, so Hyprland runs the chunk a moment later, outside the handler.
-- Write chunks from constants and numbers only. Each runs only while this
-- load is the current one: one that lands after a reload does nothing.
-- delay_ms holds it back that long first.
lib.load = string.format("%d%06d", os.time(), math.random(0, 999999))
_G.bento_load = lib.load
function lib.eval(chunk, delay_ms)
  local guarded = "if bento_load == '" .. lib.load .. "' then " .. chunk .. " end"
  local cmd = "hyprctl eval " .. lib.quote(guarded)
  if delay_ms then cmd = string.format("sleep %.3f; %s", delay_ms / 1000, cmd) end
  hl.exec_cmd(cmd)
end

-- Takes a key over: Omarchy's binding for it goes, on every keyboard (that's
-- what hl.unbind does), and this one comes in. Only for a key that's
-- Omarchy's, or this module's from the same pass: never another module's
-- (docs/safety.md). lib.taken remembers it for lib.finish.
function lib.rebind(keys, description, dispatcher, options)
  local scope = lib.in_mac and "mac"
    or (options and options.device ~= nil and (options.device == lib.pc and "pc" or "some"))
    or "all"
  local id = lib.key_id(keys)
  lib.taken[id] = lib.taken[id] or {}
  lib.taken[id][scope] = true
  hl.unbind(keys)
  o.bind(keys, description, dispatcher, options)
end

-- Finger counts from a setting: "3", "4" or "3 and 4".
function lib.fingers(setting)
  local out = {}
  for n in tostring(setting):gmatch("%d") do out[#out + 1] = tonumber(n) end
  return out
end

-- ------------------------------------------------------- keyboard styles
-- Keyboards on Bento's keymaps (apple, pc) send ⌘ as CTRL, ⌃ as SUPER and
-- ⌥ as MOD5, and get Mac bindings. Every other keyboard is PC: its keys are
-- what's printed on them, with Omarchy's bindings. keys.lua fills these in
-- once setups.lua has chosen each keyboard's keymap:
--   lib.mac  device filter for Mac keyboards, nil when there are none
--   lib.pc   device filter for every other keyboard, nil meaning all
-- Hyprland reads an empty device list as every keyboard, so lib.mac stays
-- nil rather than empty.
lib.mac, lib.pc = nil, nil

-- Omarchy's own bindings, by key (keyboard.lua records them), and the keys
-- your ~/.config/hypr binds or unbinds itself.
lib.omarchy_binds, lib.your_keys = {}, {}

-- Bindings that wait for lib.finish, once every module has bound its keys:
-- Omarchy's Alt bindings again on ⌥ (keyboard.lua), and Omarchy's bindings
-- for keys Mac keyboards took over, on PC keyboards (lib.on_mac). Waiting
-- means no module ever has to unbind one of them. lib.taken: the keys
-- modules took over with lib.rebind, each with where ("all", "pc", "mac",
-- "some" for another device list).
lib.alt_mirrors, lib.pc_returns, lib.taken = {}, {}, {}

-- "SUPER + SHIFT + code:12" and "shift+super+CODE:12" are the same key.
function lib.key_id(keys)
  local parts = {}
  for raw in tostring(keys):gmatch("[^+]+") do
    local part = raw:gsub("^%s+", ""):gsub("%s+$", ""):upper()
    if part ~= "" then parts[#parts + 1] = part end
  end
  local key = table.remove(parts)
  table.sort(parts)
  parts[#parts + 1] = key
  return table.concat(parts, "+")
end

local function copy(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = v end
  return out
end

-- Runs fn with every binding it makes limited to Mac keyboards. Omarchy's
-- bindings for the keys it unbinds come back on PC keyboards in lib.finish,
-- unless your ~/.config/hypr binds that key itself. Without Mac keyboards fn
-- doesn't run.
function lib.on_mac(fn)
  if not lib.mac then return end
  local real_bind, real_unbind = hl.bind, hl.unbind
  hl.bind = function(keys, dispatcher, opts)
    opts = copy(opts)
    if opts.device == nil then opts.device = lib.mac end
    return real_bind(keys, dispatcher, opts)
  end
  hl.unbind = function(keys)
    lib.pc_returns[#lib.pc_returns + 1] = lib.key_id(keys)
    return real_unbind(keys)
  end
  lib.in_mac = true
  local ok, err = pcall(fn)
  lib.in_mac = nil
  hl.bind, hl.unbind = real_bind, real_unbind
  if not ok then error(err, 0) end
end

-- The bindings that waited (above), once every module has run. A key a
-- module took over since stays the module's: an Alt binding isn't put back
-- on ⌥ once anything took that ⌥ key, and Omarchy's binding doesn't come
-- back on PC keyboards once a module bound that key there too.
function lib.finish()
  for _, m in ipairs(lib.alt_mirrors) do
    if not lib.taken[lib.key_id(m.keys)] then hl.bind(m.keys, m.dispatcher, m.opts) end
  end
  local done = {}
  for _, id in ipairs(lib.pc_returns) do
    local taken = lib.taken[id] or {}
    if not done[id] and not lib.your_keys[id] and not taken.all and not taken.pc then
      done[id] = true
      for _, b in ipairs(lib.omarchy_binds[id] or {}) do
        local opts = copy(b.opts)
        opts.device = lib.pc
        hl.bind(b.keys, b.dispatcher, opts)
      end
    end
  end
end

-- A binding for PC keyboards only.
function lib.on_pc(keys, description, dispatcher, options)
  local opts = copy(options)
  opts.device = lib.pc
  o.bind(keys, description, dispatcher, opts)
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
local special_animation = 'hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 3, bezier = "easeOutQuint", style = "slidevert" })'

-- Show or hide a hidden workspace in one frame. The shell calls this when its
-- stand-in for the scratchpad comes to rest, so the real one takes over with
-- no animation of its own. It comes through a dispatch from the shell, not an
-- event; the animation comes back by eval, not from a timer.
function lib.special_now(name, show)
  local open = lib.open_special()
  if show == (open == name) then return end
  hl.animation({ leaf = "specialWorkspace", enabled = false })
  if show and open then hl.dispatch(hl.dsp.workspace.toggle_special(open)) end
  hl.dispatch(hl.dsp.workspace.toggle_special(name))
  lib.eval(special_animation, 120)
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
