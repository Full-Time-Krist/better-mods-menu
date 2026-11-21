-- Run from the repository root: lua tests/run.lua
-- Only Isaac's API is substituted; the model, settings adapters and input logic
-- run from the production files. No game saves or disable.it files are touched.
local scripts = os.getenv("ISAAC_SCRIPTS") or (os.getenv("HOME") ..
  "/.local/share/Steam/steamapps/common/The Binding of Isaac Rebirth/resources/scripts")
package.path = package.path .. ";" .. scripts .. "/?.lua"
local json = require("json")
local total, failures = 0, 0
local function eq(got, want)
  assert(got == want, ("expected %s, got %s"):format(tostring(want), tostring(got)))
end
local function test(name, fn)
  total = total + 1
  local ok, err = pcall(fn)
  if ok then print("PASS " .. name) else
    failures = failures + 1
    print("FAIL " .. name .. ": " .. tostring(err))
  end
end
local function environment()
  local env = setmetatable({}, { __index = _G })
  env._G = env
  env.Isaac = { DebugString = function() end, GetFrameCount = function() return 1000 end }
  env.include = function(name) return assert(loadfile(name:gsub("%.", "/") .. ".lua", "t", env))() end
  return env
end
local function configFixture(options, pending, menus)
  local env = environment()
  env.ModConfigMenu = { OptionType = { SCROLL = 1, BOOLEAN = 2, NUMBER = 3,
    KEYBIND_KEYBOARD = 4, KEYBIND_CONTROLLER = 5, TEXT = 6, TITLE = 7, SPACE = 8 },
    MenuData = { { Name = "Example", Subcategories = { { Name = "Main", Options = options or {} } } } } }
  env.DeadSeaScrollsMenu = { Menus = menus or {} }
  local save = { data = { pendingConfig = pending or {}, cfgCache = {} }, write = function() end }
  local cfg = env.include("bmm.config")
  cfg.init({ mods = {} }, save, { T = function(k) return k end })
  return cfg, save, env
end
local ID = "mcm|Example|Main|1"
test("commit retains a setting whose mod is unavailable", function()
  local cfg, save = configFixture({}, { [ID] = false })
  cfg.commit()
  eq(save.data.pendingConfig[ID], false)
end)
test("commit retains a setting when OnChange fails", function()
  local cfg, save = configFixture({ { Type = 2, CurrentSetting = true,
    OnChange = function() error("config not loaded") end } }, { [ID] = false })
  cfg.commit()
  eq(save.data.pendingConfig[ID], false)
end)
test("successful commit applies false and removes only that setting", function()
  local value = true
  local cfg, save = configFixture({ { Type = 2, CurrentSetting = function() return value end,
    OnChange = function(v) value = v end } }, { [ID] = false, missing = 9 })
  cfg.commit()
  eq(value, false)
  eq(save.data.pendingConfig[ID], nil)
  eq(save.data.pendingConfig.missing, 9)
end)
test("number with only a minimum cannot go below it", function()
  local cfg = configFixture({ { Type = 3, Display = "Amount", CurrentSetting = 0, Minimum = 0 } })
  local row = cfg.entries()[1].open().build()[1]
  cfg.step(row, -1)
  eq(cfg.value(row), 0)
end)
test("number with only a maximum cannot go above it", function()
  local cfg = configFixture({ { Type = 3, Display = "Amount", CurrentSetting = 10, Maximum = 10 } })
  local row = cfg.entries()[1].open().build()[1]
  cfg.step(row, 1)
  eq(cfg.value(row), 10)
end)
test("bounded numbers wrap or clamp according to MCM", function()
  for _, noLoop in ipairs({ false, true }) do
    local cfg = configFixture({ { Type = 3, CurrentSetting = 10, Minimum = 0,
      Maximum = 10, NoLoopFromMaxMin = noLoop } })
    local row = cfg.entries()[1].open().build()[1]
    cfg.step(row, 1)
    eq(cfg.value(row), noLoop and 10 or 0)
  end
end)
local function dssFixture(failClose)
  local stored, unrelated = 1, 42
  local tbl = { Name = "Example DSS", DirectoryKey = { Main = "main", Settings = {} } }
  tbl.Directory = { main = { buttons = {
    { str = "Choice", variable = "choice", setting = 1, choices = { "One", "Two" },
      load = function() return stored end, store = function(v) stored = v end },
    { str = "Counter", variable = "counter", setting = 42,
      store = function() unrelated = 0 end },
  } } }
  local directory = tbl.Directory
  tbl.DirectoryKey.Item = directory.main
  tbl.Close = function(t)
    for _, item in pairs(t.Directory) do
      for _, btn in ipairs(item.buttons) do if btn.store then btn.store(btn.setting) end end
    end
    if failClose then error("save failed") end
  end
  local id = "dss|Example DSS|main|choice"
  local cfg, save = configFixture({}, { [id] = 2 }, { [tbl.Name] = tbl })
  return cfg, save, tbl, directory, id, function() return stored, unrelated end
end
test("DSS save failure retains the queued change and restores the directory", function()
  local cfg, save, tbl, directory, id = dssFixture(true)
  cfg.commit()
  eq(tbl.Directory, directory)
  eq(tbl.DirectoryKey.Item, directory.main)
  eq(save.data.pendingConfig[id], 2)
end)
test("DSS commit stores only changed buttons", function()
  local cfg, save, tbl, directory, id, values = dssFixture(false)
  cfg.commit()
  local stored, unrelated = values()
  eq(stored, 2)
  eq(unrelated, 42)
  eq(save.data.pendingConfig[id], nil)
  eq(tbl.Directory, directory)
end)
test("DSS displayif returning nil hides a conditional button", function()
  local menu = { Name = "Conditional", DirectoryKey = { Main = "main", Settings = {} },
    Directory = { main = { buttons = {
      { str = "Hidden", displayif = function() return nil end },
      { str = "Visible" },
    } } } }
  local cfg = configFixture({}, {}, { Conditional = menu })
  local rows = cfg.entries()[2].open().build()
  eq(#rows, 1)
  eq(rows[1].label(), "Visible")
end)
test("DSS empty choices are not editable", function()
  local menu = { Name = "Empty", DirectoryKey = { Main = "main", Settings = {} },
    Directory = { main = { buttons = { { str = "Unavailable", setting = 1, choices = {} } } } } }
  local cfg = configFixture({}, {}, { Empty = menu })
  local row = cfg.entries()[2].open().build()[1]
  eq(row.kind, "text")
end)

-- More suites share the runner without adding test-only hooks to production.
local context = { test = test, eq = eq, environment = environment, json = json }
for _, path in ipairs({ "tests/menu.lua", "tests/save.lua", "tests/model.lua", "tests/thumbs.lua" }) do
  assert(loadfile(path))(context)
end
print(("%d tests, %d failures"):format(total, failures))
os.exit(failures == 0 and 0 or 1)
