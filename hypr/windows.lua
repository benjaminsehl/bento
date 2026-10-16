-- Windows: minimizing (⌘M), the minimized-windows drawer, Overview, and the
-- trackpad gestures that open them. Overlay.qml draws the drawer and Overview.
--
--   fingers together        Overview, zooming out as they go (three or four;
--                           a pinch: the gesture's scale goes below 1)
--   fingers apart           show the desktop; again to come back
--   fingers up and down     one gesture: the drawer comes down from above and
--                           the scratchpad rises from below, following the
--                           fingers. Down over Overview puts it away.
--
-- libinput recognises gestures of up to four fingers, so five can't work.
return function(lib, S)
  local W, T = S.windows, S.trackpad
  local mac = S.keyboard.macModifiers
  local pages = lib.pages

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
    if pages then pages.slide_on_if_empty(id, monitor) end
  end

  local function toggle_overview()
    if lib.view() == "overview" then lib.hide_overlay() else lib.show("overview") end
  end

  local function toggle_drawer()
    if lib.view() == "drawer" then lib.hide_overlay()
    elseif minimized_count() > 0 then lib.show("drawer") end
  end

  -- Down: put away what's open, or open the drawer when something is minimized.
  local function down()
    local v = lib.view()
    if v == "overview" or v == "preferences" then lib.hide_overlay()
    elseif v == "drawer" then return
    elseif lib.open_special() then lib.hide_special()
    elseif W.minimize and minimized_count() > 0 then lib.show("drawer") end
  end

  -- Up: close the drawer, or show the scratchpad.
  local function up()
    local v = lib.view()
    if v == "drawer" then lib.hide_overlay()
    elseif v == "overview" then return
    else lib.show_special("scratchpad") end
  end

  -- ------------------------------------------------------------- keys
  -- With Bento's keys: ⌘M minimizes, ⌃↑ and Mission Control open Overview, ⌃↓
  -- the drawer. Without them, SUPER + M minimizes.
  if W.minimize then
    lib.rebind(mac and "CTRL + M" or "SUPER + M", "Minimize window", minimize)
    if mac then lib.rebind("SUPER + DOWN", "Minimized windows", toggle_drawer) end
  end
  if W.overview and mac then
    lib.rebind("SUPER + UP", "Overview", toggle_overview)
    if S.keyboard.topRow then lib.rebind("XF86LaunchA", "Overview", toggle_overview) end
  end

  -- ⌃⌘, opens Bento's preferences, like ⌘, in an app.
  lib.rebind("SUPER + CTRL + COMMA", "Bento preferences", function() lib.show("preferences") end)

  -- --------------------------------------------------------- gestures
  -- A pinch is one gesture too. While the shell is alive, fingers coming
  -- together stream to it and Overview zooms out as they go; apart, it zooms
  -- back in. Fingers apart over the page show the desktop, and the desktop
  -- showing takes the next pinch to come back. Without the shell, the
  -- direction decides once the fingers lift.
  if T.pinch then
    local streaming, from, scale = false, nil, 1
    local function start(e)
      from, scale = lib.view(), 1
      local desktop = pages and pages.desktop_showing()
      streaming = W.overview and lib.shell_alive() and not desktop
      -- Hyprland passes this same event to update next.
      if streaming then lib.emit(string.format("zoom>>start>>1>>%d", e.time_ms)) end
    end
    local function update(e)
      scale = e.scale or scale
      if streaming then lib.emit(string.format("zoom>>move>>%.4f>>%d", scale, e.time_ms)) end
    end
    local function finish(e)
      if streaming then lib.emit(string.format("zoom>>end>>%d>>%d", e.cancelled and 1 or 0, e.time_ms)) end
      if e.cancelled or scale == 1 then return end
      local together = scale < 1
      if pages and pages.desktop_showing() then pages.show_desktop()
      elseif streaming then
        -- The shell has Overview; apart from anywhere else is Bento's to do.
        if not together and from ~= "overview" then
          if from then lib.hide_overlay() elseif pages and scale > 1.1 then pages.show_desktop() end
        end
      elseif together then
        if W.overview then toggle_overview() end
      elseif lib.view() then lib.hide_overlay()
      elseif pages then pages.show_desktop() end
    end
    for _, n in ipairs({ 3, 4 }) do
      hl.gesture({ fingers = n, direction = "pinch", action = { start = start, update = update, finish = finish } })
    end
  end

  -- Up and down are one gesture. While the shell is alive, the fingers stream
  -- to it and the drawer or the scratchpad follows them, crossing from one to
  -- the other in one movement (places/Axis.qml). Without the shell, or over
  -- another hidden workspace, the direction decides once the fingers lift.
  if T.upDown then
    local streaming, travel = false, 0

    local function start(e)
      local open = lib.open_special()
      streaming = lib.shell_alive() and (open == nil or open == "scratchpad")
      travel = 0
      -- Hyprland passes this same event to update next, so its delta counts there.
      if streaming then lib.emit(string.format("pull>>start>>0>>%d", e.time_ms)) end
    end

    local function update(e)
      local dy = e.delta and e.delta.y or 0
      travel = travel + dy
      if streaming then lib.emit(string.format("pull>>move>>%.2f>>%d", dy, e.time_ms)) end
    end

    local function finish(e)
      if streaming then
        lib.emit(string.format("pull>>end>>%d>>%d", e.cancelled and 1 or 0, e.time_ms))
      elseif not e.cancelled and travel ~= 0 then
        if travel > 0 then down() else up() end
      end
    end

    for _, n in ipairs(lib.fingers(T.upDownFingers)) do
      hl.gesture({ fingers = n, direction = "vertical", action = { start = start, update = update, finish = finish } })
    end
  end
end
