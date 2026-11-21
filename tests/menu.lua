local t = ...
local test, eq = t.test, t.eq
local function fixture(classic)
  local env = t.environment()
  env.REPENTOGON = true
  env.MainMenuType = { MODS = 16, TITLE = 1 }
  env.ModCallbacks = { MC_MAIN_MENU_RENDER = 1, MC_POST_GAME_STARTED = 2 }
  env.SoundEffect = {}
  env.Keyboard = { KEY_F2 = 291, KEY_F9 = 298, KEY_L = 76, KEY_S = 83, KEY_B = 66,
    KEY_D = 68, KEY_O = 79, KEY_P = 80, KEY_C = 67, KEY_PAGE_UP = 266, KEY_PAGE_DOWN = 267,
    KEY_HOME = 268, KEY_END = 269, KEY_LEFT_BRACKET = 91, KEY_RIGHT_BRACKET = 93,
    KEY_ESCAPE = 256, KEY_LEFT_CONTROL = 341, KEY_LEFT_SHIFT = 340 }
  for i = 1, 4 do env.Keyboard["KEY_" .. i] = 48 + i end
  env.ButtonAction = { ACTION_MENUCONFIRM = 14, ACTION_MENUBACK = 15, ACTION_MENULEFT = 20,
    ACTION_MENURIGHT = 21, ACTION_MENUUP = 22, ACTION_MENUDOWN = 23, ACTION_MENUTAB = 28,
    ACTION_MENUEX = 29, ACTION_MENULT = 26, ACTION_MENURT = 27, ACTION_MENULB = 24,
    ACTION_MENURB = 25, ACTION_FULLSCREEN = 16, ACTION_MUTE = 17 }
  env.Vector = function(x, y) return { X = x, Y = y } end
  env.SFXManager = function() return { Play = function() end } end
  local keys, actions, frame, currentMenu, selection = {}, {}, 1000, 16, 1
  local mask, state, callbacks, modules, logs = 0xFFFFFFFF, nil, {}, {}, {}
  env.Input = {
    GetDeviceNameByIdx = function() return nil end,
    IsButtonTriggered = function(k) return keys[k] or false end,
    IsButtonPressed = function(k) return keys[k] or false end,
    IsActionTriggered = function(a, c) return actions[c] and actions[c][a] or false end,
    IsActionPressed = function(a, c) return actions[c] and actions[c][a] or false end,
  }
  env.Isaac.GetFrameCount = function() return frame end
  env.Isaac.DebugString = function(msg) logs[#logs + 1] = msg end
  env.Isaac.WorldToMenuPosition = function() return env.Vector(39, 15) end
  env.MenuManager = { GetActiveMenu = function() return currentMenu end,
    SetInputMask = function(m) mask = m end }
  env.ModsMenu = { GetSelectedElement = function() return selection end,
    SetSelectedElement = function(i) selection = i end }
  local entries = {}
  for i = 1, 16 do entries[i] = { name = ("Mod %02d"):format(i), realdirectory = "mod" .. i, enabled = true } end
  env.XMLNode = { MOD = 1 }
  env.XMLData = { GetCurrentMod = function() return { realdirectory = "mod1" } end,
    GetNumEntries = function() return #entries end, GetEntryById = function(_, i) return entries[i] end }
  local data = t.json.encode({ classic = classic or false })
  env.RegisterMod = function()
    return { HasData = function() return true end, LoadData = function() return data end,
      SaveData = function(_, value) data = value end,
      AddCallback = function(_, id, fn) callbacks[id] = fn end,
      AddPriorityCallback = function() end,
      RemoveCallback = function(_, id) callbacks[id] = nil end }
  end
  local include = env.include
  env.include = function(name)
    local m
    if name == "bmm.ui" then
      m = { ROWS = 9, LIST_ROWS = 6, NUM_FILTERS = 10, NUM_SORTS = 3,
        font = { GetStringWidth = function(_, s) return #s * 6 end },
        init = function() end, draw = function(s) state = s end }
    else m = include(name) end
    modules[name] = m
    return m
  end
  assert(loadfile("main.lua", "t", env))()
  local f = { env = env, modules = modules, logs = logs }
  function f.step(k, a, ctl)
    frame = frame + 21 -- each scripted input starts after key repeat's debounce
    keys, actions = {}, { [ctl or 0] = {} }
    for _, key in ipairs(k or {}) do keys[key] = true end
    for _, action in ipairs(a or {}) do actions[ctl or 0][action] = true end
    assert(callbacks[1], table.concat(logs, "\n"))()
  end
  function f.state() return state end
  function f.mask() return mask end
  function f.menu(id) currentMenu = id end
  function f.select(i) selection = i end
  f.step()
  f.step()
  return f
end

test("classic mode tracks search before returning through F2", function()
  local f = fixture(true)
  f.step({341})
  f.step({65})
  f.step({257})
  f.step({291})
  f.step()
  eq(f.state().search, "a")
  eq(#f.state().list, 0)
  eq(f.mask() & (1 << 14), 0)
end)
test("classic mode tracks a vanilla toggle before returning through F2", function()
  local f = fixture(true)
  f.select(2)
  f.step()
  f.step({}, {14})
  f.step({291})
  f.step()
  eq(f.modules["bmm.model"].byDir.mod2.enabled, false)
end)
test("switching to classic captures the current vanilla pointer", function()
  local f = fixture()
  f.step({291})
  f.step({}, {14})
  f.step({291})
  f.step()
  eq(f.modules["bmm.model"].byDir.mod1.enabled, false)
end)
test("classic gamepad undo restores the model as well as vanilla", function()
  local f = fixture(true)
  f.step({}, {14}, 1)
  eq(f.modules["bmm.model"].byDir.mod1.enabled, false)
  f.step({}, {24}, 1)
  eq(f.modules["bmm.model"].byDir.mod1.enabled, true)
end)
test("returning from classic closes a previously open panel", function()
  local f = fixture()
  f.step({80})
  eq(f.state().panel, "profiles")
  f.step({291})
  f.menu(1)
  f.step()
  f.menu(16)
  f.step({291})
  f.step()
  eq(f.state().panel, nil)
end)
test("undo wins over confirm pressed in the same frame", function()
  local f = fixture()
  f.step({259}, {14})
  eq(f.modules["bmm.model"].byDir.mod1.enabled, true)
end)
test("failure while refreshing settings releases the input mask", function()
  local f = fixture()
  f.menu(1)
  f.step()
  f.menu(16)
  f.modules["bmm.config"].refresh = function() error("bad third-party settings") end
  f.step()
  eq(f.mask(), 0xFFFFFFFF)
  assert(table.concat(f.logs, "\n"):find("falling back", 1, true))
end)
test("filtering to a different mod resets description scroll", function()
  local f = fixture()
  f.modules["bmm.model"].byDir.mod2.enabled = false
  f.state().descScroll = 12
  f.step({}, {21}) -- enabled
  f.step({}, {21}) -- disabled: only Mod 02
  eq(f.state().list[f.state().cursor].dir, "mod2")
  eq(f.state().descScroll, 0)
end)
test("filter arrows step over filters with no mods", function()
  local f = fixture()
  f.step({}, {21})
  eq(f.state().filter, 2) -- on: every fixture mod is enabled
  f.step({}, {21})
  local n = f.state().filter
  assert(n ~= 3 and n ~= 4, "landed on an empty filter " .. n)
  assert(#f.state().list > 0)
  f.step({}, {20})
  eq(f.state().filter, 2)
end)
test("a filter that loses its last mod falls back to all", function()
  local f = fixture()
  f.step({}, {14})
  eq(f.modules["bmm.model"].byDir.mod1.enabled, false)
  f.step({}, {20}) -- left from "all" wraps past the empty "broken" to "changed"
  eq(f.state().filter, 9)
  f.step({259})    -- undo: nothing is changed any more
  f.step()
  eq(f.state().filter, 1)
end)
