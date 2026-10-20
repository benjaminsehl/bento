-- Bento's settings: defaults.json in the checkout, overridden by
-- ~/.config/bento/settings.json, which the Bento app writes. Both are nested
-- JSON objects with the same shape; unknown keys are ignored.

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
  local json = dofile(repo .. "/hypr/json.lua")
  local defaults = json.read(repo .. "/defaults.json")
  if type(defaults) ~= "table" then defaults = {} end
  local home = os.getenv("HOME")
  local path = (os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")) .. "/bento/settings.json"
  local parsed, err = json.read(path)
  local user = {}
  if type(parsed) == "table" then user = parsed
  elseif err and hl and hl.notification then
    pcall(hl.notification.create, { text = "bento settings: " .. tostring(err), duration = 8000 })
  end
  return merge(defaults, user)
end
