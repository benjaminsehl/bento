-- omac's settings: defaults.json in the checkout, overridden by
-- ~/.config/omac/settings.json, which the omac app writes. Both are nested
-- JSON objects with the same shape; unknown keys are ignored.

-- A small JSON decoder: Hyprland's Lua has none. Objects, arrays, strings,
-- numbers, true, false and null.
local function decode(text)
  local pos = 1
  local function fail(msg) error("omac settings: " .. msg .. " at character " .. pos) end
  local function skip() pos = text:find("[^ \t\r\n]", pos) or #text + 1 end
  local value

  local escapes = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
  local function str()
    local out = {}
    pos = pos + 1
    while true do
      local c = text:sub(pos, pos)
      if c == "" then fail("unterminated string") end
      if c == '"' then pos = pos + 1; return table.concat(out) end
      if c == "\\" then
        local e = text:sub(pos + 1, pos + 1)
        if e == "u" then
          local code = tonumber(text:sub(pos + 2, pos + 5), 16) or 63
          out[#out + 1] = utf8 and utf8.char(code) or "?"
          pos = pos + 6
        else
          out[#out + 1] = escapes[e] or e
          pos = pos + 2
        end
      else
        out[#out + 1] = c
        pos = pos + 1
      end
    end
  end

  function value()
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
        obj[k] = value(); skip()
        local d = text:sub(pos, pos); pos = pos + 1
        if d == "}" then return obj end
        if d ~= "," then fail("expected ',' or '}'") end
      end
    elseif c == "[" then
      local arr = {}
      pos = pos + 1; skip()
      if text:sub(pos, pos) == "]" then pos = pos + 1; return arr end
      while true do
        arr[#arr + 1] = value(); skip()
        local d = text:sub(pos, pos); pos = pos + 1
        if d == "]" then return arr end
        if d ~= "," then fail("expected ',' or ']'") end
      end
    elseif c == '"' then
      return str()
    elseif text:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif text:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif text:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
    else
      local num = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      if not num or num == "" then fail("unexpected '" .. c .. "'") end
      pos = pos + #num
      return tonumber(num)
    end
  end

  local ok, result = pcall(value)
  if not ok then return nil, result end
  return result
end

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return text
end

-- User values replace defaults key by key, but only where the default has
-- that key with the same type: a typo can't switch a feature into nonsense.
local function merge(defaults, user)
  local out = {}
  for k, v in pairs(defaults) do
    local u = nil
    if type(user) == "table" then u = user[k] end
    if type(v) == "table" then
      out[k] = merge(v, u)
    elseif u ~= nil and type(u) == type(v) then
      out[k] = u
    else
      out[k] = v
    end
  end
  return out
end

return function(repo)
  local defaults = decode(read(repo .. "/defaults.json") or "{}") or {}
  local home = os.getenv("HOME")
  local path = (os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")) .. "/omac/settings.json"
  local text = read(path)
  local user = {}
  if text then
    local parsed, err = decode(text)
    if parsed then user = parsed
    elseif hl and hl.notification then pcall(hl.notification, { text = err })
    end
  end
  return merge(defaults, user)
end
