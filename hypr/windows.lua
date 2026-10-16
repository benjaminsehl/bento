-- Windows: minimizing (⌘M), the minimized-windows drawer, Overview, and the
-- trackpad gestures that open them. Overlay.qml draws the drawer and Overview.
--
--   four fingers together   Overview (a pinch: the gesture's scale goes below 1,
--                           which Hyprland calls "pinchout")
--   four fingers apart      show the desktop; again to come back
--   fingers down            the drawer, or put away what's open
--   fingers up              close the drawer, or show the scratchpad
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
  if T.pinch then
    hl.gesture({ fingers = 4, direction = "pinchout", action = function()
      if pages and pages.desktop_showing() then pages.show_desktop()
      elseif W.overview then toggle_overview() end
    end })
    hl.gesture({ fingers = 4, direction = "pinchin", action = function()
      if lib.view() then lib.hide_overlay()
      elseif pages then pages.show_desktop() end
    end })
  end

  if T.upDown then
    for _, n in ipairs(lib.fingers(T.upDownFingers)) do
      hl.gesture({ fingers = n, direction = "down", action = down })
      hl.gesture({ fingers = n, direction = "up", action = up })
    end
  end
end
