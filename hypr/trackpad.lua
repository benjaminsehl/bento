-- Trackpad: scrolling, tapping, and swiping sideways between pages. Pinching
-- and swiping up and down belong to windows.lua (Overview, the drawer).
return function(lib, S)
  local T = S.trackpad

  hl.config({ input = { touchpad = { natural_scroll = T.naturalScroll, tap_to_click = T.tapToClick } } })

  if not T.swipe then return end

  -- Pages follow the fingers sideways.
  for _, n in ipairs(lib.fingers(T.swipeFingers)) do
    hl.gesture({ fingers = n, direction = "horizontal", action = "workspace" })
  end

  -- A flick switches; a slow drag peeks and snaps back unless past halfway.
  local swipe = {
    workspace_swipe_distance = 300,
    workspace_swipe_min_speed_to_force = 10,
    workspace_swipe_cancel_ratio = 0.5,
  }
  hl.config({ gestures = swipe })
  if not T.swipeLock then return end

  -- While the scratchpad (or any hidden workspace) is open, sideways swipes
  -- don't change page. Hyprland can't switch a gesture off, so make the swipe
  -- so long and so hard to commit that it never does, and put it back when
  -- the hidden workspace closes.
  local locked_swipe = {
    workspace_swipe_distance = 1000000,
    workspace_swipe_min_speed_to_force = 1000000,
    workspace_swipe_cancel_ratio = 1,
  }
  -- The same, as text for lib.eval: after the load, a change of config
  -- doesn't come from an event or a timer (docs/safety.md, rule 2).
  local function chunk(g)
    return string.format("hl.config({ gestures = { workspace_swipe_distance = %d, "
      .. "workspace_swipe_min_speed_to_force = %d, workspace_swipe_cancel_ratio = %.3f } })",
      g.workspace_swipe_distance, g.workspace_swipe_min_speed_to_force, g.workspace_swipe_cancel_ratio)
  end
  local swipe_locked = false
  local function sync()
    local lock = lib.open_special() ~= nil
    if lock ~= swipe_locked then
      swipe_locked = lock
      lib.eval(chunk(lock and locked_swipe or swipe))
    end
  end
  if lib.open_special() ~= nil then
    swipe_locked = true
    hl.config({ gestures = locked_swipe })
  end
  table.insert(lib.on_special_change, sync)
  for _, event in ipairs({ "workspace.special_active", "workspace.active", "monitor.focused" }) do
    hl.on(event, function() sync() end)
  end
end
