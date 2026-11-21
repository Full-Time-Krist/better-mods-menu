local t = ...
local function load(data)
  local env = t.environment()
  local save = env.include("bmm.save")
  local encoded = t.json.encode(data)
  save.load({ HasData = function() return true end, LoadData = function() return encoded end,
    SaveData = function() end })
  return save
end
t.test("invalid saved field types are replaced with usable defaults", function()
  local save = load({ favs = false, profiles = 42, pendingConfig = "invalid", cfgCache = true,
    classic = "false", sort = {}, lang = {}, proc = "invalid" })
  for _, key in ipairs({ "favs", "profiles", "pendingConfig", "cfgCache" }) do t.eq(type(save.data[key]), "table") end
  t.eq(save.data.classic, false)
  t.eq(save.data.sort, 1)
  t.eq(save.data.lang, "auto")
  t.eq(save.processSnapshot({ example = true }).example, true)
end)
t.test("incomplete process snapshot is rebuilt", function()
  local start = os.time() - 1000 / 60
  local save = load({ proc = { start = start } })
  t.eq(save.processSnapshot({ example = true }).example, true)
end)
t.test("malformed profile slots do not break the profiles panel", function()
  local save = load({ profiles = { p1 = true, p2 = { set = "bad" }, p3 = { set = { example = true } } } })
  t.eq(save.data.profiles.p1, nil)
  t.eq(save.data.profiles.p2, nil)
  t.eq(save.data.profiles.p3.set.example, true)
end)
t.test("valid settings and same-process undo snapshot survive load", function()
  local start = os.time() - 1000 / 60
  local save = load({ favs = { example = true }, classic = true, lang = "ru", sort = 2,
    pendingConfig = { example = false }, proc = { start = start, states = { example = false } } })
  t.eq(save.data.favs.example, true)
  t.eq(save.data.classic, true)
  t.eq(save.data.pendingConfig.example, false)
  t.eq(save.processSnapshot({ example = true }).example, false)
end)
