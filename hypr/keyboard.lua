-- Keyboard: Mac modifiers, text editing, ⌘ app shortcuts, the Magic Keyboard
-- top row and Caps Lock dictation.
--
-- Bento's keyboard layout (xkb/symbols/bento) swaps the modifiers themselves:
--
--   you press   Linux sees          so
--   ⌘           CTRL                apps get native Ctrl shortcuts
--   ⌃           SUPER               Omarchy's Super bindings live on ⌃
--   ⌥           MOD5 (Option)       Mac special characters
--
-- Bindings are written the way Linux sees them, with the Mac keys in the
-- comments. Everything here depends on that swap, so with Mac modifiers off
-- this whole module stays out.
return function(lib, S)
  local K = S.keyboard
  if not K.macModifiers then return end
  local rebind, send, send_once, is_terminal = lib.rebind, lib.send, lib.send_once, lib.is_terminal

  -- -------------------------------------------------------------- keymaps
  -- install.sh compiles one keymap per keyboard type into ~/.local/state/bento.
  -- Keyboards not listed keep Omarchy's layout.
  local keyboards = {
    { name = "apple-inc.-magic-keyboard-with-touch-id", keymap = "apple" },
    { name = "at-translated-set-2-keyboard", keymap = "pc" },
  }
  for _, k in ipairs(keyboards) do
    local file = lib.state .. "/keymap-" .. k.keymap .. ".xkb"
    if lib.exists(file) then hl.device({ name = k.name, kb_file = file }) end
  end

  -- ----------------------------------------------- Omarchy's Alt, on Option
  -- No key sends Alt any more, so every Omarchy binding that uses ALT would be
  -- out of reach. Re-read Omarchy's own binding files and register each of
  -- those again with ALT replaced by MOD5 (⌥). Everything else they bind is
  -- skipped, so nothing is bound twice, and Omarchy updates carry over.
  do
    local real_bind, real_on = hl.bind, hl.on
    hl.bind = function(keys, dispatcher, opts)
      if type(keys) == "string" and keys:find("%f[%w]ALT%f[%W]") then
        real_bind((keys:gsub("%f[%w]ALT%f[%W]", "MOD5")), dispatcher, opts)
      end
    end
    hl.on = function() end
    for _, file in ipairs({ "media", "clipboard", "tiling", "utilities", "voxtype", "applications" }) do
      local path = lib.omarchy .. "/default/hypr/bindings/" .. file .. ".lua"
      if lib.exists(path) then pcall(dofile, path) end
    end
    hl.bind, hl.on = real_bind, real_on
  end

  -- ----------------------------------------------------- ⌃ + letter: shell
  -- macOS uses plain ⌃ + letter for shell and line-editing keys. Omarchy's
  -- Super+letter bindings go: copy/paste/cut and close are native on ⌘ now,
  -- and the window actions move to ⌃⌥ below. Ghostty turns ⌃ + letter into
  -- control characters (ghostty/bento.conf).
  for _, key in ipairs({ "C", "V", "X", "W", "J", "P", "T", "F", "O", "L", "S", "G", "K" }) do
    hl.unbind("SUPER + " .. key)
  end

  -- ------------------------------------------------------------ ⌃⌥: windows
  rebind("SUPER + MOD5 + F", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
  rebind("SUPER + MOD5 + RETURN", "Full width", hl.dsp.window.fullscreen({ mode = "maximized" }))
  rebind("SUPER + MOD5 + T", "Toggle window floating/tiling", hl.dsp.window.float({ action = "toggle" }))
  rebind("SUPER + MOD5 + O", "Pop window out (float & pin)", "omarchy-hyprland-window-pop")
  rebind("SUPER + MOD5 + L", "Toggle workspace layout", "omarchy-hyprland-workspace-layout-toggle")
  rebind("SUPER + MOD5 + S", "Toggle scratchpad", lib.toggle_scratchpad)
  rebind("SUPER + MOD5 + SHIFT + S", "Move window to scratchpad", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))
  rebind("SUPER + CTRL + MOD5 + F", "Tiled full screen", "omarchy-hyprland-window-tiled-fullscreen-toggle")
  for _, a in ipairs({ { "LEFT", "l", "left" }, { "RIGHT", "r", "right" }, { "UP", "u", "above" }, { "DOWN", "d", "below" } }) do
    rebind("SUPER + MOD5 + " .. a[1], "Focus on " .. a[3] .. " window", hl.dsp.focus({ direction = a[2] }))
  end

  -- --------------------------------------------------------- ⌃: desktops
  -- windows.lua puts Exposé on ⌃↑ and the drawer on ⌃↓ when they're on.
  rebind("SUPER + LEFT", "Previous workspace", hl.dsp.focus({ workspace = "e-1" }))
  rebind("SUPER + RIGHT", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))
  rebind("SUPER + UP", "Toggle scratchpad", lib.toggle_scratchpad)
  rebind("SUPER + DOWN", "Hide the scratchpad", lib.hide_special)

  -- ⌃Tab is the app's next tab, as on a Mac.
  rebind("SUPER + TAB", "Next tab", send({ "CTRL", "Tab" }, { "CTRL", "Tab" }))
  rebind("SUPER + SHIFT + TAB", "Previous tab", send({ "CTRL SHIFT", "Tab" }, { "CTRL SHIFT", "Tab" }))

  -- ------------------------------------------------------- text editing
  if K.textEditing then
    -- ⌃A ⌃E ⌃K edit the line in any app, as on a Mac. Terminals get the key itself.
    local function line_key(app_steps, key)
      return function()
        if is_terminal() then
          send_once("SUPER", key)
          return
        end
        for i, step in ipairs(app_steps) do
          hl.timer(function() send_once(step[1], step[2]) end, { timeout = 1 + (i - 1) * 80, type = "oneshot" })
        end
      end
    end
    o.bind("SUPER + A", "Line start", line_key({ { "", "Home" } }, "A"))
    o.bind("SUPER + E", "Line end", line_key({ { "", "End" } }, "E"))
    o.bind("SUPER + K", "Delete to line end", line_key({ { "SHIFT", "End" }, { "", "Delete" } }, "K"))

    -- Caret keys. Terminals get the key itself; Ghostty maps it the macOS way.
    local caret = {
      { "CTRL + LEFT", "Line start", { "", "Home" }, { "CTRL", "LEFT" } },
      { "CTRL + RIGHT", "Line end", { "", "End" }, { "CTRL", "RIGHT" } },
      { "CTRL + UP", "Document start", { "CTRL", "Home" }, { "CTRL", "UP" } },
      { "CTRL + DOWN", "Document end", { "CTRL", "End" }, { "CTRL", "DOWN" } },
      { "CTRL + SHIFT + LEFT", "Select to line start", { "SHIFT", "Home" } },
      { "CTRL + SHIFT + RIGHT", "Select to line end", { "SHIFT", "End" } },
      { "CTRL + SHIFT + UP", "Select to document start", { "CTRL SHIFT", "Home" } },
      { "CTRL + SHIFT + DOWN", "Select to document end", { "CTRL SHIFT", "End" } },
      { "MOD5 + LEFT", "Word back", { "CTRL", "LEFT" }, { "ALT", "LEFT" } },
      { "MOD5 + RIGHT", "Word forward", { "CTRL", "RIGHT" }, { "ALT", "RIGHT" } },
      { "MOD5 + SHIFT + LEFT", "Select word back", { "CTRL SHIFT", "LEFT" } },
      { "MOD5 + SHIFT + RIGHT", "Select word forward", { "CTRL SHIFT", "RIGHT" } },
      { "MOD5 + UP", "Move line up", { "ALT", "UP" }, { "ALT", "UP" } },
      { "MOD5 + DOWN", "Move line down", { "ALT", "DOWN" }, { "ALT", "DOWN" } },
      { "MOD5 + BACKSPACE", "Delete word", { "CTRL", "BackSpace" }, { "ALT", "BackSpace" } },
    }
    for _, c in ipairs(caret) do rebind(c[1], c[2], send(c[3], c[4])) end

    -- ⌘⌫: delete to line start. Ghostty has its own ⌘⌫.
    o.bind("CTRL + BACKSPACE", "Delete to line start", function()
      if is_terminal() then
        send_once("CTRL", "BackSpace")
        return
      end
      send_once("SHIFT", "Home")
      hl.timer(function() send_once("", "BackSpace") end, { timeout = 80, type = "oneshot" })
    end)

    -- ⌘[ ⌘]: back / forward in browsers; everywhere else the app's own ⌘[ ⌘]
    -- (VS Code indents with them).
    local function browser_or_self(browser_key, key)
      return function()
        if lib.is_browser() then send_once("ALT", browser_key) else send_once("CTRL", key) end
      end
    end
    o.bind("CTRL + BRACKETLEFT", "Back", browser_or_self("LEFT", "bracketleft"))
    o.bind("CTRL + BRACKETRIGHT", "Forward", browser_or_self("RIGHT", "bracketright"))

    -- ⌘⇧[ ⌘⇧]: previous / next tab. Ghostty has its own.
    o.bind("CTRL + SHIFT + BRACKETLEFT", "Previous tab", send({ "CTRL SHIFT", "Tab" }, { "CTRL SHIFT", "bracketleft" }))
    o.bind("CTRL + SHIFT + BRACKETRIGHT", "Next tab", send({ "CTRL", "Tab" }, { "CTRL SHIFT", "bracketright" }))
  end

  -- ------------------------------------------------------- ⌘ app shortcuts
  if K.appShortcuts then
    -- ⌘W: close the tab, and the window once no tab closed. Hyprland can't see
    -- tabs, so send Ctrl+W and look again 300 ms later: a closed tab changes
    -- the title, a closed last tab or a save dialog moves focus. Browsers and
    -- terminals close their own last tab's window.
    o.bind("CTRL + W", "Close tab", function()
      local window = hl.get_active_window()
      if not window then return end
      send_once("CTRL", "W")
      if is_terminal(window) or lib.is_browser(window) then return end
      local address, title = window.address, window.title
      hl.timer(function()
        local now = hl.get_active_window()
        if now and now.address == address and now.title == title then
          hl.dispatch(hl.dsp.window.close())
        end
      end, { timeout = 300, type = "oneshot" })
    end)

    -- ⌘Q: quit the app by closing every window it has. Each app still gets to
    -- ask about unsaved work.
    o.bind("CTRL + Q", "Quit app", function()
      local window = hl.get_active_window()
      if not window or not window.class or window.class == "" then return end
      for _, w in ipairs(hl.get_windows({ class = window.class })) do
        hl.dispatch(hl.dsp.window.close({ window = "address:" .. w.address }))
      end
    end)

    -- ⌘Tab ⌘⇧Tab: next / previous window. ⌘`: next window of the same app.
    o.bind("CTRL + TAB", "Next window", hl.dsp.window.cycle_next())
    o.bind("CTRL + TAB", "Reveal active window on top", hl.dsp.window.bring_to_top())
    o.bind("CTRL + SHIFT + TAB", "Previous window", hl.dsp.window.cycle_next({ next = false }))
    o.bind("CTRL + SHIFT + TAB", "Reveal active window on top", hl.dsp.window.bring_to_top())
    o.bind("CTRL + GRAVE", "Next window of the same app", function()
      local window = hl.get_active_window()
      if not window then return end
      local same = hl.get_windows({ class = window.class })
      if #same < 2 then return end
      table.sort(same, function(a, b) return a.address < b.address end)
      for i, w in ipairs(same) do
        if w.address == window.address then
          hl.dispatch(hl.dsp.focus({ window = "address:" .. same[i % #same + 1].address }))
          return
        end
      end
    end)

    -- ⌘Space: app launcher. ⌃Space stays Omarchy's menu.
    o.bind("CTRL + SPACE", "Apps menu", "omarchy-menu toggle apps")

    -- ⌘↩ ⌘⇧↩: terminal and browser, like Omarchy's ⌃↩ ⌃⇧↩.
    o.bind("CTRL + RETURN", "Terminal", { omarchy = "terminal" })
    o.bind("CTRL + SHIFT + RETURN", "Browser", { omarchy = "browser" })

    -- ⌘⇧3 ⌘⇧4 ⌘⇧5 screenshots; ⌃ added copies to the clipboard only. Number
    -- keys bind by key code (3 is code:12), since Shift changes their symbol.
    o.bind("CTRL + SHIFT + code:12", "Screenshot of the screen", "omarchy-capture-screenshot fullscreen")
    o.bind("CTRL + SHIFT + code:13", "Screenshot of an area or window", "omarchy-capture-screenshot smart")
    o.bind("CTRL + SHIFT + code:14", "Capture menu", "omarchy-menu toggle trigger.capture")
    o.bind("SUPER + CTRL + SHIFT + code:12", "Copy the screen", "omarchy-capture-screenshot fullscreen copy")
    o.bind("SUPER + CTRL + SHIFT + code:13", "Copy an area or window", "omarchy-capture-screenshot smart copy")

    -- ⌥⌘Esc: force quit.
    o.bind("CTRL + MOD5 + ESCAPE", "Force quit window", hl.dsp.window.kill())

    -- ⌃⌘: macOS's own keys. (⌃⌘, for the Bento app is in windows.lua.)
    rebind("SUPER + CTRL + F", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
    rebind("SUPER + CTRL + Q", "Lock system", "omarchy-system-lock")
    rebind("SUPER + CTRL + SPACE", "Emojis", "omarchy-shell shell toggle omarchy.emojis")
    rebind("SUPER + CTRL + K", "Keybindings", lib.home .. "/.local/bin/mac-keybindings")
  end

  -- ------------------------------------------------- Magic Keyboard top row
  -- With hid_apple fnmode=1 (system/apple-fnmode.sh) the top row sends its
  -- Mac functions without fn. windows.lua puts Exposé on Mission Control.
  if K.topRow then
    local apple = { inclusive = true, list = { "apple-inc.-magic-keyboard-with-touch-id" } }
    local not_apple = { inclusive = false, list = { "apple-inc.-magic-keyboard-with-touch-id" } }
    o.bind("XF86LaunchA", "Mission Control (scratchpad)", lib.toggle_scratchpad)
    o.bind("XF86Search", "Apps menu", "omarchy-menu toggle apps")
    hl.unbind("XF86AudioMicMute")
    o.bind("XF86AudioMicMute", "Mute microphone", "omarchy-audio-input-mute", { locked = true, device = not_apple })
    if o.cmd_present("voxtype") and K.dictation then
      o.bind("XF86AudioMicMute", "Toggle dictation", "voxtype record toggle", { device = apple })
    end
    o.bind_toggle("XF86Sleep", "Toggle silencing notifications", "notification-silencing")
  end

  -- ------------------------------------------------ Caps Lock: push-to-talk
  -- The keymap makes Caps Lock F13. F9 goes back to apps (VS Code breakpoints).
  hl.unbind("F9")
  if K.dictation and o.cmd_present("voxtype") then
    o.bind("F13", "Start dictation (push-to-talk)", "voxtype record start")
    o.bind("F13", "Stop dictation (push-to-talk)", "voxtype record stop", { release = true })
  end
end
