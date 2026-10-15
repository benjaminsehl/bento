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

for n = 1, 10 do
  local key = "code:" .. tostring(n + 9) -- 1..9, 0 by key code so Shift doesn't change them
  rebind("SUPER + " .. key, "Switch to page " .. n, go(n))
  rebind("SUPER + SHIFT + " .. key, "Move window to page " .. n, move(n, true))
  rebind("SUPER + SHIFT + ALT + " .. key, "Move window silently to page " .. n, move(n, false))
end
