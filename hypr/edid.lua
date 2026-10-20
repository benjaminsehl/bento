-- edid.lua: pure EDID / DisplayID parsing for Bento Setups.
-- No I/O, no globals. Lua 5.4/5.5 (uses native integer bitwise operators).
--
-- Mirrors, where noted, Linux v7.2 drivers/gpu/drm/drm_edid.c and
-- drm_displayid.c (what the kernel puts in the connector TILE property) and
-- aquamarine 0.15.0 src/backend/drm/DRM.cpp (what Hyprland hides).

local M = {}

local byte, sub, format, concat = string.byte, string.sub, string.format, table.concat

local HEADER = "\0\255\255\255\255\255\255\0"
local DESCRIPTORS = { 54, 72, 90, 108 }

-- 0-based byte access, so offsets read like the EDID spec.
local function u8(s, i)
  return byte(s, i + 1)
end

local function u16le(s, i)
  local a, b = byte(s, i + 1, i + 2)
  return a | (b << 8)
end

local function u32le(s, i)
  local a, b, c, d = byte(s, i + 1, i + 4)
  return a | (b << 8) | (c << 16) | (d << 24)
end

local function sum8(s, from, to) -- inclusive, 0-based
  local n = 0
  for i = from + 1, to + 1 do
    n = n + byte(s, i)
  end
  return n % 256
end

-- Display descriptor text (0xFC name, 0xFF serial, 0xFE text): 13 bytes at
-- +5, ended by 0x0A, padded with spaces. Some sinks pad with NULs instead.
-- Returns nil when empty.
local function descriptor_text(s, off)
  local t = sub(s, off + 6, off + 18)
  local nl = t:find("\n", 1, true)
  if nl then
    t = sub(t, 1, nl - 1)
  end
  t = t:gsub("^[ \0]+", ""):gsub("[ \0]+$", "")
  if t == "" then
    return nil
  end
  return t
end

-- Three printable ASCII bytes stay as text; anything else is hex-escaped so
-- the group id stays a safe, stable string.
local function ascii3(s, off)
  local out = {}
  for i = off, off + 2 do
    local c = u8(s, i)
    if c > 0x20 and c < 0x7F and c ~= 0x3A then
      out[#out + 1] = string.char(c)
    else
      out[#out + 1] = format("\\x%02X", c)
    end
  end
  return concat(out)
end

-- DisplayID tiled display topology payload (22 bytes from p).
-- Bit layout = drm_parse_tiled_block (drm_edid.c v7.2 :7586-7603).
local function decode_tile(s, p)
  local caps = u8(s, p)
  local t0, t1, t2 = u8(s, p + 1), u8(s, p + 2), u8(s, p + 3)
  local w, h = u16le(s, p + 4), u16le(s, p + 6)
  local vendor, product, serial = ascii3(s, p + 13), u16le(s, p + 16), u32le(s, p + 18)
  return {
    cols = ((t0 >> 4) | ((t2 >> 2) & 0x30)) + 1,
    rows = ((t0 & 0x0F) | (t2 & 0x30)) + 1,
    h_loc = (t1 >> 4) | (((t2 >> 2) & 0x03) << 4),
    v_loc = (t1 & 0x0F) | ((t2 & 0x03) << 4),
    w = w + 1,
    h = h + 1,
    caps = caps,
    single_enclosure = (caps & 0x80) ~= 0, -- kernel: tile_is_single_monitor
    group = format("%s:%04X:%08X", vendor, product, serial),
  }
end

-- Walk DisplayID sections the way the kernel's displayid iterator does
-- (drm_displayid.c v7.2 :53-184):
--   * extension blocks tagged 0x70, in order;
--   * section = rev, bytes, prod, ext_count at +1..+4, then data blocks,
--     then one checksum byte; 4 + bytes + 1 must fit in 126 bytes and the
--     section must sum to 0, otherwise iteration STOPS (later sections are
--     ignored too);
--   * the structure version comes from the first section only;
--   * a data block is used only if its header and payload fit.
-- Tile tag = 0x12 when version < 0x20, 0x28 when version == 0x20
-- (drm_edid.c :7631-7639); payload must be >= 22 bytes (:7579). If several
-- tile blocks exist the last one wins, as in the kernel.
local function displayid_tile(s, nblocks)
  local version, tile
  for k = 1, nblocks - 1 do
    local off = 128 * k
    if u8(s, off) == 0x70 then
      local bytes = u8(s, off + 2)
      local seclen = 4 + bytes + 1
      if seclen > 126 or sum8(s, off + 1, off + seclen) ~= 0 then
        break
      end
      if version == nil then
        version = u8(s, off + 1)
      end
      local idx, last = 5, 5 + bytes
      while idx + 3 <= last do
        local tag, n = u8(s, off + idx), u8(s, off + idx + 2)
        if idx + 3 + n > last then
          break
        end
        if n >= 22 and ((version < 0x20 and tag == 0x12) or (version == 0x20 and tag == 0x28)) then
          tile = decode_tile(s, off + idx + 3)
          tile.block = k
          tile.displayid = version
        end
        idx = idx + 3 + n
      end
    end
  end
  return tile, version
end

-- parse(bytes) -> table, or nil and a reason.
function M.parse(s)
  if type(s) ~= "string" or #s < 128 then
    return nil, "short"
  end
  if sub(s, 1, 8) ~= HEADER then
    return nil, "header"
  end

  local v = (u8(s, 8) << 8) | u8(s, 9)
  -- Same as libdisplay-info: '@' + 5-bit value, so 1..26 = A..Z.
  local pnp = string.char(64 + ((v >> 10) & 31), 64 + ((v >> 5) & 31), 64 + (v & 31))
  local product = u16le(s, 10)
  local serial = u32le(s, 12)

  local name, serial_text
  for _, off in ipairs(DESCRIPTORS) do
    -- Display descriptor: pixel clock 0 and byte 2 = 0; tag at +3.
    if u8(s, off) == 0 and u8(s, off + 1) == 0 and u8(s, off + 2) == 0 then
      local tag = u8(s, off + 3)
      if tag == 0xFC and name == nil then
        name = descriptor_text(s, off)
      elseif tag == 0xFF and serial_text == nil then
        serial_text = descriptor_text(s, off)
      end
    end
  end

  local id
  if serial_text then
    id = serial_text
  elseif serial ~= 0 then
    id = format("%08X", serial)
  else
    id = "0"
  end

  local nblocks = #s // 128
  local tile = displayid_tile(s, nblocks)

  return {
    pnp = pnp,
    product = product,
    serial = serial,
    serial_text = serial_text,
    name = name,
    key = format("%s:%04X:%s", pnp, product, id),
    tile = tile,
    extensions = u8(s, 126), -- as declared; may exceed what is present
    blocks = nblocks, -- complete 128-byte blocks present
    checksum_ok = sum8(s, 0, 127) == 0,
  }
end

-- modes(text): sysfs "modes" file (drm_sysfs.c modes_show, one
-- drm_mode_set_name() per line: "%dx%d" plus "i" if interlaced).
-- Duplicates (same size, other refresh) are dropped; order is kept.
function M.modes(text)
  local list, seen = {}, {}
  for line in (text or ""):gmatch("[^\n]+") do
    local w, h, i = line:match("^%s*(%d+)x(%d+)(i?)%s*$")
    if w then
      local k = w .. "x" .. h .. i
      if not seen[k] then
        seen[k] = true
        list[#list + 1] = { w = tonumber(w), h = tonumber(h), interlaced = i == "i" }
      end
    end
  end
  return list
end

-- Largest width and largest height, taken separately and including
-- interlaced modes, as aquamarine's maxMode (DRM.cpp 0.15.0 :1294-1298).
function M.max_mode(list)
  local mw, mh = 0, 0
  for _, m in ipairs(list or {}) do
    if m.w > mw then mw = m.w end
    if m.h > mh then mh = m.h end
  end
  return mw, mh
end

-- "card0-DP-1" -> "DP-1" (Hyprland/aquamarine output name).
function M.output_name(sysfs_name)
  return (sysfs_name:gsub("^card%d+%-", ""))
end

local function natural_less(a, b)
  local pa, na = a:match("^(.-)(%d*)$")
  local pb, nb = b:match("^(.-)(%d*)$")
  if pa ~= pb then
    return pa < pb
  end
  return (tonumber(na) or -1) < (tonumber(nb) or -1)
end

-- tiled_groups(connectors)
-- connectors: list of { name, status, edid = parse() result, modes = modes()
-- result, connector_id = optional number }.
-- Returns a list of groups, one per physical display that carries a tile block:
--   { id, key, keys, group, cols, rows, w, h, full_w, full_h,
--     members = { {name, key, h_loc, v_loc, max_w, max_h}, ... } sorted by v_loc, h_loc,
--     left = name of the h_loc 0 / v_loc 0 member (else the lowest v_loc, then h_loc),
--     complete = every tile position is connected,
--     full = name of the connector that offers the whole panel, or nil,
--     hidden = names aquamarine marks tiling-redundant,
--     tiled = true when no member offers the whole panel,
--     modes_known = false when a member has an empty mode list }
--
-- Rule (aquamarine 0.15.0 markRedundantTiles, DRM.cpp :1158-1203): within a
-- group of connected tiles, full = cols*w x rows*h taken from the first
-- member; the first member whose max width >= full_w AND max height >=
-- full_h drives the whole panel and every other member is hidden. Groups
-- with one member are skipped by aquamarine (nothing hidden); here they are
-- still reported, with tiled = true when that one tile can't show the panel.
-- Members are visited in connector_id order (aquamarine's connector list),
-- falling back to natural name order.
--
-- Grouping is by the topology id first, as the kernel (and so aquamarine)
-- does. LG UltraFine tiles all carry topology serial 0x01010101, so two
-- UltraFines share one topology id. When a group has more members than tile
-- positions, two members claim one position, or members disagree about the
-- tile layout, it is split by EDID key. `key` is the left tile's key.
local function same_layout(a, b)
  return a.cols == b.cols and a.rows == b.rows and a.w == b.w and a.h == b.h
end

local function conflicts(list)
  local first, seen = list[1].edid.tile, {}
  if #list > first.cols * first.rows then return true end
  for _, c in ipairs(list) do
    local t = c.edid.tile
    if not same_layout(t, first) then return true end
    local pos = t.v_loc * 64 + t.h_loc
    if seen[pos] then return true end
    seen[pos] = true
  end
  return false
end

local function build_group(id, list)
  local t = list[1].edid.tile
  local g = {
    id = id,
    group = t.group,
    cols = t.cols,
    rows = t.rows,
    w = t.w,
    h = t.h,
    full_w = t.cols * t.w,
    full_h = t.rows * t.h,
    members = {},
    hidden = {},
    keys = {},
  }
  local seen_key = {}
  for _, c in ipairs(list) do
    local mw, mh = M.max_mode(c.modes)
    g.members[#g.members + 1] = {
      name = c.name,
      key = c.edid.key,
      h_loc = c.edid.tile.h_loc,
      v_loc = c.edid.tile.v_loc,
      max_w = mw,
      max_h = mh,
    }
    if not seen_key[c.edid.key] then
      seen_key[c.edid.key] = true
      g.keys[#g.keys + 1] = c.edid.key
    end
  end

  for _, m in ipairs(g.members) do
    if g.full == nil and m.max_w >= g.full_w and m.max_h >= g.full_h then
      g.full = m.name
    end
  end
  g.tiled = g.full == nil
  -- An empty mode list (connector not probed yet) makes max 0x0, which
  -- would read as "tiled" even for a Studio Display. Callers should not
  -- trust tiled until modes_known (or should use Hyprland's list).
  g.modes_known = true
  for _, m in ipairs(g.members) do
    if m.max_w == 0 or m.max_h == 0 then
      g.modes_known = false
    end
  end
  if g.full and #g.members > 1 then
    for _, m in ipairs(g.members) do
      if m.name ~= g.full then
        g.hidden[#g.hidden + 1] = m.name
      end
    end
  end
  table.sort(g.members, function(a, b)
    if a.v_loc ~= b.v_loc then
      return a.v_loc < b.v_loc
    end
    if a.h_loc ~= b.h_loc then
      return a.h_loc < b.h_loc
    end
    return natural_less(a.name, b.name)
  end)
  local pos = {}
  for _, m in ipairs(g.members) do
    pos[m.v_loc * 64 + m.h_loc] = true
  end
  g.left = g.members[1].name
  g.key = g.members[1].key
  local n = 0
  for _ in pairs(pos) do
    n = n + 1
  end
  g.complete = n == g.cols * g.rows
  return g
end

function M.tiled_groups(connectors)
  local list = {}
  for _, c in ipairs(connectors or {}) do
    if c.status == "connected" and c.edid and c.edid.tile then
      list[#list + 1] = c
    end
  end
  table.sort(list, function(a, b)
    if a.connector_id and b.connector_id and a.connector_id ~= b.connector_id then
      return a.connector_id < b.connector_id
    end
    return natural_less(a.name, b.name)
  end)

  -- By topology id, in connector order.
  local by_topology, topologies = {}, {}
  for _, c in ipairs(list) do
    local id = c.edid.tile.group
    if not by_topology[id] then
      by_topology[id] = {}
      topologies[#topologies + 1] = id
    end
    table.insert(by_topology[id], c)
  end

  local order = {}
  for _, id in ipairs(topologies) do
    local members = by_topology[id]
    if conflicts(members) then
      local by_key, keys = {}, {}
      for _, c in ipairs(members) do
        local k = c.edid.key
        if not by_key[k] then
          by_key[k] = {}
          keys[#keys + 1] = k
        end
        table.insert(by_key[k], c)
      end
      for _, k in ipairs(keys) do
        order[#order + 1] = build_group(#keys > 1 and (id .. "/" .. k) or id, by_key[k])
      end
    else
      order[#order + 1] = build_group(id, members)
    end
  end
  return order
end

return M
