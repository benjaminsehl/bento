-- Pages: workspaces as an ordered row of pages, shown as dots in the bar
-- (pages/BarWidget.qml).
--
--   number keys    SUPER + N goes to the Nth dot, not workspace id N
--   left edge      an empty page waits left of the first one, so you can swipe
--                  left past the first dot to start a new first page
--   slide on       close or minimize a page's last window and you slide to
--                  the next page on the right
--   moving         Overview drags a page to a new place in the row, or to
--                  another monitor
--
-- Each monitor has its own row of pages: its own dots, its own number keys
-- and its own ends to swipe past. Workspace ids are shared by every monitor,
-- so a new page takes the nearest id no other monitor has.
--
-- Hyprland drops a workspace once it's empty and you leave it, so the ids
-- that remain have gaps (3, 4, 7, ...). The dots count positions, never ids.
-- lib.pages shares pages(), slide_on_if_empty() and show_desktop() with
-- windows.lua.
return function(lib, S)
  local P = S.pages
  local M = {}
  lib.pages = M

  -- The focused monitor's pages, in dot order: workspaces with windows, plus
  -- the one you're on.
  function M.pages()
    local active = hl.get_active_workspace()
    local active_id = active and not active.special and active.id or nil
    local mon = hl.get_active_monitor()
    local name = mon and mon.name
    local ids, seen = {}, {}
    for _, ws in ipairs(hl.get_workspaces()) do
      if not ws.special and ws.id > 0 and (ws.windows > 0 or ws.id == active_id) and not seen[ws.id]
        and (not name or (ws.monitor and ws.monitor.name) == name) then
        seen[ws.id] = true
        ids[#ids + 1] = ws.id
      end
    end
    table.sort(ids)
    return ids, active
  end

  -- A new page after the focused monitor's last one: the next id that isn't
  -- a page on any monitor already.
  function M.new_page_id()
    local ids = M.pages()
    local used = {}
    for _, ws in ipairs(hl.get_workspaces()) do used[ws.id] = true end
    local id = (ids[#ids] or 0) + 1
    while used[id] do id = id + 1 end
    return id
  end

  -- ------------------------------------------------------------ left edge
  -- Hyprland can only make a new workspace by swiping past the last one. To
  -- swipe left past the first dot too, keep one empty, persistent workspace
  -- just left of each monitor's first page. The bar doesn't show it until
  -- you're on it, and then it's dot #1. Open a window there and it becomes a
  -- real page, and a new empty one is placed to its left.
  --
  -- Ids can't go below 1, so new sessions start at 1001. If a monitor still
  -- runs out of room (a monitor plugged in later starts at 1), its pages are
  -- shifted up a thousand ids at a time, to ids no other monitor has.
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

    -- Every page on the monitor moves by the same amount, so their order
    -- holds, and onto ids nothing has yet, so no two pages merge.
    local function rebase(names)
      local focused = hl.get_active_monitor()
      local back = nil
      for name in pairs(names) do
        local used, mine = {}, {}
        for _, ws in ipairs(hl.get_workspaces()) do
          used[ws.id] = true
          if not ws.special and ws.id > 0 and (ws.monitor and ws.monitor.name) == name then mine[#mine + 1] = ws end
        end
        local shift = BASE
        local function clear()
          for _, ws in ipairs(mine) do
            if used[ws.id + shift] then return false end
          end
          return true
        end
        while not clear() do shift = shift + BASE end

        local mon
        for _, m in ipairs(hl.get_monitors()) do
          if m.name == name then mon = m end
        end
        for _, ws in ipairs(mine) do
          for _, w in ipairs(ws:get_windows()) do
            hl.dispatch(hl.dsp.window.move({ workspace = tostring(ws.id + shift), follow = false, window = w }))
          end
        end
        -- Show the moved page where the old one was. Focusing it focuses its
        -- monitor too, so come back afterwards if that wasn't the one in use.
        -- An empty page didn't move: focused from elsewhere, it would open on
        -- the wrong monitor.
        local here = focused and focused.name == name
        local active = mon and mon.active_workspace
        if active and not active.special and active.id > 0 and (active.windows > 0 or here) then
          hl.dispatch(hl.dsp.focus({ workspace = tostring(active.id + shift) }))
          if not here then back = focused and focused.name end
        end
      end
      if back then hl.dispatch(hl.dsp.focus({ monitor = back })) end
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

      local need_rebase = nil
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
            need_rebase = need_rebase or {}
            need_rebase[name] = true
          end
        end
      end
      syncing = false
      if need_rebase then
        rebase(need_rebase)
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
    -- A workspace changing id has no event; move_page calls this instead.
    M.sync_edges = queue

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
    hl.dispatch(hl.dsp.focus({ workspace = tostring(edge and edge.id or M.new_page_id()) }))
  end
  hl.on("workspace.active", function()
    local ws = hl.get_active_workspace()
    if desktop_from and ws and ws.windows > 0 and tostring(ws.id) ~= desktop_from then desktop_from = nil end
  end)

  -- -------------------------------------------------------- moving pages
  -- Overview drags a page to another place in its row, or onto another
  -- monitor (overview/Overview.qml calls _G.bento.move_page). The workspace
  -- itself moves, windows, layout and all; only its id changes, since the row
  -- is in id order. It takes a free id between its new neighbours, or, when
  -- there's none, the monitor's pages take their ids again in the new order.
  local function workspace(id)
    for _, ws in ipairs(hl.get_workspaces()) do
      if ws.id == id then return ws end
    end
  end

  local function change_id(from, to)
    hl.dispatch(hl.dsp.workspace.change_id({ workspace = tostring(from), id = to }))
    return workspace(to) ~= nil
  end

  -- A monitor's pages in order, leaving out one of them.
  local function row(name, except)
    local active_id
    for _, m in ipairs(hl.get_monitors()) do
      local a = m.active_workspace
      if m.name == name and a and not a.special then active_id = a.id end
    end
    local ids = {}
    for _, ws in ipairs(hl.get_workspaces()) do
      if not ws.special and ws.id > 0 and ws.id ~= except and (ws.monitor and ws.monitor.name) == name
        and (ws.windows > 0 or ws.id == active_id) then
        ids[#ids + 1] = ws.id
      end
    end
    table.sort(ids)
    return ids
  end

  -- index counts from 1; past the end, or nil, is the end.
  function M.move_page(id, name, index)
    local ws = workspace(id)
    if not ws or ws.special or ws.id <= 0 then return end
    local focused = hl.get_active_monitor()
    local from = ws.monitor and ws.monitor.name
    name = name or from
    if name ~= from then
      hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(id), monitor = name }))
      ws = workspace(id)
      if not ws or (ws.monitor and ws.monitor.name) ~= name then return end
    end

    local others = row(name, id)
    index = math.max(1, math.min(index or #others + 1, #others + 1))
    local before, after = others[index - 1], others[index]
    if (not before or before < id) and (not after or id < after) then
      -- Already in place.
    else
      local used, top = {}, 0
      for _, w in ipairs(hl.get_workspaces()) do
        used[w.id] = true
        top = math.max(top, w.id)
      end
      local free
      if not after then
        free = before + 1
        while used[free] do free = free + 1 end
      else
        local lo = before and before + 1 or 1
        for i = after - 1, lo, -1 do
          if not used[i] then free = i; break end
        end
      end
      if free then
        change_id(id, free)
      else
        -- No room between them: the pages take their ids again, in the new
        -- order, by way of ids nothing has yet.
        local order = {}
        for i, v in ipairs(others) do order[i] = v end
        table.insert(order, index, id)
        local pool = {}
        for i, v in ipairs(order) do pool[i] = v end
        table.sort(pool)
        local moving = {}
        for i, v in ipairs(order) do
          if v ~= pool[i] then
            top = top + 1
            if not change_id(v, top) then return end
            moving[#moving + 1] = { temp = top, final = pool[i] }
          end
        end
        for _, m in ipairs(moving) do change_id(m.temp, m.final) end
      end
    end

    if M.sync_edges then M.sync_edges() end

    -- Moving a workspace to a monitor can take the focus with it; stay put.
    local now = hl.get_active_monitor()
    if focused and now and now.name ~= focused.name then hl.dispatch(hl.dsp.focus({ monitor = focused.name })) end
  end
  if _G.bento then _G.bento.move_page = M.move_page end

  -- ----------------------------------------------------------- animation
  -- Omarchy turns workspace animations off; slide in 180 ms instead.
  if P.slideAnimation then
    hl.curve("easeOutCubic", { type = "bezier", points = { { 0.33, 1 }, { 0.68, 1 } } })
    hl.animation({ leaf = "workspaces", enabled = true, speed = 1.8, bezier = "easeOutCubic", style = "slide" })
  end

  -- --------------------------------------------------------- number keys
  -- SUPER + N (⌃N with Bento's keys) goes to the Nth dot on the monitor
  -- you're on. A number past the last dot opens a new, empty page at the end.
  -- numberKey "⌘" puts switching on CTRL + N (⌘N) as well, for when there's
  -- no trackpad to swipe with; apps lose their own ⌘1 … ⌘9 then. Moving a
  -- window stays on ⌃⇧N, since ⌘⇧3 ⌘⇧4 ⌘⇧5 take screenshots.
  if not P.numberKeys then return end

  local function target(n)
    local ids, active = M.pages()
    if ids[n] then return ids[n] end
    if active and not active.special and active.windows == 0 and ids[#ids] == active.id then
      return active.id -- already on an empty new page at the end
    end
    return M.new_page_id()
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

  -- Mac keyboards send ⌥ as MOD5, where keyboard.lua moved Omarchy's Alt
  -- bindings, and PC keyboards send Alt, so both get replaced. ⌘1 … ⌘0 are
  -- for Mac keyboards only.
  local alts = S.keyboard.macModifiers and { "MOD5", "ALT" } or { "ALT" }
  local command = P.numberKey == "⌘"
  for n = 1, 10 do
    local key = "code:" .. tostring(n + 9) -- 1..9, 0 by key code so Shift doesn't change them
    lib.rebind("SUPER + " .. key, "Switch to page " .. n, go(n))
    if command then lib.on_mac(function() lib.rebind("CTRL + " .. key, "Switch to page " .. n, go(n)) end) end
    lib.rebind("SUPER + SHIFT + " .. key, "Move window to page " .. n, move(n, true))
    for _, alt in ipairs(alts) do
      lib.rebind("SUPER + SHIFT + " .. alt .. " + " .. key, "Move window silently to page " .. n, move(n, false))
    end
  end
end
