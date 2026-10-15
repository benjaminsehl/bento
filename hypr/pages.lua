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
