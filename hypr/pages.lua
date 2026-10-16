-- Pages: workspaces as an ordered row of pages, shown as dots in the bar
-- (pages/BarWidget.qml).
--
--   number keys    SUPER + N goes to the Nth dot, not workspace id N
--   left edge      an empty page waits left of the first one, so you can swipe
--                  left past the first dot to start a new first page
--   slide on       close or minimize a page's last window and you slide to
--                  the next page on the right
--
-- Hyprland drops a workspace once it's empty and you leave it, so the ids
-- that remain have gaps (3, 4, 7, ...). The dots count positions, never ids.
-- lib.pages shares pages(), slide_on_if_empty() and show_desktop() with
-- windows.lua.
return function(lib, S)
  local P = S.pages
  local M = {}
  lib.pages = M

  -- The pages, in dot order: workspaces with windows, plus the focused one.
  function M.pages()
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

  -- ------------------------------------------------------------ left edge
  -- Hyprland can only make a new workspace by swiping past the last one. To
  -- swipe left past the first dot too, keep one empty, persistent workspace
  -- just left of each monitor's first page. The bar doesn't show it until
  -- you're on it, and then it's dot #1. Open a window there and it becomes a
  -- real page, and a new empty one is placed to its left.
  --
  -- Ids can't go below 1, so new sessions start at 1001. If a monitor still
  -- runs out of room, its pages are shifted up by 1000 once.
  local BASE = 1000
  M.edges = {} -- monitor name -> { id = workspace id, rule = HL.WorkspaceRule }

  if P.leftEdge then
    local edges = M.edges
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
  end

  -- -------------------------------------------------------- emptied pages
  -- Close or minimize the last window on the page you're on and you slide to
  -- the next page on the right. On the rightmost page you stay on the empty
  -- screen.
  function M.slide_on_if_empty(id, monitor)
    if not P.slideOnEmpty then return end
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
    M.slide_on_if_empty(ws.id, ws.monitor and ws.monitor.name)
  end)

  -- -------------------------------------------------------- show desktop
  -- The empty page left of the first one (or a new one at the end). Again to
  -- come back. Going anywhere else by hand forgets the way back.
  local desktop_from = nil
  function M.desktop_showing() return desktop_from ~= nil end
  function M.show_desktop()
    if desktop_from then
      hl.dispatch(hl.dsp.focus({ workspace = desktop_from }))
      desktop_from = nil
      return
    end
    local ws = hl.get_active_workspace()
    if not ws or ws.windows == 0 then return end -- already on an empty page
    local mon = hl.get_active_monitor()
    local edge = mon and M.edges[mon.name]
    desktop_from = tostring(ws.id)
    local ids = M.pages()
    hl.dispatch(hl.dsp.focus({ workspace = tostring(edge and edge.id or ((ids[#ids] or 0) + 1)) }))
  end
  hl.on("workspace.active", function()
    local ws = hl.get_active_workspace()
    if desktop_from and ws and ws.windows > 0 and tostring(ws.id) ~= desktop_from then desktop_from = nil end
  end)

  -- ----------------------------------------------------------- animation
  -- Omarchy turns workspace animations off; slide in 180 ms instead.
  if P.slideAnimation then
    hl.curve("easeOutCubic", { type = "bezier", points = { { 0.33, 1 }, { 0.68, 1 } } })
    hl.animation({ leaf = "workspaces", enabled = true, speed = 1.8, bezier = "easeOutCubic", style = "slide" })
  end

  -- --------------------------------------------------------- number keys
  -- SUPER + N (⌃N with Bento's keys) goes to the Nth dot. A number past the
  -- last dot opens a new, empty page at the end.
  if not P.numberKeys then return end

  local function target(n)
    local ids, active = M.pages()
    if ids[n] then return ids[n] end
    if active and not active.special and active.windows == 0 and ids[#ids] == active.id then
      return active.id -- already on an empty new page at the end
    end
    return (ids[#ids] or 0) + 1
  end

  local function go(n)
    return function() hl.dispatch(hl.dsp.focus({ workspace = tostring(target(n)) })) end
  end

  local function move(n, follow)
    return function()
      if not hl.get_active_window() then return end
      hl.dispatch(hl.dsp.window.move({ workspace = tostring(target(n)), follow = follow }))
    end
  end

  -- With Mac modifiers nothing sends Alt: keyboard.lua moved Omarchy's Alt
  -- bindings to ⌥ (MOD5), so replace those too.
  local alt = S.keyboard.macModifiers and "MOD5" or "ALT"
  for n = 1, 10 do
    local key = "code:" .. tostring(n + 9) -- 1..9, 0 by key code so Shift doesn't change them
    lib.rebind("SUPER + " .. key, "Switch to page " .. n, go(n))
    lib.rebind("SUPER + SHIFT + " .. key, "Move window to page " .. n, move(n, true))
    lib.rebind("SUPER + SHIFT + " .. alt .. " + " .. key, "Move window silently to page " .. n, move(n, false))
    if alt ~= "ALT" then hl.unbind("SUPER + SHIFT + ALT + " .. key) end
  end
end
