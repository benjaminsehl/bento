-- Keyboard: each keyboard's keymap, and Omarchy's Alt bindings on Option.
-- The bindings themselves are in keys.lua, which runs once setups.lua has
-- chosen the keymaps.
--
-- Bento's keyboard layout (xkb/symbols/bento) swaps the modifiers themselves:
--
--   you press   Linux sees          so
--   ⌘           CTRL                apps get native Ctrl shortcuts
--   ⌃           SUPER               Omarchy's Super bindings live on ⌃
--   ⌥           MOD5 (Option)       Mac special characters
--
-- With Mac modifiers off this whole module stays out.

-- Keymaps: install.sh compiles one keymap per keyboard type into
-- ~/.local/state/bento. keyboards.json in the checkout says which keyboard
-- gets which (the Keychron K3 Pro in Mac mode sends ⌃ ⌥ ⌘ in Apple's
-- positions); ~/.config/bento/keyboards.json changes or adds keyboards, field
-- by field. Each keyboard has a style:
--   mac        Apple's layout (keymap-apple), Mac bindings
--   mac-on-pc  Mac modifiers on a PC layout (keymap-pc), Mac bindings
--   pc         Omarchy's own layout and bindings, as for keyboards not listed
-- The older "keymap" field still works: apple, pc and omarchy are mac,
-- mac-on-pc and pc.
-- Shares lib.keyboards, so setups.lua can swap a style while a setup is on.
local styles = { mac = "apple", ["mac-on-pc"] = "pc", pc = "omarchy" }
local from_keymap = { apple = "mac", pc = "mac-on-pc", omarchy = "pc" }

local function keymaps(lib)
  local json = dofile(lib.repo .. "/hypr/json.lua")
  local kb_file = { omarchy = "" }
  for _, keymap in ipairs({ "apple", "pc" }) do
    local file = lib.state .. "/keymap-" .. keymap .. ".xkb"
    if lib.exists(file) then kb_file[keymap] = file end
  end

  local merged = {}
  local config = (os.getenv("XDG_CONFIG_HOME") or (lib.home .. "/.config")) .. "/bento/keyboards.json"
  for _, path in ipairs({ lib.repo .. "/keyboards.json", config }) do
    local file = json.read(path)
    if type(file) == "table" and not json.is_array(file) then
      for id, entry in pairs(file) do
        if type(entry) == "table" then
          merged[id] = merged[id] or {}
          for field, value in pairs(entry) do merged[id][field] = value end
          if not styles[entry.style] and from_keymap[entry.keymap] then merged[id].style = from_keymap[entry.keymap] end
        end
      end
    end
  end

  -- Hyprland names input devices after the kernel's names: lower case, with
  -- spaces and commas as "-", and "-1", "-2" for a second and third device
  -- with the same name. The kernel lists them with their vendor:product.
  local present, by_id = {}, {}
  local f = io.open("/proc/bus/input/devices", "r")
  if f then
    for block in ((f:read("a") or "") .. "\n\n"):gmatch("(.-)\n\n") do
      local vendor, product = block:match("I: Bus=%x+ Vendor=(%x+) Product=(%x+)")
      local name = block:match('N: Name="([^\n]*)"')
      if vendor and name then
        name = name:lower():gsub("[ ,]", "-")
        local n = present[name] or 0
        present[name] = n + 1
        if (" " .. (block:match("H: Handlers=([^\n]*)") or "") .. " "):find(" kbd ", 1, true) then
          local id = (vendor .. ":" .. product):lower()
          by_id[id] = by_id[id] or {}
          table.insert(by_id[id], n == 0 and name or (name .. "-" .. n))
        end
      end
    end
    f:close()
  end

  local list, ids = {}, {}
  for id in pairs(merged) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local entry = merged[id]
    local style = styles[entry.style] and entry.style
    if style then
      local k = { id = id, label = type(entry.label) == "string" and entry.label or id, style = style,
        own = style, connected = false, devices = json.array(), ids = {} }
      local function add(name)
        for _, known in ipairs(k.devices) do
          if known == name then return end
        end
        k.devices[#k.devices + 1] = name
        if present[name] then k.connected = true end
      end
      for _, name in ipairs(type(entry.devices) == "table" and entry.devices or {}) do
        if type(name) == "string" and name ~= "" then add(name) end
      end
      local vps = { id }
      for _, vp in ipairs(type(entry.ids) == "table" and entry.ids or {}) do vps[#vps + 1] = vp end
      for _, raw in ipairs(vps) do
        local vp = tostring(raw):lower()
        if vp:match("^%x%x%x%x:%x%x%x%x$") then
          k.ids[vp] = true
          for _, name in ipairs(by_id[vp] or {}) do
            add(name)
            k.connected = true
          end
        end
      end
      list[#list + 1] = k
    end
  end

  -- mac and mac-on-pc only when install.sh has compiled their keymaps, as
  -- before. k.bento: the keyboard really is on one of Bento's keymaps, so
  -- keys.lua gives it the Mac bindings.
  local function emit(k)
    local file = kb_file[styles[k.style]]
    if not file then return false end
    for _, name in ipairs(k.devices) do hl.device({ name = name, kb_file = file }) end
    k.bento = file ~= ""
    return true
  end
  for _, k in ipairs(list) do emit(k) end

  lib.keyboards = { list = list }
  -- id: a keyboard's id in keyboards.json, or one of its vendor:product pairs.
  function lib.keyboards.override(id, style)
    if not styles[style] then return false end
    for _, k in ipairs(list) do
      if k.id == id or k.ids[tostring(id):lower()] then
        if not kb_file[styles[style]] then return false end
        k.style, k.override = style, style
        return emit(k)
      end
    end
    return false
  end
end

return function(lib, S)
  local K = S.keyboard
  if not K.macModifiers then return end

  -- -------------------------------------------------------------- keymaps
  -- A broken keyboards.json mustn't cost Omarchy's Alt bindings: the error is
  -- raised at the end, once they're in place.
  local keymaps_ok, keymaps_err = pcall(keymaps, lib)

  -- ----------------------------------------------- Omarchy's Alt, on Option
  -- No key sends Alt any more, so every Omarchy binding that uses ALT would be
  -- out of reach. Re-read Omarchy's own binding files and register each of
  -- those again with ALT replaced by MOD5 (⌥), in lib.finish once every
  -- module has run, so a ⌥ key a module takes over is simply left out.
  -- Everything else they bind is skipped, so nothing is bound twice, and
  -- Omarchy updates carry over.
  -- The same pass records every Omarchy binding by key, so that what Bento
  -- takes away from Mac keyboards comes back on PC keyboards (lib.on_mac).
  do
    local real_bind, real_on = hl.bind, hl.on
    hl.bind = function(keys, dispatcher, opts)
      if type(keys) ~= "string" then return end
      local id = lib.key_id(keys)
      lib.omarchy_binds[id] = lib.omarchy_binds[id] or {}
      table.insert(lib.omarchy_binds[id], { keys = keys, dispatcher = dispatcher, opts = opts })
      if keys:find("%f[%w]ALT%f[%W]") then
        table.insert(lib.alt_mirrors, { keys = (keys:gsub("%f[%w]ALT%f[%W]", "MOD5")), dispatcher = dispatcher, opts = opts })
      end
    end
    hl.on = function() end
    for _, file in ipairs({ "media", "clipboard", "tiling", "utilities", "voxtype", "applications" }) do
      local path = lib.omarchy .. "/default/hypr/bindings/" .. file .. ".lua"
      if lib.exists(path) then pcall(dofile, path) end
    end
    hl.bind, hl.on = real_bind, real_on
  end

  if not keymaps_ok then error("keymaps: " .. tostring(keymaps_err), 0) end
end
