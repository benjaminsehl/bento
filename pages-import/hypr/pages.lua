-- Pages: SUPER + N goes to the Nth page dot, not workspace id N.
--
-- Hyprland drops a workspace once it's empty and you leave it, so the ids
-- that remain have gaps (3, 4, 7, ...). The bar shows them as dots in id
-- order; these bindings count the same way, so the 2nd dot is always SUPER + 2.
-- A number past the last dot opens a new, empty page at the end.
--
-- install.sh loads this file from ~/.local/state/omarchy/toggles/hypr/,
-- which Omarchy reads after ~/.config/hypr/bindings.lua.

-- The pages, in dot order: workspaces with windows, plus the focused one.
local function pages()
  local active = hl.get_active_workspace()
  local active_id = active and not active.special and active.id or nil
  local ids, seen = {}, {}
  for _, ws in ipairs(hl.get_workspaces()) do
    if not ws.special and ws.id > 0 and (ws.windows > 0 or ws.id == active_id) and not seen[ws.id] then
      seen[ws.id] = true
      ids[#ids + 1] = ws.id
    end
  end
  table.sort(ids)
  return ids, active
end

-- Workspace id for dot n; a new page after the last one when n is past the end.
local function target(n)
  local ids, active = pages()
  if ids[n] then return ids[n], false end
  if active and not active.special and active.windows == 0 and ids[#ids] == active.id then
    return active.id, true -- already on an empty new page at the end
  end
  return (ids[#ids] or 0) + 1, true
end

local function go(n)
  return function()
    hl.dispatch(hl.dsp.focus({ workspace = tostring((target(n))) }))
  end
end

local function move(n, follow)
  return function()
    if not hl.get_active_window() then return end
    local id = target(n)
    hl.dispatch(hl.dsp.window.move({ workspace = tostring(id), follow = follow }))
  end
end

-- ------------------------------------------------------------- left edge
-- Hyprland can only make a new workspace by swiping past the last one. To
-- swipe left past the first dot too, keep one empty, persistent workspace
-- just left of each monitor's first page. The bar doesn't show it until
-- you're on it, and then it's dot #1. Open a window there and it becomes a
-- real page, and a new empty one is placed to its left.
--
-- Ids can't go below 1, so new sessions start at 1001. If a monitor still
-- runs out of room, its pages are shifted up by 1000 once.
local BASE = 1000
local edges = {} -- monitor name -> { id = workspace id, rule = HL.WorkspaceRule }
local syncing, queued = false, false
local queue

local function drop_edge(name)
  local e = edges[name]
  if e and e.rule then pcall(function() e.rule:set_enabled(false) end) end
  edges[name] = nil
end

local function rebase()
  local active = hl.get_active_workspace()
  for _, ws in ipairs(hl.get_workspaces()) do
    if not ws.special and ws.id > 0 and ws.id <= BASE and ws.windows > 0 then
      for _, w in ipairs(ws:get_windows()) do
        hl.dispatch(hl.dsp.window.move({ workspace = tostring(ws.id + BASE), follow = false, window = w }))
      end
    end
  end
  if active and not active.special and active.id <= BASE then
    hl.dispatch(hl.dsp.focus({ workspace = tostring(active.id + BASE) }))
  end
end

local function sync()
  if syncing then return end
  syncing = true
  local used, by_monitor = {}, {}
  for _, ws in ipairs(hl.get_workspaces()) do
    if not ws.special and ws.id > 0 then
      used[ws.id] = ws
      local m = ws.monitor and ws.monitor.name
      if m then
        by_monitor[m] = by_monitor[m] or {}
        table.insert(by_monitor[m], ws)
      end
    end
  end

  local need_rebase = false
  for _, mon in ipairs(hl.get_monitors()) do
    local name = mon.name
    local active_id = mon.active_workspace and not mon.active_workspace.special and mon.active_workspace.id or nil
    local edge = edges[name]
    -- The first page: lowest workspace with windows, or the one you're on.
    local first
    for _, ws in ipairs(by_monitor[name] or {}) do
      if (ws.windows > 0 or ws.id == active_id) and (not first or ws.id < first.id) then first = ws end
    end

    -- Where the empty page belongs: the closest free id left of the first page.
    local id = first and first.id - 1 or 0
    while id >= 1 and used[id] and not (edge and edge.id == id and used[id].windows == 0) do id = id - 1 end

    if not first or first.windows == 0 then
      -- You're on an empty first page already; it is the left edge.
      if edge and (not first or edge.id ~= first.id) then drop_edge(name) end
    elseif edge and edge.id == id and used[id] and used[id].windows == 0 then
      -- The empty page is still right where it belongs.
    else
      drop_edge(name)
      if id >= 1 then
        local rule = hl.workspace_rule({ workspace = tostring(id), persistent = true, monitor = name })
        edges[name] = { id = id, rule = rule }
      else
        need_rebase = true
      end
    end
  end
  syncing = false
  if need_rebase then
    rebase()
    queue()
  end
end

queue = function()
  if queued then return end
  queued = true
  hl.timer(function()
    queued = false
    sync()
  end, { timeout = 60, type = "oneshot" })
end

for _, event in ipairs({
  "window.open", "window.close", "window.destroy", "window.move_to_workspace",
  "workspace.active", "workspace.created", "workspace.removed", "workspace.move_to_monitor",
  "monitor.added", "monitor.removed",
}) do
  hl.on(event, queue)
end

-- ------------------------------------------------------------- emptied pages
-- Close or minimize the last window on the page you're on and you slide to
-- the next page on the right. On the rightmost page you stay on the empty screen.
local function slide_on_if_empty(id, monitor)
  hl.timer(function()
    local active = hl.get_active_workspace()
    if not active or active.special or active.id ~= id or active.windows > 0 then return end
    local next_id
    for _, other in ipairs(hl.get_workspaces()) do
      if not other.special and other.id > id and other.windows > 0
        and (other.monitor and other.monitor.name) == monitor
        and (not next_id or other.id < next_id) then
        next_id = other.id
      end
    end
    if next_id then hl.dispatch(hl.dsp.focus({ workspace = tostring(next_id) })) end
  end, { timeout = 30, type = "oneshot" })
end

hl.on("window.close", function(w)
  local ws = w and w.workspace
  if not ws or ws.special or ws.id <= 0 then return end
  slide_on_if_empty(ws.id, ws.monitor and ws.monitor.name)
end)

-- ------------------------------------------------------------- hidden windows
-- Minimized windows live on the hidden "special:minimized" workspace, the
-- scratchpad on "special:scratchpad". Overlay.qml shows them: the drawer
-- (minimized only) and Exposé (everything). It sets _G.pages_view to the
-- view that's open, so gestures can close what they opened.
local PLUGIN = "io.github.benjaminsehl.pages"
local toggles = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/omarchy/toggles/hypr"
local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() end
  return f ~= nil
end
-- omac makes ⌘ send Ctrl and ⌃ send Super; with it, Pages uses Mac keys.
local OMAC = exists(toggles .. "/omac.lua")

local function view() return _G.pages_view end

local function show(v)
  _G.pages_view = v
  hl.exec_cmd("omarchy-shell shell summon " .. PLUGIN .. " '{\"view\":\"" .. v .. "\"}'")
end

local function hide_overlay()
  _G.pages_view = nil
  hl.exec_cmd("omarchy-shell shell hide " .. PLUGIN)
end

local function open_special()
  local ws = hl.get_active_special_workspace()
  return ws and ws.name and (ws.name:gsub("^special:", "")) or nil
end

local function show_special(name)
  local open = open_special()
  if open == name then return end
  if open then hl.dispatch(hl.dsp.workspace.toggle_special(open)) end
  hl.dispatch(hl.dsp.workspace.toggle_special(name))
end

local function hide_special()
  local open = open_special()
  if open then hl.dispatch(hl.dsp.workspace.toggle_special(open)) end
end

local function minimized_count()
  local n = 0
  for _, w in ipairs(hl.get_windows()) do
    if w.workspace and w.workspace.name == "special:minimized" then n = n + 1 end
  end
  return n
end

local function minimize()
  local w = hl.get_active_window()
  if not w or not w.workspace or w.workspace.special then return end
  local id, monitor = w.workspace.id, w.workspace.monitor and w.workspace.monitor.name
  hl.dispatch(hl.dsp.window.move({ workspace = "special:minimized", follow = false }))
  slide_on_if_empty(id, monitor)
end

local function toggle_expose()
  if view() == "expose" then hide_overlay() else show("expose") end
end

local function toggle_drawer()
  if view() == "drawer" then hide_overlay()
  elseif minimized_count() > 0 then show("drawer") end
end

-- Down: put away what's open, or open the drawer when something is minimized.
local function down()
  if view() == "expose" then hide_overlay()
  elseif view() == "drawer" then return
  elseif open_special() then hide_special()
  elseif minimized_count() > 0 then show("drawer") end
end

-- Up: close the drawer, or show the scratchpad.
local function up()
  if view() == "drawer" then hide_overlay()
  elseif view() == "expose" then return
  else show_special("scratchpad") end
end

-- Show desktop: the empty page left of the first one. Again to come back.
local desktop_from = nil
local function show_desktop()
  if desktop_from then
    hl.dispatch(hl.dsp.focus({ workspace = desktop_from }))
    desktop_from = nil
    return
  end
  local ws = hl.get_active_workspace()
  local mon = hl.get_active_monitor and hl.get_active_monitor() or (ws and ws.monitor)
  local edge = mon and edges[mon.name]
  if not ws or ws.windows == 0 then return end -- already on an empty page
  desktop_from = tostring(ws.id)
  local ids = pages()
  hl.dispatch(hl.dsp.focus({ workspace = tostring(edge and edge.id or ((ids[#ids] or 0) + 1)) }))
end
hl.on("workspace.active", function()
  -- Going anywhere else by hand forgets the way back.
  local ws = hl.get_active_workspace()
  if desktop_from and ws and ws.windows > 0 and tostring(ws.id) ~= desktop_from then desktop_from = nil end
end)

-- Pinch four fingers together for Exposé; spread them to show the desktop.
-- A pinch fires "pinchout" (the gesture's scale goes below 1). libinput
-- recognises gestures of up to four fingers, so five can't work.
hl.gesture({ fingers = 4, direction = "pinchout", action = function()
  if desktop_from then show_desktop() else toggle_expose() end
end })
hl.gesture({ fingers = 4, direction = "pinchin", action = function()
  if view() then hide_overlay() else show_desktop() end
end })

-- Three or four fingers down for the drawer, up for the scratchpad. omac
-- leaves these gestures to Pages when Pages is installed.
for _, fingers in ipairs({ 3, 4 }) do
  hl.gesture({ fingers = fingers, direction = "down", action = down })
  hl.gesture({ fingers = fingers, direction = "up", action = up })
end

-- New sessions start at workspace 1001, leaving room on the left.
hl.on("hyprland.start", function()
  hl.dispatch(hl.dsp.focus({ workspace = tostring(BASE + 1) }))
end)

queue()

-- ------------------------------------------------------------- keys
local function rebind(keys, description, action)
  hl.unbind(keys)
  o.bind(keys, description, action)
end

-- ⌘M minimizes. With omac, ⌃↑ and the Mission Control key open Exposé and
-- ⌃↓ the drawer, as on a Mac. Without omac, ⌘M is SUPER + M.
if OMAC then
  rebind("CTRL + M", "Minimize window", minimize)
  rebind("SUPER + UP", "Exposé", toggle_expose)
  rebind("SUPER + DOWN", "Minimized windows", toggle_drawer)
  rebind("XF86LaunchA", "Exposé", toggle_expose)
else
  rebind("SUPER + M", "Minimize window", minimize)
end

for n = 1, 10 do
  local key = "code:" .. tostring(n + 9) -- 1..9, 0 by key code so Shift doesn't change them
  rebind("SUPER + " .. key, "Switch to page " .. n, go(n))
  rebind("SUPER + SHIFT + " .. key, "Move window to page " .. n, move(n, true))
  rebind("SUPER + SHIFT + ALT + " .. key, "Move window silently to page " .. n, move(n, false))
end
