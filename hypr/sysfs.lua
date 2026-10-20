-- What's plugged in, read from sysfs: displays (with their EDIDs), Thunderbolt
-- devices and USB devices. Read-only, no processes, no globals.
--
-- Standard Lua can't list a directory, so this opens fixed or derived paths
-- instead (connector names, Thunderbolt routes, USB ports). Only cheap
-- attributes are read: a connector's edid and modes take the kernel's DRM
-- lock, so only connected connectors are read further, and USB string
-- attributes (product, serial) can wait on the device, so they're never read.
-- The whole scan takes about a millisecond.

local here = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/[^/]+$") or "."
local E = dofile(here .. "/edid.lua")

local M = { edid = E }

-- Prefix for every path. Tests point it at a fixture tree.
M.root = ""

local open, format = io.open, string.format

local function slurp(path)
  local f = open(M.root .. path, "rb")
  if not f then return nil end
  local s = f:read("a") -- sysfs reports size 0 for edid; read to EOF
  f:close()
  return s
end

-- First line of a one-value attribute, trailing blanks removed. nil when the
-- file is missing or empty.
local function line(path)
  local f = open(M.root .. path, "rb")
  if not f then return nil end
  local s = f:read("l")
  f:close()
  if s == nil then return nil end
  s = s:gsub("%s+$", "")
  return s
end

local function exists(path)
  local f = open(M.root .. path, "rb")
  if f then f:close() end
  return f ~= nil
end

-- ---------------------------------------------------------------- displays
-- Connector type names, from the kernel's drm_connector_enum_list, most likely
-- first, with the highest id probed for each. Ids are shared by every card, so
-- a second card continues the numbering (card1-DP-4).
M.DRM_TYPES = {
  { "eDP", 4 }, { "DP", 16 }, { "HDMI-A", 8 }, { "HDMI-B", 2 }, { "DVI-D", 4 },
  { "DVI-I", 4 }, { "DVI-A", 2 }, { "VGA", 4 }, { "LVDS", 2 }, { "DSI", 4 },
  { "DPI", 2 }, { "USB", 4 }, { "Virtual", 4 }, { "SPI", 2 },
}
M.DRM_MAX_CARD = 7

local DRM = "/sys/class/drm/"

function M.internal(name)
  return name:match("^eDP%-") ~= nil or name:match("^LVDS%-") ~= nil or name:match("^DSI%-") ~= nil
end

-- One connector by its sysfs name ("card0-DP-1"). edid and modes are read
-- only when it's connected.
local function read_connector(sysname)
  local base = DRM .. sysname .. "/"
  local c = {
    sysfs = sysname,
    name = E.output_name(sysname),
    status = line(base .. "status") or "unknown",
    connector_id = tonumber(line(base .. "connector_id") or ""),
  }
  c.internal = M.internal(c.name)
  if c.status == "connected" then
    local raw = slurp(base .. "edid") or ""
    if #raw > 0 then c.edid = E.parse(raw) end
    c.modes = E.modes(slurp(base .. "modes"))
  end
  return c
end

function M.connectors()
  local list = {}
  for card = 0, M.DRM_MAX_CARD do
    if exists(format("%scard%d/dev", DRM, card)) then
      for _, t in ipairs(M.DRM_TYPES) do
        for id = 1, t[2] do
          local n = format("card%d-%s-%d", card, t[1], id)
          if exists(DRM .. n .. "/status") then list[#list + 1] = read_connector(n) end
        end
      end
    end
  end
  return list
end

-- One connector by Hyprland's name ("DP-1"), for monitor events.
function M.connector(name)
  if type(name) ~= "string" or not name:match("^[%w%-]+$") then return nil end
  for card = 0, M.DRM_MAX_CARD do
    local n = format("card%d-%s", card, name)
    if exists(DRM .. n .. "/status") then return read_connector(n) end
  end
  return nil
end

-- ---------------------------------------------------------------- Thunderbolt
-- Routers are named "<domain>-<route in hex>". A device behind port p of a
-- router at depth d has route parent | p << (8 * d). Hosts (route 0) are the
-- laptop's own controllers. unique_id, vendor_name and device_name are plain
-- fields in the kernel: no locks.
M.TB_MAX_DOMAIN = 3
M.TB_MAX_PORT = 63
M.TB_MAX_DEPTH = 6

local TB = "/sys/bus/thunderbolt/devices/"

local function tb_label(vendor, device)
  vendor, device = vendor or "", device or ""
  if device ~= "" and vendor ~= "" and device:sub(1, #vendor) ~= vendor then return vendor .. " " .. device end
  if device ~= "" then return device end
  if vendor ~= "" then return vendor end
  return "Thunderbolt device"
end

function M.thunderbolt()
  local list = {}
  for dom = 0, M.TB_MAX_DOMAIN do
    local root = format("%d-0", dom)
    if exists(TB .. root .. "/unique_id") then
      local queue, qi = { { root, 0, 0 } }, 1
      while queue[qi] do
        local name, route, depth = queue[qi][1], queue[qi][2], queue[qi][3]
        qi = qi + 1
        local d = TB .. name .. "/"
        list[#list + 1] = {
          name = name,
          host = route == 0,
          unique_id = (line(d .. "unique_id") or ""):lower(),
          label = tb_label(line(d .. "vendor_name"), line(d .. "device_name")),
        }
        if depth < M.TB_MAX_DEPTH then
          for p = 1, M.TB_MAX_PORT do
            local r = route | (p << (8 * depth))
            local n = format("%d-%x", dom, r)
            if exists(TB .. n .. "/unique_id") then queue[#queue + 1] = { n, r, depth + 1 } end
          end
        end
      end
    end
  end
  return list
end

-- ---------------------------------------------------------------- USB
-- Root hubs are "usb<bus>"; devices are "<bus>-<port>" and "<bus>-<port>.<port>"
-- below hubs. Every device has maxchild (0 unless it's a hub), so the tree can
-- be walked port by port.
M.USB_MAX_BUS = 32

local USB = "/sys/bus/usb/devices/"

local function usb_device(name)
  local d = USB .. name .. "/"
  local vid = line(d .. "idVendor")
  if not vid then return nil end
  return {
    name = name,
    id = (vid .. ":" .. (line(d .. "idProduct") or "")):lower(),
    maxchild = tonumber(line(d .. "maxchild") or "0") or 0,
  }
end

local function usb_walk(list, bus, dev, path)
  for p = 1, math.min(dev.maxchild, 64) do
    local devpath = path and (path .. "." .. p) or tostring(p)
    local child = usb_device(bus .. "-" .. devpath)
    if child then
      list[#list + 1] = child
      if child.maxchild > 0 and #devpath < 24 then usb_walk(list, bus, child, devpath) end
    end
  end
end

-- Every USB device except the root hubs.
function M.usb()
  local list = {}
  for bus = 1, M.USB_MAX_BUS do
    local root = usb_device("usb" .. bus)
    if root then usb_walk(list, bus, root, nil) end
  end
  return list
end

-- ---------------------------------------------------------------- all
function M.scan()
  local t0 = os.clock()
  local r = { drm = M.connectors(), thunderbolt = M.thunderbolt(), usb = M.usb() }
  r.tiles = E.tiled_groups(r.drm)
  r.cpu_ms = (os.clock() - t0) * 1000
  return r
end

return M
