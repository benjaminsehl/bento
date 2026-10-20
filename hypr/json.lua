-- JSON for Bento's Lua: Hyprland's Lua has none. Objects, arrays, strings,
-- numbers, true, false and null. Load it with dofile(repo .. "/hypr/json.lua").
local M = {}

-- null inside an array decodes to M.null, so the items after it keep their
-- places. null as an object's value leaves the key out. M.null encodes as null.
M.null = setmetatable({}, { __tostring = function() return "null" end, __name = "json.null" })

-- An empty Lua table can't say whether it's [] or {}. Tables made with
-- M.array() encode as arrays even when empty; decoded arrays get the mark too.
local array_mt = { __name = "json.array" }
function M.array(t) return setmetatable(t or {}, array_mt) end
function M.is_array(t) return getmetatable(t) == array_mt end

-- ---------------------------------------------------------------- decode
local escapes = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }

-- decode(text) -> value, or nil and a sentence saying what's wrong and where.
function M.decode(text)
  if type(text) ~= "string" then return nil, "no text" end
  local pos = 1
  local function fail(msg) error({ msg .. " at character " .. pos }, 0) end
  local function skip() pos = text:find("[^ \t\r\n]", pos) or #text + 1 end
  local value

  local function hex4(at)
    local h = text:sub(at, at + 3)
    if not h:match("^%x%x%x%x$") then fail("bad \\u escape") end
    return tonumber(h, 16)
  end

  local function str()
    local out = {}
    pos = pos + 1
    while true do
      -- Copy plain runs in one go; stop at a quote or a backslash.
      local stop = text:find('["\\]', pos)
      if not stop then fail("unterminated string") end
      if stop > pos then out[#out + 1] = text:sub(pos, stop - 1) end
      pos = stop
      if text:sub(pos, pos) == '"' then pos = pos + 1; return table.concat(out) end
      local e = text:sub(pos + 1, pos + 1)
      if e == "u" then
        local code = hex4(pos + 2)
        pos = pos + 6
        -- A UTF-16 surrogate pair: 😀 is one character.
        if code >= 0xD800 and code <= 0xDBFF and text:sub(pos, pos + 1) == "\\u" then
          local low = hex4(pos + 2)
          if low >= 0xDC00 and low <= 0xDFFF then
            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
            pos = pos + 6
          end
        end
        if code >= 0xD800 and code <= 0xDFFF then code = 0xFFFD end
        out[#out + 1] = utf8.char(code)
      elseif escapes[e] then
        out[#out + 1] = escapes[e]
        pos = pos + 2
      else
        fail("bad escape")
      end
    end
  end

  local function number()
    local s, e = text:find("^-?%d+", pos)
    if not s then fail("unexpected '" .. text:sub(pos, pos) .. "'") end
    if text:find("^-?0%d", s) then fail("bad number") end
    local _, e2 = text:find("^%.%d+", e + 1)
    if e2 then e = e2 end
    _, e2 = text:find("^[eE][-+]?%d+", e + 1)
    if e2 then e = e2 end
    local n = tonumber(text:sub(s, e))
    if not n then fail("bad number") end
    pos = e + 1
    return n
  end

  function value(depth)
    if depth > 200 then fail("nested too deeply") end
    skip()
    local c = text:sub(pos, pos)
    if c == "{" then
      local obj = {}
      pos = pos + 1; skip()
      if text:sub(pos, pos) == "}" then pos = pos + 1; return obj end
      while true do
        skip()
        if text:sub(pos, pos) ~= '"' then fail("expected a key") end
        local k = str(); skip()
        if text:sub(pos, pos) ~= ":" then fail("expected ':'") end
        pos = pos + 1
        local v = value(depth + 1)
        if v ~= M.null then obj[k] = v end
        skip()
        local d = text:sub(pos, pos); pos = pos + 1
        if d == "}" then return obj end
        if d ~= "," then pos = pos - 1; fail("expected ',' or '}'") end
      end
    elseif c == "[" then
      local arr = M.array()
      pos = pos + 1; skip()
      if text:sub(pos, pos) == "]" then pos = pos + 1; return arr end
      while true do
        arr[#arr + 1] = value(depth + 1); skip()
        local d = text:sub(pos, pos); pos = pos + 1
        if d == "]" then return arr end
        if d ~= "," then pos = pos - 1; fail("expected ',' or ']'") end
      end
    elseif c == '"' then
      return str()
    elseif text:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif text:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif text:sub(pos, pos + 3) == "null" then pos = pos + 4; return M.null
    elseif c == "" then fail("unexpected end")
    else
      return number()
    end
  end

  local ok, result = pcall(function()
    local v = value(0)
    skip()
    if pos <= #text then fail("unexpected text after the end") end
    return v
  end)
  if not ok then
    if type(result) == "table" then return nil, result[1] end
    return nil, tostring(result)
  end
  if result == M.null then return nil, "null" end
  return result
end

-- ---------------------------------------------------------------- encode
local function quote(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    if c == "\n" then return "\\n" end
    if c == "\t" then return "\\t" end
    if c == "\r" then return "\\r" end
    if c == "\b" then return "\\b" end
    if c == "\f" then return "\\f" end
    return string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function num(n)
  if n ~= n or n == math.huge or n == -math.huge then return "null" end
  if math.type(n) == "integer" then return tostring(n) end
  local i = math.tointeger(n)
  if i then return tostring(i) end
  return string.format("%.14g", n)
end

-- A table is an array when it's marked, or when its keys are exactly 1..n.
local function is_list(t)
  if getmetatable(t) == array_mt then return true end
  local n = #t
  if n == 0 then return false end
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count == n
end

-- encode(value, indent) -> text. indent is a number of spaces per level, or
-- nil for one line. Object keys come out sorted, so the same table always
-- gives the same text.
function M.encode(value, indent)
  local out = {}
  local function put(s) out[#out + 1] = s end
  local function newline(level)
    if indent then put("\n" .. string.rep(" ", indent * level)) end
  end
  local colon = indent and ": " or ":"

  local function enc(v, level, seen)
    local t = type(v)
    if v == nil or v == M.null then put("null")
    elseif t == "boolean" then put(tostring(v))
    elseif t == "number" then put(num(v))
    elseif t == "string" then put(quote(v))
    elseif t == "table" then
      if seen[v] then error("json: a table contains itself") end
      seen[v] = true
      if is_list(v) then
        if #v == 0 then put("[]") else
          put("[")
          for i = 1, #v do
            if i > 1 then put(",") end
            newline(level + 1)
            enc(v[i], level + 1, seen)
          end
          newline(level)
          put("]")
        end
      else
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        if #keys == 0 then put("{}") else
          put("{")
          for i, k in ipairs(keys) do
            if i > 1 then put(",") end
            newline(level + 1)
            local item = v[k]
            if item == nil then item = v[tonumber(k)] end
            put(quote(k) .. colon)
            enc(item, level + 1, seen)
          end
          newline(level)
          put("}")
        end
      end
      seen[v] = nil
    else
      put("null")
    end
  end

  enc(value, 0, {})
  return table.concat(out)
end

-- ---------------------------------------------------------------- files
-- read(path) -> value, err, text. A missing file gives nil, nil, nil.
function M.read(path)
  local f = io.open(path, "r")
  if not f then return nil, nil, nil end
  local text = f:read("a")
  f:close()
  if not text then return nil, "unreadable", nil end
  local value, err = M.decode(text)
  return value, err, text
end

-- Write next to the file, then rename over it, so readers never see half a
-- file. Returns true, or nil and the reason. A full disk often shows only
-- when the buffered text is flushed at close; then the old file stays.
function M.write_atomic(path, text)
  local tmp = path .. ".tmp"
  local f, err = io.open(tmp, "w")
  if not f then return nil, err end
  local ok, werr = f:write(text)
  local closed, cerr = f:close()
  if not ok or not closed then os.remove(tmp); return nil, werr or cerr end
  local renamed, rerr = os.rename(tmp, path)
  if not renamed then os.remove(tmp); return nil, rerr end
  return true
end

return M
