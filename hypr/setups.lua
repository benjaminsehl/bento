-- Setups: what's plugged in decides how your displays are arranged.
--
-- ~/.config/bento/setups.json lists setups (the Bento app saves them). Each
-- names the devices that identify a desk (a display, a dock, a camera) and
-- where each display goes. At every load this module picks the setup that
-- matches what's connected, sends its monitor rules, and then checks that
-- Hyprland did what it asked. ~/.local/state/bento/setup.json says what
-- happened, for `bento setup` and the app. docs/setups.md explains it all.
--
-- Some 5K displays (the LG UltraFine) are two tiles, each half of the panel
-- on its own stream. When both streams don't fit through the cable, Hyprland
-- shows half a picture, or a phantom monitor. The tile guard keeps such a
-- display on one stream: the left tile drives the whole panel at the largest
-- mode one stream carries, and the other tiles stay off. The guard runs first
-- and never depends on setups.json.
--
-- Nothing here writes to ~/.config/hypr. Rules go through hl.monitor, after
-- monitors.lua, so they win for the displays they name. Omarchy's own toggles
-- load later and still win: the lid toggles for the laptop, and the mirror
-- toggle for the external display it puts the laptop's picture on.

-- nil when x isn't a number that fits an integer.
local function int(x) return math.tointeger(math.floor((tonumber(x) or 0) + 0.5)) end

local function num_text(x)
  return (string.format("%.3f", x):gsub("0+$", ""):gsub("%.$", ""))
end

local function mode_text(m) return string.format("%dx%d@%.3f", m.w, m.h, m.refresh) end

local function fnv1a(text)
  local h = 0x811c9dc5
  for i = 1, #text do h = ((h ~ text:byte(i)) * 0x01000193) & 0xffffffff end
  return string.format("%08x", h)
end

local function read_text(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return text
end

-- Hyprland snaps a scale to the nearest n/120 that gives whole logical
-- pixels, and warns in red when it has to (Monitor.cpp). Snap first, the same
-- way, so what Bento asks for is what you get. Hyprland refuses a scale under
-- 0.25 (it sets 1 and shows a config error), so nothing goes below that, or
-- above 10, whatever a mode or a file says.
local function snap(scale, w, h)
  local base = math.floor((tonumber(scale) or 1) * 120 + 0.5)
  if base ~= base then base = 120 end
  base = math.min(1200, math.max(30, base))
  local function clean(n)
    if n < 30 or n > 1200 then return false end
    local lw, lh = w / (n / 120), h / (n / 120)
    return lw == math.floor(lw) and lh == math.floor(lh)
  end
  if clean(base) then return base / 120 end
  for i = 1, 89 do
    if clean(base + i) then return (base + i) / 120 end
    if clean(base - i) then return (base - i) / 120 end
  end
  return base / 120
end

-- The largest mode with the panel's shape that one stream carries (at most
-- 3840 wide), at its highest refresh up to 61 Hz. Never "preferred": for a
-- tile that's half the panel.
local function single_stream(modes, full_w, full_h)
  local aspect, best = full_w / full_h, nil
  for _, m in ipairs(modes) do
    if m.w > 0 and m.h > 0 and m.w <= 3840 and math.abs(m.w / m.h - aspect) <= aspect * 0.01 and m.refresh <= 61 then
      if not best or m.w * m.h > best.w * best.h or (m.w * m.h == best.w * best.h and m.refresh > best.refresh) then
        best = m
      end
    end
  end
  return best
end

local function preferred(modes)
  for _, m in ipairs(modes) do
    if m.preferred then return m end
  end
  return modes[1]
end

-- A scale that's a positive number, else nil.
local function numeric(v)
  if type(v) == "string" and (v:match("^%d+$") or v:match("^%d+%.%d+$")) then v = tonumber(v) end
  if type(v) == "number" and v > 0 and v < math.huge then return v end
  return nil
end

-- Omarchy's scale, read from ~/.config/hypr/monitors.lua the way its own
-- clamshell script reads it (omarchy-hyprland-monitor-clamshell): comments
-- cut, then the laptop's hl.monitor line, else the catch-all (output = ""),
-- else `local omarchy_monitor_scale`. A bare word is looked up as a local.
-- Whatever it can't evaluate stays as text.
local function omarchy_scales(text, internal)
  local raw, lines = {}, {}
  for l in (text .. "\n"):gmatch("([^\n]*)\n") do
    raw[#raw + 1] = l
    lines[#lines + 1] = (l:gsub("%-%-%[%[[^%]]*%]%]", ""):gsub("%-%-.*$", ""))
  end
  local function local_value(name)
    if not name:match("^[%a_][%w_]*$") then return nil end
    for _, l in ipairs(raw) do
      local rest = l:match("^%s*local%s+" .. name .. "%s*=%s*(.*)$")
      if rest then
        local v = rest:match('^"([^"]*)"%s*$') or rest:match('^"([^"]*)"%s*%-%-.*$')
          or rest:match('^([^"%s]+)%s*$') or rest:match('^([^"%s]+)%s+%-%-.*$')
        if v then return v end
      end
    end
    return nil
  end
  local function scalar(v)
    if #v >= 2 and v:match('^".*"$') then return v:sub(2, -2) end
    local r = local_value(v)
    if r and r ~= "" then return r end
    return v
  end
  local function rule_line(output)
    return '^%s*hl%.monitor%(%{.*output%s*=%s*"' .. output:gsub("%p", "%%%0") .. '"'
  end
  local function rule_value(output, key)
    local head = rule_line(output)
    for _, l in ipairs(lines) do
      if l:match(head) then
        local found, init = nil, 1
        while true do
          local s, e = l:find("[{,;%s]" .. key .. "%s*=%s*", init)
          if not s then break end
          local rest = l:sub(e + 1)
          local v = rest:match('^("[^"]*")%s*$') or rest:match('^("[^"]*")%s*[,;}]')
            or rest:match("^([^,;}%s]+)%s*$") or rest:match("^([^,;}%s]+)%s*[,;}]")
          if v then found = v end
          init = s + 1
        end
        if found then return scalar(found) end
      end
    end
    return ""
  end

  local own_rule = false
  if internal then
    local head = rule_line(internal)
    for _, l in ipairs(lines) do
      if l:match(head) then own_rule = true end
    end
  end
  local own = internal and rule_value(internal, "scale") or ""
  local catchall = rule_value("", "scale")
  local knob = local_value("omarchy_monitor_scale") or ""
  local laptop = own
  if laptop == "" then laptop = catchall end
  if laptop == "" then laptop = knob end
  return { laptop = laptop, own_rule = own_rule, catchall = catchall, knob = knob }
end

-- ---------------------------------------------------------------- setups.json
-- Checks every field. A bad setup or display is skipped, with a sentence in
-- problems; the rest still works.
local function validate(doc, problems)
  local setups = {}
  local function problem(text) problems[#problems + 1] = text end
  if type(doc) ~= "table" then
    problem("setups.json isn't a JSON object, so no setups are used")
    return setups
  end
  if doc.version ~= nil and doc.version ~= 1 then
    problem("setups.json is version " .. tostring(doc.version) .. "; this Bento reads version 1, so no setups are used")
    return setups
  end
  if type(doc.setups) ~= "table" then
    if doc.setups ~= nil then problem("setups.json's setups isn't a list, so no setups are used") end
    return setups
  end
  -- Two whole numbers Hyprland can take (it reads positions as 32-bit).
  local function pair(v, positive)
    if type(v) ~= "table" or type(v[1]) ~= "number" or type(v[2]) ~= "number" then return nil end
    if positive and (v[1] <= 0 or v[2] <= 0) then return nil end
    local a, b = int(v[1]), int(v[2])
    if not a or not b or math.abs(a) >= 1 << 30 or math.abs(b) >= 1 << 30 then return nil end
    return { a, b }
  end

  local taken = {}
  for i, s in ipairs(doc.setups) do
    local name = type(s) == "table" and type(s.name) == "string" and s.name ~= "" and s.name or ("Setup " .. i)
    if type(s) ~= "table" then
      problem(name .. " isn't a JSON object, so it's skipped")
    elseif type(s.id) ~= "string" or not s.id:match("^[a-z0-9]+$") or #s.id < 4 or #s.id > 12 then
      problem(name .. ": its id isn't 4 to 12 lowercase letters and digits, so it's skipped")
    elseif taken[s.id] then
      problem(name .. ": another setup already has the id " .. s.id .. ", so it's skipped")
    else
      -- A bad device in when would make the setup match more than it should,
      -- so it skips the whole setup.
      local when, bad = {}, nil
      if s.when ~= nil and type(s.when) ~= "table" then bad = "its when isn't a list" end
      for j, w in ipairs(type(s.when) == "table" and s.when or {}) do
        local kind, value
        if type(w) == "table" then
          if type(w.display) == "string" and w.display ~= "" then
            kind, value = "display", w.display
          elseif type(w.thunderbolt) == "string" and w.thunderbolt ~= "" then
            kind, value = "thunderbolt", w.thunderbolt:lower()
          elseif type(w.usb) == "string" and w.usb:lower():match("^%x%x%x%x:%x%x%x%x$") then
            kind, value = "usb", w.usb:lower()
          end
        end
        if not kind then
          bad = "device " .. j .. " in its when isn't a display, Thunderbolt device or USB device"
          break
        end
        local label = type(w.label) == "string" and w.label ~= "" and w.label
          or (kind == "display" and (value == "internal" and "Laptop" or "a display"))
          or (kind == "thunderbolt" and "a Thunderbolt device") or ("USB device " .. value)
        when[#when + 1] = { kind = kind, value = value, label = label }
      end

      if bad then
        problem(name .. ": " .. bad .. ", so it's skipped")
      else
        local displays, seen = {}, {}
        local list = type(s.displays) == "table" and s.displays or {}
        if s.displays ~= nil and type(s.displays) ~= "table" then problem(name .. ": its displays isn't a list") end
        for j, d in ipairs(list) do
          local what = name .. ": display " .. j
          if type(d) ~= "table" or type(d.display) ~= "string" or d.display == "" then
            problem(what .. " doesn't say which display it is")
          elseif seen[d.display] then
            problem(what .. " is " .. d.display .. " again, so it's skipped")
          elseif not pair(d.at) then
            problem(what .. " has no position (at)")
          else
            seen[d.display] = true
            local e = {
              display = d.display,
              internal = d.display == "internal",
              label = type(d.label) == "string" and d.label ~= "" and d.label or (d.display == "internal" and "Laptop" or d.display),
              at = pair(d.at),
              native = pair(d.native, true),
              size = pair(d.size, true),
              primary = d.primary == true,
              transform = 0,
            }
            if d.scale ~= nil then
              if type(d.scale) == "number" and d.scale > 0 and d.scale <= 10 then e.scale = d.scale
              else problem(what .. " has a scale that isn't a number from 0 to 10; it follows Omarchy's") end
            end
            if d.transform ~= nil then
              local t = math.tointeger(d.transform)
              if t and t >= 0 and t <= 7 then e.transform = t
              else problem(what .. " has a transform that isn't 0 to 7; it's 0") end
            end
            if type(d.mode) == "string" and d.mode:match("^%d+x%d+") then
              local w, h, r = d.mode:match("^(%d+)x(%d+)@?([%d%.]*)")
              e.mode = { w = tonumber(w), h = tonumber(h), refresh = tonumber(r) }
            end
            displays[#displays + 1] = e
          end
        end

        local keyboards = {}
        if type(s.keyboards) == "table" then
          local ids = {}
          for id in pairs(s.keyboards) do ids[#ids + 1] = tostring(id) end
          table.sort(ids)
          for _, id in ipairs(ids) do
            local keymap = s.keyboards[id]
            if keymap == "apple" or keymap == "pc" or keymap == "omarchy" then
              keyboards[#keyboards + 1] = { id = id, keymap = keymap }
            else
              problem(name .. ": keyboard " .. id .. " asks for " .. tostring(keymap) .. "; keymaps are apple, pc and omarchy")
            end
          end
        end

        taken[s.id] = true
        setups[#setups + 1] = { id = s.id, name = name, when = when, displays = displays, keyboards = keyboards }
      end
    end
  end
  return setups
end

-- ---------------------------------------------------------------- the module
return function(lib, S)
  -- omarchy-menu-keybindings reads this config with a stand-in hl, to list
  -- the keys. Its functions are tables that hand themselves back for any key,
  -- so a loop over hl.get_monitors() never ends, and nothing it says is real.
  -- No displays to set up then, and no state to write.
  if type(hl.get_monitors) ~= "function" then return end

  local json = dofile(lib.repo .. "/hypr/json.lua")
  local sysfs = dofile(lib.repo .. "/hypr/sysfs.lua")

  local config_home = os.getenv("XDG_CONFIG_HOME") or (lib.home .. "/.config")
  local setups_path = config_home .. "/bento/setups.json"
  local state_path = lib.state .. "/setup.json"
  local request_path = lib.state .. "/setup-request.json"
  -- Omarchy's scripts find these under $HOME, whatever XDG says.
  local monitors_path = lib.home .. "/.config/hypr/monitors.lua"
  local toggles = lib.home .. "/.local/state/omarchy/toggles/hypr"

  -- Bugs (not problems in setups.json) are raised at the end of the load, so
  -- they reach ~/.local/state/bento/errors, after every rule is in place.
  local errors = {}
  local function try(what, fn)
    local ok, err = pcall(fn)
    if not ok then errors[#errors + 1] = what .. ": " .. tostring(err) end
    return ok
  end
  -- A timer or event callback can't reach that file, so a bug there shows
  -- once per load as a notification.
  local complained = false
  local function safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not complained then
      complained = true
      pcall(lib.notify, "critical", "Bento setups", tostring(err))
    end
  end
  local function after(ms, fn)
    hl.timer(function() safe(fn) end, { timeout = ms, type = "oneshot" })
  end

  -- -------------------------------------------------------------- what's here
  -- hl.get_monitors(), copied into plain tables right away. It lists enabled
  -- monitors only, nothing at the first load after login, and the old layout
  -- during a reload. Right after a replug it can list a monitor at 0×0 with
  -- no modes; a mode of no size is never kept.
  local function monitors_now()
    local out = {}
    local ok, list = pcall(hl.get_monitors)
    if not ok or type(list) ~= "table" then return out end
    for _, m in ipairs(list) do
      local modes = {}
      for _, am in ipairs(type(m.available_modes) == "table" and m.available_modes or {}) do
        local w, h = int(am.width) or 0, int(am.height) or 0
        if w > 0 and h > 0 then
          modes[#modes + 1] = { w = w, h = h, refresh = tonumber(am.refresh_rate) or 0, preferred = am.preferred == true }
        end
      end
      if type(m.name) == "string" then
        out[m.name] = { name = m.name, description = m.description or "", w = int(m.width) or 0, h = int(m.height) or 0,
          refresh = tonumber(m.refresh_rate) or 0, x = int(m.x) or 0, y = int(m.y) or 0, scale = tonumber(m.scale) or 1,
          transform = int(m.transform) or 0, modes = modes }
      end
    end
    return out
  end

  -- A connector's modes: Hyprland's list when it has the output, else the
  -- kernel's sizes, which come without refresh rates (taken as 60 Hz).
  local function modes_for(name, by_name, live)
    local m = live[name]
    if m and #m.modes > 0 then return m.modes end
    local out, c = {}, by_name[name]
    for _, md in ipairs(c and c.modes or {}) do
      if not md.interlaced and md.w > 0 and md.h > 0 then
        out[#out + 1] = { w = md.w, h = md.h, refresh = 60, preferred = #out == 0, loose = true }
      end
    end
    return out
  end

  -- A group of tiles is one tiled display when no member can show the whole
  -- panel. A Studio Display's first connector can, so it's one plain display.
  -- That takes the left tile's modes: without them it's unprobed, and left
  -- alone until they come. Another tile without modes can't show the panel
  -- (right after a replug the UltraFine's right tile has none, or only
  -- 640×480).
  local function tile_kind(g, by_name, live)
    local left_known = false
    for _, m in ipairs(g.members) do
      local mw, mh = m.max_w or 0, m.max_h or 0
      for _, md in ipairs(modes_for(m.name, by_name, live)) do
        mw, mh = math.max(mw, md.w), math.max(mh, md.h)
      end
      if mw >= g.full_w and mh >= g.full_h then return "plain" end
      if m.name == g.left and mw > 0 and mh > 0 then left_known = true end
    end
    return left_known and "tiled" or "unprobed"
  end

  local function card_of(c) return c.sysfs and c.sysfs:match("^(card%d+)%-") or "" end
  local function type_of(name) return name:match("^(.-)%-%d+$") or name end

  -- One entry per connected display, in connector order.
  --
  -- A tiled display's other stream can turn up as a phantom: a connector
  -- that's connected but answers with only a partial EDID (the same key, no
  -- tile block) or none at all, listed at 640×480 or 0×0. Its description
  -- may be empty, so no desc: rule reaches it. It belongs to the display: it
  -- joins its connectors, so it's never a display of its own, and the tile
  -- guard turns it off by name. Only a display whose left tile is there takes
  -- one, so the real left tile is never mistaken for it, and only by what
  -- sysfs says, never by size, so the answer can't flip while Hyprland's
  -- sizes do. A connector with no EDID needs more: the same card and kind of
  -- connector as the left tile, and a tile position still free.
  --
  -- A display whose first tile (h_loc 0, v_loc 0) isn't among its tiles has
  -- no left tile to drive: another tile can't carry it on one stream. That
  -- first tile is often there all the same, half awake: a partial EDID (the
  -- same key, no tile block) or none, as a panel powered off at boot
  -- answers. It's the display's left tile then, never a display of its own:
  -- with modes it's driven as one; otherwise (and always when it has no
  -- EDID, as nothing says whose it is) the display is unprobed until the
  -- whole EDID comes, which changes the shape, so the settle reloads. The
  -- same display on two connectors with no tile block (both tiles half
  -- awake) is one display too.
  local function find_displays(scan, live, cache)
    local list, by_name, group_of, done, at, groups, strays = {}, {}, {}, {}, {}, {}, {}
    local orphans, taken, keyed = {}, {}, {}
    for _, c in ipairs(scan.drm) do by_name[c.name] = c end
    for _, g in ipairs(scan.tiles) do
      for _, m in ipairs(g.members) do group_of[m.name] = g end
    end
    for _, c in ipairs(scan.drm) do
      if c.status == "connected" then
        local g, d = group_of[c.name], nil
        if c.internal then
          if not done.internal then
            done.internal = true
            d = { display = "internal", label = "Laptop", internal = true, connectors = { c.name }, output = c.name }
          end
        elseif g then
          if not done[g] then
            done[g] = true
            local names, origin = {}, nil
            for _, m in ipairs(g.members) do
              names[#names + 1] = m.name
              if m.h_loc == 0 and m.v_loc == 0 then origin = m end
            end
            local kind = tile_kind(g, by_name, live)
            if kind ~= "plain" and not origin then
              -- No first tile: unprobed unless it's found among the strays.
              kind = "unprobed"
              d = { display = g.key, keys = g.keys, unprobed = true, connectors = names, output = g.left }
              orphans[#orphans + 1] = { d = d, g = g }
            elseif kind == "tiled" then
              d = { display = g.key, keys = g.keys, tiled = true, connectors = names, output = g.left, left = g.left,
                complete = g.complete, native = { g.full_w, g.full_h } }
            elseif kind == "unprobed" then
              d = { display = g.key, keys = g.keys, unprobed = true, connectors = names, output = g.left }
            else
              d = { display = g.key, keys = g.keys, connectors = { g.full or g.left }, output = g.full or g.left }
            end
            d.kind, d.phantoms, d.free = kind, {}, g.cols * g.rows - #g.members
            d.origin = origin and by_name[origin.name]
            groups[#groups + 1] = d
          end
        else
          strays[#strays + 1] = c
        end
        at[c.name] = d
      end
    end
    -- A display without its first tile takes it from the strays: the same
    -- key and no tile block, else no EDID, on the same card and kind of
    -- connector as its tiles and with a position free.
    for _, o in ipairs(orphans) do
      local d, g, left = o.d, o.g, nil
      local ref = by_name[g.left]
      for _, c in ipairs(strays) do
        if not left and not taken[c.name] and c.edid and not c.edid.tile then
          for _, k in ipairs(g.keys) do
            if k == c.edid.key then left = c end
          end
        end
      end
      for _, c in ipairs(strays) do
        if not left and not taken[c.name] and not c.edid and d.free > 0 and ref
          and card_of(c) == card_of(ref) and type_of(c.name) == type_of(ref.name) then
          -- A display whose left tile is there may take it as a phantom
          -- (below), so then it's not this one's.
          local claimed = false
          for _, gd in ipairs(groups) do
            local o = gd.origin
            if o and gd.kind ~= "plain" and gd.free > 0 and card_of(c) == card_of(o)
              and type_of(c.name) == type_of(o.name) then
              claimed = true
            end
          end
          if not claimed then left = c end
        end
      end
      if left then
        taken[left.name] = true
        local kind = left.edid and tile_kind({ members = { { name = left.name } }, left = left.name,
          full_w = g.full_w, full_h = g.full_h }, by_name, live) or "unprobed"
        if kind == "plain" then
          d.unprobed, d.connectors, d.output = nil, { left.name }, left.name
        else
          table.insert(d.connectors, 1, left.name) -- the left tile first
          if kind == "tiled" then
            d.unprobed, d.tiled, d.output, d.left = nil, true, left.name, left.name
            d.complete, d.native = d.free == 1, { g.full_w, g.full_h }
          end
        end
        d.kind = kind
      end
      for _, k in ipairs(g.keys) do keyed[k] = keyed[k] or d end
    end
    for _, c in ipairs(strays) do
      local host
      for _, gd in ipairs(groups) do
        local o = gd.origin
        if o and not host and not taken[c.name] then
          if c.edid and not c.edid.tile then
            for _, k in ipairs(gd.keys) do
              if k == c.edid.key then host = gd end
            end
          elseif not c.edid and gd.kind ~= "plain" and gd.free > 0 and card_of(c) == card_of(o)
            and type_of(c.name) == type_of(o.name) then
            gd.free = gd.free - 1
            host = gd
          end
        end
      end
      if taken[c.name] then
        -- An orphan's first tile (above).
      elseif host then
        host.phantoms[#host.phantoms + 1] = c.name
        host.connectors[#host.connectors + 1] = c.name
      elseif c.edid and keyed[c.edid.key] then
        local d = keyed[c.edid.key]
        d.connectors[#d.connectors + 1] = c.name
      elseif c.edid then
        at[c.name] = { display = c.edid.key, connectors = { c.name }, output = c.name }
        keyed[c.edid.key] = at[c.name]
      end
    end
    for _, c in ipairs(scan.drm) do
      local d = at[c.name]
      if d then
        local edid = by_name[d.output] and by_name[d.output].edid
        d.origin, d.free = nil, nil
        d.tiled = d.tiled or false
        d.internal = d.internal or false
        d.label = d.label or (edid and edid.name) or d.display
        d.modes = modes_for(d.output, by_name, live)
        -- An unprobed display's size waits for its left tile: another
        -- tile's modes (640×480, or half the panel) aren't its size.
        if not d.native and not d.unprobed then
          local p = preferred(d.modes)
          d.native = p and { p.w, p.h } or nil
        end
        local m = live[d.output]
        d.description = (m and m.description ~= "" and m.description) or cache[d.display]
        list[#list + 1] = d
      end
    end
    return list
  end

  local function is_phantom(d, name)
    for _, n in ipairs(d.phantoms or {}) do
      if n == name then return true end
    end
    return false
  end

  -- How the tile groups came out: which are tiled, and the connectors of
  -- each. A change means a load planned without the whole picture.
  local function tiled_shape(list)
    local parts = {}
    for _, d in ipairs(list) do
      if d.kind then
        local names = {}
        for _, n in ipairs(d.connectors) do names[#names + 1] = n end
        table.sort(names)
        parts[#parts + 1] = d.display .. " " .. d.kind .. " " .. table.concat(names, "+")
      end
    end
    table.sort(parts)
    return table.concat(parts, ",")
  end

  local function find(displays, key)
    for _, d in ipairs(displays) do
      if d.display == key then return d end
      for _, k in ipairs(d.keys or {}) do
        if k == key then return d end
      end
    end
    return nil
  end

  -- -------------------------------------------------------------- the state
  local prev = json.read(state_path)
  if type(prev) ~= "table" or json.is_array(prev) then prev = {} end
  local cache = {}
  for k, v in pairs(type(prev.descriptions) == "table" and prev.descriptions or {}) do
    if type(v) == "string" then cache[k] = v end
  end

  local state = {}
  -- Fields from a later Bento stay as they were.
  for k, v in pairs(prev) do state[k] = v end
  state.version = 1
  state.load = (math.tointeger(prev.load) or 0) + 1
  state.at = os.time()
  state.problems = json.array()
  state.descriptions = cache
  for _, k in ipairs({ "drift", "retry", "stopped", "guard_notice" }) do
    if type(prev[k]) ~= "string" then state[k] = nil end
  end

  -- True once the file is written. Whatever has to survive a reload (the
  -- reload breaker above all) is only good when this says so. The directory
  -- is made only while the config loads: after that, a missing one means
  -- bin/bento-cleanup took it away (Bento was turned off), and a timer or
  -- event of this load must not bring it back.
  local loading = true
  local function write_state()
    local out = {}
    for k, v in pairs(state) do out[k] = v end
    for _, k in ipairs({ "active", "hand", "hand_error", "stopped" }) do
      if out[k] == nil then out[k] = json.null end
    end
    local text = json.encode(out, 2) .. "\n"
    if json.write_atomic(state_path, text) then return true end
    if not loading then return false end
    os.execute("mkdir -p " .. lib.quote(lib.state))
    return json.write_atomic(state_path, text) == true
  end

  -- -------------------------------------------------------------- scan
  local live = monitors_now()
  local scan = { drm = {}, tiles = {}, thunderbolt = {}, usb = {} }
  local displays, internal, by_name, covered = {}, nil, {}, {}
  try("scan", function()
    scan = sysfs.scan()
    displays = find_displays(scan, live, cache)
  end)
  for _, c in ipairs(scan.drm) do
    by_name[c.name] = c
    -- Connectors seen now are this load's business; monitor.added only has
    -- to look at ones that turn up later, or that this load couldn't plan
    -- for: no modes anywhere yet.
    if c.status == "connected" and (#((live[c.name] or {}).modes or {}) > 0 or #(c.modes or {}) > 0) then
      covered[c.name] = true
    end
  end
  for _, d in ipairs(displays) do
    if d.internal then internal = d end
    if d.description and not d.internal then cache[d.display] = d.description end
    -- An unprobed tiled display gets no rules now: its tiles are for the
    -- runtime guard when Hyprland lights them.
    if d.unprobed then
      for _, n in ipairs(d.connectors) do covered[n] = nil end
    end
  end
  local shape = tiled_shape(displays)
  -- Omarchy's mirror toggle puts the laptop's picture on an external
  -- display: its rule for that display loads after Bento's and wins, and
  -- Hyprland lists a mirror nowhere. The file names it.
  local mirrored = lib.exists(toggles .. "/internal-monitor-mirror.lua")
  local mirror_output = mirrored and (read_text(toggles .. "/internal-monitor-mirror.lua") or ""):match('output%s*=%s*"([^"]+)"') or nil
  -- Omarchy turns the laptop panel off with these (lid closed, or by hand).
  local laptop_toggled = mirrored or lib.exists(toggles .. "/internal-monitor-disable.lua")
    or lib.exists(toggles .. "/internal-monitor-clamshell.lua")

  -- -------------------------------------------------------------- Omarchy's scale
  local omarchy = omarchy_scales(read_text(monitors_path) or "", internal and internal.output)
  local remembered = numeric((read_text(toggles .. "/internal-monitor-scale") or ""):match("^%s*(%S+)"))
  -- External displays follow the catch-all, as stock Omarchy does.
  local external_scale = numeric(omarchy.catchall) or (omarchy.catchall == "auto" and "auto")
    or numeric(omarchy.knob) or "auto"
  -- The laptop: a number is used as is. "auto" stays "auto". Anything else is
  -- an expression only Hyprland can evaluate: Bento's rule then leaves the
  -- scale out, so the laptop's own rule in monitors.lua keeps deciding it.
  local laptop_scale, laptop_inherit = numeric(omarchy.laptop), false
  if not laptop_scale then
    if omarchy.laptop ~= "auto" and omarchy.own_rule then laptop_inherit = true end
    laptop_scale = (omarchy.laptop ~= "auto" and remembered) or "auto"
  end
  state.laptop_scale = laptop_scale
  -- What external displays follow (bento-setup save and the Setups pane read
  -- it to tell a chosen scale from Omarchy's).
  state.external_scale = external_scale

  -- A tile's scale before it's fitted to a mode: the setup's, else Omarchy's,
  -- else about 2560 logical pixels across.
  local function default_base(native_w)
    if type(external_scale) == "number" then return external_scale end
    return math.max(1, math.floor(native_w / 2560 * 4 + 0.5) / 4)
  end

  -- Omarchy's Scale shortcut on a tile sets that scale as is
  -- (omarchy-hyprland-monitor-scaling), then writes the number into
  -- monitors.lua, and Hyprland reloads. Fitted to the panel again, the number
  -- would give the tile another scale, or the one it had. So a tile that runs
  -- Omarchy's number as is, where Bento asked for something else, keeps it
  -- while that number stays. Only for a tile that follows Omarchy's scale:
  -- a setup's own scale wins.
  local tile_scales = {}
  for k, r in pairs(type(prev.tile_scales) == "table" and prev.tile_scales or {}) do
    if type(k) == "string" and type(r) == "table" and numeric(r.knob) and numeric(r.scale) and numeric(r.w)
      and type(external_scale) == "number" and math.abs(r.knob - external_scale) <= 0.001 then
      tile_scales[k] = { knob = r.knob, scale = r.scale, w = r.w }
    end
  end

  -- A tile's scale for a mode: the setup's own (relative to the panel),
  -- else the one kept from the Scale shortcut, else Omarchy's (relative to
  -- the panel too), else about 2560 logical pixels across.
  local function tile_scale(d, mode, own)
    local r = not own and tile_scales[d.display]
    if r then return snap(r.scale * mode.w / r.w, mode.w, mode.h) end
    return snap((own or default_base(d.native[1])) * mode.w / d.native[1], mode.w, mode.h)
  end

  -- -------------------------------------------------------------- tile guard
  -- Planned before setups.json is read, so a broken file can't stop it.
  local guards = {}
  try("tile guard", function()
    for _, d in ipairs(displays) do
      if d.tiled then
        local target = single_stream(d.modes, d.native[1], d.native[2])
        if target then
          -- The other tiles and any phantom: off, by connector.
          local g = { display = d, left = d.left, target = target, others = {}, lit = {} }
          for _, name in ipairs(d.connectors) do
            if name ~= d.left then
              g.others[#g.others + 1] = name
              if live[name] then g.lit[name] = true end
            end
          end
          -- Taking over two lit tiles: there's no switching every output at
          -- once, so the others go off first while the left tile keeps its
          -- mode, and it changes mode after (pass 2, below). Only a mode
          -- with a size: right after a replug the tile can be listed at 0×0.
          local m = live[d.left]
          if m and next(g.lit) and m.w > 0 and m.h > 0 and m.refresh > 0 then
            g.pass1 = { w = m.w, h = m.h, refresh = m.refresh }
          end
          guards[#guards + 1] = g
        end
      end
    end
  end)

  -- -------------------------------------------------------------- setups
  local problems = state.problems
  local setups, active, reason, back_to_auto = {}, nil, "none", nil
  local fp, config = "", ""
  local placement = {} -- display key → { position, base, transform, label, primary }
  local entries = {}   -- the active setup's displays, resolved
  local failed_before = false
  local named = { thunderbolt = {}, usb = {} }

  local connected_tb, connected_usb = {}, {}
  for _, t in ipairs(scan.thunderbolt) do
    if t.unique_id ~= "" then connected_tb[t.unique_id] = t end
  end
  for _, u in ipairs(scan.usb) do connected_usb[u.id] = true end

  local function fingerprint(list, tb, usb)
    local ids, seen = {}, {}
    local function add(id)
      if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
    for _, d in ipairs(list) do
      if not d.internal then add("display:" .. d.display) end
    end
    for id in pairs(tb) do
      if named.thunderbolt[id] then add("tb:" .. id) end
    end
    for id in pairs(usb) do
      if named.usb[id] then add("usb:" .. id) end
    end
    table.sort(ids)
    return table.concat(ids, ",")
  end

  local function present(w)
    if w.kind == "display" then return w.value == "internal" and internal ~= nil or find(displays, w.value) ~= nil end
    if w.kind == "thunderbolt" then return connected_tb[w.value] ~= nil end
    return connected_usb[w.value] == true
  end

  local function usable(s)
    local any, missing = false, {}
    for _, e in ipairs(s.displays) do
      if not e.internal then
        any = true
        if find(displays, e.display) then return true, {} end
        missing[#missing + 1] = e.label
      end
    end
    return not any, missing
  end

  try("setups", function()
    local doc, err, text = json.read(setups_path)
    config = text and fnv1a(text) or ""
    if text and err then
      problems[#problems + 1] = "setups.json can't be read (" .. err .. "), so no setups are used"
    elseif text then
      setups = validate(doc, problems)
    end
    for _, s in ipairs(setups) do
      for _, w in ipairs(s.when) do
        if w.kind == "thunderbolt" or w.kind == "usb" then named[w.kind][w.value] = true end
      end
    end
    fp = fingerprint(displays, connected_tb, connected_usb)
    -- Marks for other devices are history: when they're back, everything
    -- may be tried once more.
    for _, k in ipairs({ "drift", "retry" }) do
      if state[k] ~= fp then state[k] = nil end
    end

    local by_id = {}
    for _, s in ipairs(setups) do by_id[s.id] = s end
    local failed = json.array()
    for _, f in ipairs(type(prev.failed) == "table" and prev.failed or {}) do
      if type(f) == "table" and type(f.id) == "string" and type(f.fingerprint) == "string" and type(f.config) == "string"
        and #failed < 50 then
        failed[#failed + 1] = { id = f.id, fingerprint = f.fingerprint, config = f.config }
      end
    end
    local function is_failed(id)
      for _, f in ipairs(failed) do
        if f.id == id and f.fingerprint == fp and f.config == config then return true end
      end
      return false
    end

    -- The app or `bento setup` asks through a request file: a setup by hand,
    -- or back to automatic. It's used once.
    local hand = type(prev.hand) == "table" and type(prev.hand.id) == "string" and prev.hand or nil
    local hand_error = type(prev.hand_error) == "string" and prev.hand_error or nil
    local request, _, request_text = json.read(request_path)
    if request_text then
      os.remove(request_path)
      -- bin/bento-setup waits for the load that took its request: the file
      -- is gone well before this load's state is written.
      state.request_load = state.load
      state.stopped = nil
      if type(request) == "table" and type(request.hand) == "string" then
        local s = by_id[request.hand]
        local ok, missing = false, {}
        if s then ok, missing = usable(s) end
        if not s then
          hand_error = "There's no setup " .. request.hand
        elseif not ok then
          hand_error = "Not connected: " .. table.concat(missing, ", ")
        else
          hand, hand_error = { id = s.id, fingerprint = fp }, nil
          for i = #failed, 1, -1 do
            if failed[i].id == s.id and failed[i].fingerprint == fp then table.remove(failed, i) end
          end
        end
      elseif type(request) == "table" then
        hand, hand_error = nil, nil
      end
    end

    -- Choose: by hand while the same things are connected; nothing more after
    -- even the fallback failed here; else the best match; else the fallback.
    if hand then
      local s = by_id[hand.id]
      if s and hand.fingerprint == fp and usable(s) then
        active, reason = s, "hand"
      else
        back_to_auto = s and s.name or hand.id
        hand = nil
      end
    end
    if state.stopped ~= fp then state.stopped = nil end
    for _, f in ipairs(failed) do
      if f.fingerprint == fp and f.config == config then failed_before = true end
    end
    if not active and not state.stopped then
      local best, best_score = nil, 0
      for _, s in ipairs(setups) do
        if #s.when > 0 and #s.when > best_score and not is_failed(s.id) and usable(s) then
          local all = true
          for _, w in ipairs(s.when) do
            if not present(w) then all = false end
          end
          if all then best, best_score = s, #s.when end
        end
      end
      if best then
        active, reason = best, "auto"
      else
        for _, s in ipairs(setups) do
          if #s.when == 0 and not is_failed(s.id) then
            active, reason = s, "fallback"
            break
          end
        end
      end
    end

    state.hand = hand
    state.hand_error = hand_error
    state.failed = failed
    state.active = active and active.id or nil
    state.reason = active and reason or "none"

    local list = json.array()
    for _, s in ipairs(setups) do
      local missing = {}
      for _, w in ipairs(s.when) do
        if not present(w) then missing[#missing + 1] = w.label end
      end
      local ok, absent = usable(s)
      local note
      if s == active then note = reason == "hand" and "Chosen by hand" or "In use"
      elseif is_failed(s.id) then note = "Failed its check"
      elseif not ok then note = "Not connected: " .. table.concat(absent, ", ")
      elseif #s.when > 0 and #missing > 0 then note = "Not matched: " .. table.concat(missing, ", ") .. " missing"
      elseif #s.when == 0 then note = "When no other setup matches"
      elseif state.stopped then note = "Stopped after a failed check"
      else note = "Another setup matches better" end
      list[#list + 1] = { id = s.id, name = s.name, matches = #s.when > 0 and #missing == 0, score = #s.when,
        usable = ok, failed = is_failed(s.id), note = note }
    end
    state.setups = list
  end)
  state.config = config

  -- The Scale shortcut (see tile_scales): a tile that runs the mode Bento
  -- asked for last time, at Omarchy's number as is instead of the scale
  -- asked for.
  try("tile scales", function()
    local asked = {}
    local r = type(prev.requested) == "table" and prev.requested.monitors
    for _, a in ipairs(type(r) == "table" and r or {}) do
      if type(a) == "table" and type(a.output) == "string" then asked[a.output] = a end
    end
    for _, g in ipairs(guards) do
      local own = false
      for _, e in ipairs(active and active.displays or {}) do
        if e.scale and find(displays, e.display) == g.display then own = true end
      end
      local m, a, t = live[g.left], asked[g.left], g.target
      local w, h = tostring(a and a.mode or ""):match("^(%d+)x(%d+)")
      if not own and m and a and type(external_scale) == "number" and numeric(a.scale)
        and tonumber(w) == t.w and tonumber(h) == t.h and m.w == t.w and m.h == t.h
        and math.abs(m.scale - a.scale) > 0.001 and math.abs(m.scale - snap(external_scale, t.w, t.h)) <= 0.001 then
        tile_scales[g.display.display] = { knob = external_scale, scale = snap(m.scale, t.w, t.h), w = t.w }
      end
    end
  end)
  state.tile_scales = next(tile_scales) and tile_scales or nil

  -- -------------------------------------------------------------- placing
  -- Where each display of the active setup goes. Positions adapt: when a
  -- display is missing or a different size now, the displays to its right
  -- (and below) move by the difference, so nothing overlaps or floats.
  local function logical(w, h, scale, transform)
    if type(scale) ~= "number" then return nil end
    if transform and transform % 2 == 1 then w, h = h, w end
    return { w / scale, h / scale }
  end

  try("placing", function()
    if not active then return end
    for _, e in ipairs(active.displays) do
      local d = e.internal and internal or find(displays, e.display)
      local x = { e = e, d = d }
      if d and d.tiled then
        local g
        for _, guard in ipairs(guards) do
          if guard.display == d then g = guard end
        end
        if g then
          x.scale = tile_scale(d, g.target, e.scale)
          x.current = logical(g.target.w, g.target.h, x.scale, e.transform)
        else
          x.d = nil -- not drivable on one stream: treat it as missing
        end
      elseif d and d.unprobed then
        x.d = nil -- no modes yet: missing until Hyprland lights it
      elseif d and d.internal then
        local p = preferred(d.modes)
        if laptop_scale == "auto" and e.scale and p then
          x.scale = snap(e.scale * p.w / ((e.native or d.native or { p.w })[1]), p.w, p.h)
        elseif not laptop_inherit then
          x.scale = laptop_scale
        end
        local s = x.scale or laptop_scale
        x.current = p and logical(p.w, p.h, type(s) == "number" and snap(s, p.w, p.h) or s, e.transform)
      elseif d then
        local p = preferred(d.modes)
        if e.mode then
          for _, m in ipairs(d.modes) do
            if m.w == e.mode.w and m.h == e.mode.h and (not e.mode.refresh or math.abs(m.refresh - e.mode.refresh) < 0.5) then
              x.mode = m
              break
            end
          end
        end
        local mode = x.mode or p
        if mode then
          if e.scale then
            local native_w = (d.native or e.native or { mode.w })[1]
            x.scale = snap(e.scale * mode.w / native_w, mode.w, mode.h)
          elseif type(external_scale) == "number" then
            x.scale = snap(external_scale, mode.w, mode.h)
          else
            x.scale = "auto"
          end
          x.current = logical(mode.w, mode.h, x.scale, e.transform)
        end
      end
      -- The rectangle it had when saved.
      local size = e.size
      if not size and e.native then
        local rel = e.scale or (e.internal and numeric(laptop_scale)) or numeric(external_scale)
        size = logical(e.native[1], e.native[2], rel, e.transform)
      end
      if not size and x.current then size = x.current end
      size = size or { 0, 0 }
      x.saved = { x = e.at[1], y = e.at[2], w = size[1], h = size[2] }
      -- Now: nothing if it's not connected; the saved size if it can't be known.
      if not x.d then x.now = { 0, 0 } else x.now = x.current or size end
      entries[#entries + 1] = x
    end

    for _, x in ipairs(entries) do
      local r, dx, dy = x.saved, 0, 0
      for _, o in ipairs(entries) do
        local q = o.saved
        if o ~= x then
          if q.x + q.w <= r.x and q.y < r.y + r.h and r.y < q.y + q.h then dx = dx + o.now[1] - q.w end
          if q.y + q.h <= r.y and q.x < r.x + r.w and r.x < q.x + q.w then dy = dy + o.now[2] - q.h end
        end
      end
      -- Left out ("auto") when it can't be a position Hyprland takes.
      local px, py = int(r.x + dx), int(r.y + dy)
      local fits = px and py and math.abs(px) < 1 << 31 and math.abs(py) < 1 << 31
      x.position = fits and { px, py } or nil
      placement[x.e.display] = { position = x.position, own = x.e.scale, transform = x.e.transform, label = x.e.label }
    end
  end)

  -- -------------------------------------------------------------- the rules
  -- Each rule asked for, in order. requested (in the state) and the check
  -- are made from these.
  local items, pass2 = {}, { pending = false, items = {}, waiting = {} }

  local function rule_of(it)
    if it.disabled then return { output = it.output, disabled = true } end
    local rule = { output = it.output, mode = it.mode_text }
    local p = it.position
    rule.position = p and math.type(p[1]) == "integer" and math.type(p[2]) == "integer"
      and string.format("%dx%d", p[1], p[2]) or "auto"
    if it.scale ~= nil then rule.scale = it.scale end
    if it.transform then rule.transform = it.transform end
    return rule
  end

  local function emit(rule)
    hl.monitor(rule)
  end

  local function label_of(d)
    return (placement[d.display] and placement[d.display].label) or d.label
  end

  -- Each tile guard is built whole before anything is sent: its desc: rule
  -- turns the left tile off too, so it only goes out with the left tile's
  -- own rule ready to follow. `own` marks what the active setup decided, so
  -- the check knows whose fault a difference is: the left tile's place and
  -- scale when the setup names the display, never the other tiles.
  local built = {}
  for _, g in ipairs(guards) do
    local d, p = g.display, placement[g.display.display]
    try("rules: " .. tostring(label_of(d)), function()
      local function item(mode)
        return {
          output = g.left, label = label_of(d), mode = mode, mode_text = mode_text(mode), loose = mode.loose,
          scale = tile_scale(d, mode, p and p.own), position = p and p.position, transform = p and p.transform,
          own = p ~= nil,
        }
      end
      local b = { g = g, final = item(g.target), off = {} }
      b.rule = rule_of(b.final)
      if g.pass1 then b.first = rule_of(item(g.pass1)) end
      for _, name in ipairs(g.others) do
        local it = { output = name, disabled = true, label = label_of(d) .. " (" .. name .. ")", own = false }
        b.off[#b.off + 1] = it
      end
      built[#built + 1] = b
    end)
  end

  -- 1. The guard's desc: rule first: it turns off every tile of the display,
  --    then connector rules after it win for their connector.
  for _, b in ipairs(built) do
    try("rules: " .. tostring(b.final.label), function()
      if b.g.display.description then emit({ output = "desc:" .. b.g.display.description, disabled = true }) end
      -- 2. Every tile but the left one, and any phantom, off.
      for _, it in ipairs(b.off) do
        emit(rule_of(it))
        items[#items + 1] = it
      end
    end)
  end
  -- 3. The active setup's other displays, each on its own: one that can't be
  --    built or sent costs only its own rule, and only a rule that went out
  --    is checked. Displays it doesn't name get no rule: Omarchy's catch-all
  --    looks after them.
  for _, x in ipairs(entries) do
    local d = x.d
    if d and not d.tiled and not (d.internal and mirrored) then
      try("rules: " .. tostring(x.e.label), function()
        local mode = x.mode
        local it = {
          output = d.output, label = x.e.label, internal = d.internal, position = x.position,
          scale = x.scale, transform = x.e.transform, own = true,
          mode_text = mode and mode_text(mode) or "preferred", mode = mode, preferred = mode == nil,
        }
        if d.internal and type(x.scale) == "number" then
          local p = preferred(d.modes)
          it.expect = p and snap(x.scale, p.w, p.h) or x.scale
        end
        emit(rule_of(it))
        items[#items + 1] = it
      end)
    end
  end
  -- 4. Each left tile, once, with its final mode, scale and position.
  for _, b in ipairs(built) do
    try("rules: " .. tostring(b.final.label), function()
      if b.first then
        -- Pass 2 comes even when the tile already runs the target mode:
        -- Hyprland skips a rule that changes nothing.
        emit(b.first)
        pass2.pending = true
        pass2.items[#pass2.items + 1] = b.rule
        for name in pairs(b.g.lit) do pass2.waiting[name] = true end
      else
        emit(b.rule)
      end
      items[#items + 1] = b.final
    end)
  end

  -- The primary display: the setup's, else its first connected one. The
  -- cursor starts there at login; after a change of setup, focus moves there.
  local primary
  for _, x in ipairs(entries) do
    if x.d and x.e.primary then primary = x.d.output end
  end
  for _, x in ipairs(entries) do
    if not primary and x.d then primary = x.d.output end
  end
  if primary then pcall(hl.config, { cursor = { default_monitor = primary } }) end

  -- Keyboards: a setup can give a keyboard another keymap while it's on.
  try("keyboards", function()
    if lib.keyboards and active then
      for _, k in ipairs(active.keyboards) do
        if not lib.keyboards.override(k.id, k.keymap) then
          problems[#problems + 1] = active.name .. ": keyboard " .. k.id .. " can't switch to " .. k.keymap
        end
      end
    end
    local list = json.array()
    for _, k in ipairs(lib.keyboards and lib.keyboards.list or {}) do
      local devices = json.array()
      for _, n in ipairs(k.devices) do devices[#devices + 1] = n end
      list[#list + 1] = { id = k.id, label = k.label, keymap = k.keymap, own = k.own, override = k.override or json.null,
        connected = k.connected, devices = devices }
    end
    state.keyboards = list
  end)

  -- -------------------------------------------------------------- write it down
  local monitors = json.array()
  for _, it in ipairs(items) do
    if it.disabled then
      monitors[#monitors + 1] = { output = it.output, disabled = true }
    else
      monitors[#monitors + 1] = { output = it.output, mode = it.mode_text,
        position = it.position and json.array({ it.position[1], it.position[2] }) or nil,
        scale = it.scale, transform = it.transform }
    end
  end
  state.requested = { hash = fnv1a(json.encode(monitors)), monitors = monitors }
  state.check = { load = state.load, state = #items > 0 and "pending" or "skipped", at = os.time(), detail = "" }

  local devices = { fingerprint = fp, displays = json.array(), thunderbolt = json.array(), usb = json.array() }
  for _, d in ipairs(displays) do
    local entry = { display = d.display, label = d.label, internal = d.internal, connectors = json.array(d.connectors),
      tiled = d.tiled, native = d.native and json.array({ d.native[1], d.native[2] }) or nil, description = d.description }
    if d.tiled then entry.left, entry.complete = d.left, d.complete end
    devices.displays[#devices.displays + 1] = entry
  end
  for _, t in ipairs(scan.thunderbolt) do
    if not t.host and t.unique_id ~= "" then
      devices.thunderbolt[#devices.thunderbolt + 1] = { thunderbolt = t.unique_id, label = t.label }
    end
  end
  for id in pairs(connected_usb) do devices.usb[#devices.usb + 1] = id end
  table.sort(devices.usb)
  state.devices = devices
  state.setups = state.setups or json.array()
  state.failed = state.failed or json.array()
  state.keyboards = state.keyboards or json.array()
  state.reason = state.reason or "none"
  try("state", write_state)
  lib.setups = { state = state, active = active }

  -- -------------------------------------------------------------- reloading
  -- Omarchy pauses reloads around package updates
  -- (omarchy-hyprland-reload-guard), marking it with a file per instance.
  local function paused()
    local sig = os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
    if sig and sig:match("^[%w_%.%-]+$") then
      return lib.exists("/run/omarchy/hyprland-reload-guard/" .. sig)
    end
    local ok, v = pcall(hl.get_config, "misc.disable_autoreload")
    return ok and (v == true or v == 1)
  end

  -- Never a loop: besides the rules for each kind of reload, at most three
  -- automatic reloads a minute. The count lives in the state file, the only
  -- thing a reload keeps, so there's no reload when it can't be written.
  local function reload(why)
    if paused() then return false end
    local now, r = os.time(), state.reloads
    if type(r) ~= "table" or type(r.at) ~= "number" or now - r.at > 60 then r = { at = now, count = 0 } end
    if (tonumber(r.count) or 0) >= 3 then return false end
    state.reloads = { at = r.at, count = (tonumber(r.count) or 0) + 1, why = why }
    if not write_state() then return false end
    hl.exec_cmd("hyprctl reload")
    return true
  end

  -- -------------------------------------------------------------- comparing
  -- What Omarchy's toggles decide: the laptop panel (lid, or off by hand),
  -- and the display the mirror toggle names; when the toggle file has no
  -- name, any display that's missing while mirrored.
  local function excused(it, now)
    if it.internal and (not now[it.output] or laptop_toggled) then return true end
    if mirrored and not it.disabled then
      if mirror_output then return it.output == mirror_output end
      return not now[it.output]
    end
    return false
  end

  -- A display Bento asked to light that Hyprland lists at 0×0: not probed
  -- yet (Omarchy's modeless watcher reloads until it is), so there's nothing
  -- to judge.
  local function unsettled(now)
    for _, it in ipairs(items) do
      local m = now[it.output]
      if m and not it.disabled and not excused(it, now) and (m.w <= 0 or m.h <= 0) then return it.label end
    end
    return nil
  end

  -- What differs between the rules and what Hyprland shows, in words, and
  -- whether any of it is the active setup's doing.
  local function differences(now)
    local out, mine = {}, false
    for _, it in ipairs(items) do
      local m = now[it.output]
      local before = #out
      if excused(it, now) then
        -- Omarchy's toggles decide these.
      elseif it.disabled then
        if m then out[#out + 1] = it.label .. ": asked to be off, but it's on" end
      elseif not m then
        out[#out + 1] = it.label .. ": asked for " .. (it.mode and string.format("%d×%d", it.mode.w, it.mode.h) or "it") .. ", but it's off"
      else
        if it.mode then
          local tolerance = it.loose and 1 or 0.05
          if m.w ~= it.mode.w or m.h ~= it.mode.h then
            out[#out + 1] = string.format("%s: asked for %d×%d, got %d×%d", it.label, it.mode.w, it.mode.h, m.w, m.h)
          elseif math.abs(m.refresh - it.mode.refresh) > tolerance then
            out[#out + 1] = string.format("%s: asked for %s Hz, got %s Hz", it.label, num_text(it.mode.refresh), num_text(m.refresh))
          end
        elseif it.preferred then
          local any, hit = false, false
          for _, md in ipairs(m.modes) do
            if md.preferred then
              any = true
              if md.w == m.w and md.h == m.h then hit = true end
            end
          end
          if any and not hit then
            local p = preferred(m.modes)
            out[#out + 1] = string.format("%s: asked for %d×%d, got %d×%d", it.label, p.w, p.h, m.w, m.h)
          end
        end
        if #m.modes > 0 then
          local listed = false
          for _, md in ipairs(m.modes) do
            if md.w == m.w and md.h == m.h and math.abs(md.refresh - m.refresh) <= 0.05 then listed = true end
          end
          if not listed then
            out[#out + 1] = string.format("%s: runs %d×%d, which it doesn't list", it.label, m.w, m.h)
          end
        end
        local want = it.expect or it.scale
        if type(want) == "number" and math.abs(m.scale - want) > 0.001 then
          out[#out + 1] = it.label .. ": asked for scale " .. num_text(want) .. ", got " .. num_text(m.scale)
        end
        if it.position and (m.x ~= it.position[1] or m.y ~= it.position[2]) then
          out[#out + 1] = string.format("%s: asked for %d, %d, got %d, %d", it.label, it.position[1], it.position[2], m.x, m.y)
        end
        if it.transform and m.transform ~= it.transform then
          out[#out + 1] = string.format("%s: asked for rotation %d, got %d", it.label, it.transform, m.transform)
        end
      end
      if #out > before and it.own then mine = true end
    end
    return out, mine
  end

  local function signature(now)
    local names, parts = {}, {}
    for name in pairs(now) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
      local m = now[name]
      parts[#parts + 1] = string.format("%s %dx%d@%.2f %d,%d %.3f %d", name, m.w, m.h, m.refresh, m.x, m.y, m.scale, m.transform)
    end
    return table.concat(parts, ";")
  end

  -- -------------------------------------------------------------- pass 2
  local check = { tries = 0, last = nil, done = false }
  local function second_pass()
    if not pass2.pending then return end
    pass2.pending = false
    for _, rule in ipairs(pass2.items) do emit(rule) end
    check.last = nil
  end
  if pass2.pending then after(500, second_pass) end

  -- -------------------------------------------------------------- the check
  local changed = active ~= nil and prev.active ~= active.id
  local function setup_labels()
    local out = {}
    for _, x in ipairs(entries) do
      if x.d then out[#out + 1] = x.e.label end
    end
    return table.concat(out, ", ")
  end

  -- A failure is the active setup's when it decided something that came out
  -- wrong. Then it's marked failed here and Bento tries again without it,
  -- once; after that it stops choosing until the devices change. Anything
  -- else is the tile guard's or Hyprland's: no setup would do better, so it's
  -- only said, once for these devices and this difference, and never
  -- reloads.
  local open_setups = { lib.repo .. "/bin/bento", "preferences", "setups" }
  local function finish(diffs, empty, mine, waiting)
    local now_t = os.time()
    if empty or waiting then
      state.check = { load = state.load, state = "skipped", at = now_t,
        detail = empty and "Hyprland showed no monitors" or (waiting .. " has no mode yet") }
      write_state()
      return
    end
    if #diffs == 0 then
      state.check = { load = state.load, state = "passed", at = now_t, detail = "" }
      state.retry = nil
      state.guard_notice = nil
      write_state()
      if changed then
        local labels = setup_labels()
        lib.notify("low", active.name .. (labels ~= "" and (" · " .. labels) or ""), nil, open_setups)
        if primary then pcall(hl.dispatch, hl.dsp.focus({ monitor = primary })) end
      end
    else
      local detail = table.concat(diffs, "; ")
      local blame = active ~= nil and mine
      state.check = { load = state.load, state = "failed", at = now_t, detail = detail }
      -- Kept through later loads: the retry below starts a new load at once,
      -- and bin/bento-setup must still see that this one failed.
      state.last_failure = { load = state.load, id = blame and active.id or json.null, detail = detail, at = now_t }
      if blame then
        local failed = state.failed
        failed[#failed + 1] = { id = active.id, fingerprint = fp, config = config }
        while #failed > 50 do table.remove(failed, 1) end
        if reason == "hand" then state.hand = nil end
        for _, s in ipairs(state.setups) do
          if s.id == active.id then s.failed, s.note = true, "Failed its check" end
        end
        if (reason == "fallback" and failed_before) or state.retry == fp then
          state.stopped = fp
          write_state()
          lib.notify("critical", active.name .. " didn't work",
            detail .. ". Bento won't try another setup until something is plugged in or out.", open_setups)
        else
          state.retry = fp
          local again = reload("check failed")
          if not again then write_state() end
          lib.notify("critical", active.name .. " didn't work",
            detail .. (again and ". Trying again without it." or ". The next reload tries without it."), open_setups)
        end
      else
        -- Never a reload, and the same thing isn't said twice: Omarchy's
        -- modeless watcher can reload again and again.
        local key = fp .. "\n" .. detail
        local tell = state.guard_notice ~= key
        state.guard_notice = key
        write_state()
        if tell then lib.notify("critical", "A display didn't come out right", detail, open_setups) end
      end
    end
    if back_to_auto then lib.notify("low", "Back to automatic: " .. back_to_auto) end
  end

  -- At 300 ms, then every 250 ms until two reads in a row agree, for at most
  -- 3.3 s. A match ends it at once; a mismatch only after 800 ms.
  local function check_step()
    if check.done then return end
    check.tries = check.tries + 1
    local now = monitors_now()
    local diffs, mine = differences(now)
    local sig = signature(now)
    local empty = next(now) == nil
    local stable = not empty and not pass2.pending and sig == check.last
    check.last = (not pass2.pending) and sig or nil
    if (stable and (#diffs == 0 or check.tries >= 3)) or check.tries >= 13 then
      check.done = true
      return finish(diffs, empty, mine, unsettled(now))
    end
    after(250, check_step)
  end
  if #items > 0 then
    after(300, check_step)
  elseif back_to_auto then
    lib.notify("low", "Back to automatic: " .. back_to_auto)
  end

  -- -------------------------------------------------------------- settling
  -- After displays come and go, look again: if the devices changed, reload
  -- so the right setup applies; if they didn't but the layout drifted from
  -- what was asked, reload once.
  local function learn(list, now)
    local learned = false
    for _, d in ipairs(list) do
      local m = now[d.output]
      if m and not d.internal and m.description ~= "" and cache[d.display] ~= m.description then
        cache[d.display], learned = m.description, true
      end
    end
    return learned
  end

  local function rescan()
    local now = monitors_now()
    local scan2 = sysfs.scan()
    local list = find_displays(scan2, now, cache)
    local learned = learn(list, now)
    local tb, usb = {}, {}
    for _, t in ipairs(scan2.thunderbolt) do
      if t.unique_id ~= "" then tb[t.unique_id] = true end
    end
    for _, u in ipairs(scan2.usb) do usb[u.id] = true end
    -- A tiled display that was unprobed, or a phantom that came or went,
    -- changes the shape but not the devices.
    if fingerprint(list, tb, usb) ~= fp or tiled_shape(list) ~= shape then
      if learned then write_state() end
      reload("devices changed")
      return
    end
    if state.check.state == "passed" and state.drift ~= fp and not unsettled(now) then
      local diffs = differences(now)
      if #diffs > 0 then
        state.drift = fp
        write_state()
        reload("drift: " .. diffs[1])
        return
      end
    end
    if learned then write_state() end
  end

  local settle = { gen = 0, burst = 0, waiting = false }
  local function settled()
    settle.waiting = false
    rescan()
  end
  -- 1.5 s after the last monitor event, or 8 s after the first.
  local function arm()
    settle.gen = settle.gen + 1
    local gen = settle.gen
    if not settle.waiting then
      settle.waiting = true
      settle.burst = settle.burst + 1
      local burst = settle.burst
      after(8000, function()
        if settle.waiting and settle.burst == burst then settled() end
      end)
    end
    after(1500, function()
      if settle.waiting and settle.gen == gen then settled() end
    end)
  end
  after(2000, function()
    if not settle.waiting then rescan() end
  end)

  -- -------------------------------------------------------------- monitor events
  -- A tiled display that turns up after the load: guard it at once, before
  -- its tiles fight over the cable; the settle then reloads properly.
  local function runtime_guard(m)
    local c = sysfs.connector(m.name)
    if not c or c.status ~= "connected" then return end
    local description = m.description or ""
    if c.edid and description ~= "" then cache[c.edid.key] = description end
    local t = c.edid and c.edid.tile
    if not t then
      -- Maybe a tiled display's phantom (see find_displays): off, by name
      -- only, when the display is one the guard drives.
      local conns = sysfs.connectors()
      for _, d in ipairs(find_displays({ drm = conns, tiles = sysfs.edid.tiled_groups(conns) }, monitors_now(), cache)) do
        if d.tiled and is_phantom(d, m.name) and single_stream(d.modes, d.native[1], d.native[2]) then
          emit({ output = m.name, disabled = true })
        end
      end
      return
    end
    local modes = {}
    for _, am in ipairs(type(m.available_modes) == "table" and m.available_modes or {}) do
      local w, h = int(am.width) or 0, int(am.height) or 0
      if w > 0 and h > 0 then modes[#modes + 1] = { w = w, h = h, refresh = tonumber(am.refresh_rate) or 0 } end
    end
    if #modes == 0 then
      for _, md in ipairs(c.modes or {}) do
        if not md.interlaced and md.w > 0 and md.h > 0 then modes[#modes + 1] = { w = md.w, h = md.h, refresh = 60 } end
      end
    end
    local full_w, full_h, mw, mh = t.cols * t.w, t.rows * t.h, 0, 0
    for _, md in ipairs(modes) do mw, mh = math.max(mw, md.w), math.max(mh, md.h) end
    if mw >= full_w and mh >= full_h then return end
    if t.h_loc ~= 0 or t.v_loc ~= 0 then
      -- Another tile that can't show the panel, modes or none (0×0 right
      -- after a replug): off. Never a desc: rule here: it would turn off a
      -- lit left tile too.
      emit({ output = m.name, disabled = true })
      return
    end
    if mw == 0 then return end -- the left tile, not probed yet: the settle reload plans it
    local mode = single_stream(modes, full_w, full_h)
    if not mode then return end
    local p = placement[c.edid.key]
    if description ~= "" then emit({ output = "desc:" .. description, disabled = true }) end
    local rule = { output = m.name, mode = mode_text(mode),
      scale = tile_scale({ display = c.edid.key, native = { full_w, full_h } }, mode, p and p.own),
      position = p and p.position and string.format("%dx%d", p.position[1], p.position[2]) or "auto" }
    if p and p.transform then rule.transform = p.transform end
    emit(rule)
  end

  hl.on("monitor.added", function(m)
    safe(function()
      arm()
      local name = m and m.name
      if name and not covered[name] then
        covered[name] = true
        runtime_guard(m)
      end
    end)
  end)

  hl.on("monitor.removed", function(m)
    safe(function()
      arm()
      local name = m and m.name
      -- Whatever comes back later is looked at afresh.
      if name then covered[name] = nil end
      if pass2.pending and name and pass2.waiting[name] then
        pass2.waiting[name] = nil
        if next(pass2.waiting) == nil then second_pass() end
      end
    end)
  end)

  loading = false
  if #errors > 0 then error(table.concat(errors, "; "), 0) end
end
