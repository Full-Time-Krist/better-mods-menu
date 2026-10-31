-- Better Mods Menu v2 for The Binding of Isaac: Repentance+ (requires REPENTOGON)
--
-- Redraws the vanilla Mods menu with the game's own paper sprites and adds
-- search, filters, sorting, favourites, mod details, dependency warnings,
-- profiles and a page for other mods' settings (MCM, DSS).
-- Mods are still toggled by the vanilla menu itself: we only move its
-- cursor (ModsMenu.SetSelectedElement) and let the confirm press through, so
-- REPENTOGON writes disable.it exactly like it does without this mod.
local BMM = RegisterMod("Better Mods Menu", 1)

if not REPENTOGON then
  Isaac.DebugString("[BetterModsMenu] REPENTOGON not found, staying inactive")
  return
end

local U = include("bmm.util")
local Model = include("bmm.model")
local Rep = include("bmm.repsearch")
local UI = include("bmm.ui")
local Save = include("bmm.save")
local Lang = include("bmm.lang")
local Config = include("bmm.config")
local T = Lang.T

local DEV = false -- jump straight to the mods menu on boot (used for testing)

local MODS = MainMenuType.MODS
local BA = ButtonAction
local KEY = Keyboard
local ALL_INPUT = 0xFFFFFFFF
local SND_MOVE = SoundEffect.SOUND_MENU_SCROLL
local SND_IN = SoundEffect.SOUND_PAPER_IN
local SND_OUT = SoundEffect.SOUND_PAPER_OUT

local NUM_FILTERS = UI.NUM_FILTERS
local NUM_SORTS = UI.NUM_SORTS

local S = {
  A = Vector(39, 15),
  list = {},
  cursor = 1,
  scroll = 0,
  filter = 1,
  sort = 1,
  favs = {},
  panel = nil,            -- nil | "profiles" | "settings"
  cfg = nil,              -- settings page stack: { { page, cursor, scroll } }
  cfgCapture = nil,       -- key binding row waiting for a key press
  profileRows = {},
  profileCursor = 1,
  search = "",
  searching = false,
  gamepad = false,
  descScroll = 0,
  dirty = true,           -- vanilla selection pointer may be stale this frame
  applying = nil,         -- { name, target = {dir=bool}, plan = {mods} }
  toast = nil,
}

local ready = false
local snapshot = {}       -- REPENTOGON undo target
local selectedDir = nil
local lastOX, settled, restY = nil, 0, 15
local maskSet = false
local confirmWasAllowed = false
local pointerMod = nil    -- mod the vanilla menu will toggle on confirm
local jumped = false
local wasActive = false
local debugOverlay = false
local held = {}

-------------------------------------------------------------------- helpers

local function sfx(id)
  if id then SFXManager():Play(id, 0.8) end
end

local function toast(msg, color)
  S.toast = { text = msg, until_ = Isaac.GetFrameCount() + 150, color = color }
end

local function controllers()
  local n = 0
  while Input.GetDeviceNameByIdx(n) do n = n + 1 end
  return math.max(n, 4)
end

local numCtl = 4
local function actionTriggered(a)
  for i = 0, numCtl do
    if Input.IsActionTriggered(a, i) then
      S.gamepad = i > 0
      return true
    end
  end
  return false
end

local function actionPressed(a)
  for i = 0, numCtl do
    if Input.IsActionPressed(a, i) then return true end
  end
  return false
end

local function keyTriggered(k)
  if Input.IsButtonTriggered(k, 0) then
    S.gamepad = false
    return true
  end
  return false
end

-- triggered + auto-repeat while held (menu-style)
local function repeating(a)
  if actionTriggered(a) then
    held[a] = 0
    return true
  end
  if actionPressed(a) then
    held[a] = (held[a] or 0) + 1
    return held[a] > 18 and (held[a] - 18) % 4 == 0
  end
  held[a] = 0
  return false
end

local function bit(a) return 1 << a end

-------------------------------------------------------------------- list

local FILTERS = {
  function() return true end,
  function(m) return m.enabled end,
  function(m) return not m.enabled end,
  function(m) return S.favs[m.dir] end,
  function(m) return m.category == "API" end,
  function(m) return m.category == "CONTENT" end,
  function(m) return m.category == "QOL" end,
  function(m) return m.category == "VISUAL" end,
  function(m) return m.enabled ~= m.enabledAtLoad end,
  function(m) return m.enabled and #Model.missingDeps(m) > 0 end,
}

local CAT_ORDER = { API = 1, CONTENT = 2, QOL = 3, VISUAL = 4 }

local function sortKey(a, b)
  local fa, fb = S.favs[a.dir] and 1 or 0, S.favs[b.dir] and 1 or 0
  if fa ~= fb then return fa > fb end
  if S.sort == 2 and a.enabled ~= b.enabled then return a.enabled end
  if S.sort == 3 and a.category ~= b.category then return CAT_ORDER[a.category] < CAT_ORDER[b.category] end
  if a.simple ~= b.simple then return U.byteLess(a.simple, b.simple) end
  return U.byteLess(a.dir, b.dir)
end

local function rebuildList()
  local inView
  if S.search ~= "" then
    inView = {}
    for _, m in ipairs(Model.vanillaView(S.search)) do inView[m] = true end
  end
  local list = {}
  -- a search always looks through every mod
  local f = S.search ~= "" and FILTERS[1] or FILTERS[S.filter]
  for _, m in ipairs(Model.mods) do
    if f(m) and (not inView or inView[m]) then list[#list + 1] = m end
  end
  table.sort(list, sortKey)
  S.list = list

  -- keep the cursor on the same mod when the list reshuffles
  local keep
  if selectedDir then
    for i, m in ipairs(list) do
      if m.dir == selectedDir then keep = i break end
    end
  end
  S.cursor = U.clamp(keep or S.cursor, 1, math.max(1, #list))
  if list[S.cursor] then selectedDir = list[S.cursor].dir end
  local maxScroll = math.max(0, #list - UI.ROWS)
  if S.cursor - 1 < S.scroll then S.scroll = S.cursor - 1 end
  if S.cursor > S.scroll + UI.ROWS then S.scroll = S.cursor - UI.ROWS end
  S.scroll = U.clamp(S.scroll, 0, maxScroll)
end

local function moveCursor(delta)
  if #S.list == 0 then return end
  local n = S.cursor + delta
  if math.abs(delta) == 1 then
    if n < 1 then n = #S.list elseif n > #S.list then n = 1 end
  else
    n = U.clamp(n, 1, #S.list)
  end
  if n ~= S.cursor then
    S.cursor = n
    selectedDir = S.list[n].dir
    S.descScroll = 0
    sfx(SND_MOVE)
  end
end

local function setFilter(f)
  S.filter = (f - 1) % NUM_FILTERS + 1
  sfx(SND_MOVE)
end

-------------------------------------------------------------------- profiles / apply

local function buildProfileRows()
  local rows = {}
  for i = 1, 4 do
    local p = Save.data.profiles["p" .. i]
    if p and p.set then
      local n = 0
      for _ in pairs(p.set) do n = n + 1 end
      rows[#rows + 1] = { label = T("slot", i, T("profile_name", i)), detail = T("n_on", n), slot = i }
    else
      rows[#rows + 1] = { label = T("slot_empty", i), empty = true, slot = i }
    end
  end
  local atStart = 0
  for _, v in pairs(snapshot) do if v then atStart = atStart + 1 end end
  rows[#rows + 1] = { label = T("at_start"), detail = T("n_on", atStart), special = "start" }
  rows[#rows + 1] = { label = T("everything_off"), special = "off" }
  S.profileRows = rows
  S.profileCursor = U.clamp(S.profileCursor, 1, #rows)
end

local function planFor(target)
  local plan = {}
  local view = {}
  for _, m in ipairs(Model.vanillaView(S.search)) do view[m] = true end
  local selfLast
  for _, m in ipairs(Model.loadOrder) do
    local want = target[m.dir]
    if want == nil then want = false end
    if m.enabled ~= want and view[m] then
      if m.isSelf then selfLast = m else plan[#plan + 1] = m end
    end
  end
  if selfLast then plan[#plan + 1] = selfLast end
  return plan
end

local function startApply(name, target)
  local plan = planFor(target)
  if S.search ~= "" then
    local hidden = 0
    for _, m in ipairs(Model.mods) do
      local want = target[m.dir] == true
      if m.enabled ~= want then hidden = hidden + 1 end
    end
    if hidden > #plan then
      toast(T("t_clear_search"), nil)
      return
    end
  end
  if #plan == 0 then
    toast(T("t_nothing", name), nil)
    return
  end
  S.applying = { name = name, target = target, plan = plan }
  S.panel = nil
  S.filter = 1
  sfx(SND_IN)
end

local function profileTarget(row)
  local t = {}
  if row.special == "start" then
    for dir, v in pairs(snapshot) do t[dir] = v end
  elseif row.special == "off" then
    for _, m in ipairs(Model.mods) do t[m.dir] = m.isSelf end
  else
    local p = Save.data.profiles["p" .. row.slot]
    if not p then return nil end
    for _, m in ipairs(Model.mods) do t[m.dir] = p.set[m.dir] == true end
  end
  return t
end

local function saveProfile(slot)
  local set, n = {}, 0
  for _, m in ipairs(Model.mods) do
    if m.enabled then set[m.dir] = true n = n + 1 end
  end
  Save.data.profiles["p" .. slot] = { set = set }
  Save.write()
  toast(T("t_saved", n, slot), nil)
  buildProfileRows()
end

-------------------------------------------------------------------- settings of other mods

local SELECTABLE = { bool = true, choice = true, number = true, key = true, link = true }

local function cfgClamp(top)
  local rows = top.page.rows
  top.cursor = U.clamp(top.cursor, 1, math.max(1, #rows))
  if top.cursor - 1 < top.scroll then top.scroll = top.cursor - 1 end
  if top.cursor > top.scroll + UI.ROWS then top.scroll = top.cursor - UI.ROWS end
  top.scroll = U.clamp(top.scroll, 0, math.max(0, #rows - UI.ROWS))
end

local function cfgMove(top, dir)
  local rows = top.page.rows
  local n = top.cursor
  for _ = 1, #rows do
    n = (n - 1 + dir) % #rows + 1
    if SELECTABLE[rows[n].kind] then
      top.cursor = n
      cfgClamp(top)
      sfx(SND_MOVE)
      return
    end
  end
end

local function cfgPush(page)
  page.rows = page.build()
  local top = { page = page, cursor = 0, scroll = 0 }
  S.cfg[#S.cfg + 1] = top
  cfgMove(top, 1)
  if top.cursor == 0 then top.cursor = 1 end
  sfx(SND_IN)
end

local function openSettings()
  Config.refresh()
  S.panel = "settings"
  S.cfg = {}
  S.cfgCapture = nil
  cfgPush(Config.pageFor(S.list[S.cursor]))
end

local function closePanel()
  S.panel = nil
  S.cfg = nil
  S.cfgCapture = nil
  sfx(SND_OUT)
end

local PANELS = { "profiles", "settings" }

local function openPanel(name)
  if name == "settings" then return openSettings() end
  S.cfg = nil
  S.panel = name
  if name == "profiles" then buildProfileRows() end
  sfx(SND_IN)
end

-- LB/RB walk through the panels: the gamepad has no T or O key
local function panelCycle()
  local dir = (actionTriggered(BA.ACTION_MENULB) and -1 or 0) + (actionTriggered(BA.ACTION_MENURB) and 1 or 0)
  if dir == 0 then return false end
  for i, name in ipairs(PANELS) do
    if name == S.panel then
      openPanel(PANELS[(i - 1 + dir) % #PANELS + 1])
      return true
    end
  end
  return false
end

local function cfgChanged(top, row)
  top.page.rows = top.page.build()
  cfgClamp(top)
  if row.restart then toast(T("t_restart"), nil) end
end

local function handleSettingsInput()
  local top = S.cfg[#S.cfg]
  if S.cfgCapture then
    if keyTriggered(KEY.KEY_ESCAPE) then
      S.cfgCapture = nil
      return
    end
    local v = Config.capture(S.cfgCapture, numCtl)
    if v then
      Config.change(S.cfgCapture, v)
      cfgChanged(top, S.cfgCapture)
      S.cfgCapture = nil
      sfx(SND_MOVE)
    end
    return
  end
  if panelCycle() then return end
  if repeating(BA.ACTION_MENUUP) then cfgMove(top, -1) end
  if repeating(BA.ACTION_MENUDOWN) then cfgMove(top, 1) end
  local wheel = Input.GetMouseWheel and Input.GetMouseWheel()
  if wheel and wheel.Y ~= 0 then cfgMove(top, wheel.Y > 0 and -1 or 1) end
  local row = top.page.rows[top.cursor]
  local selectable = row and SELECTABLE[row.kind]
  if selectable then
    local value = row.kind == "bool" or row.kind == "choice" or row.kind == "number"
    local dir = 0
    if repeating(BA.ACTION_MENURIGHT) then dir = 1 end
    if repeating(BA.ACTION_MENULEFT) then dir = -1 end
    if value and dir ~= 0 then
      Config.step(row, dir)
      cfgChanged(top, row)
      sfx(SND_MOVE)
    elseif actionTriggered(BA.ACTION_MENUCONFIRM) then
      if row.kind == "link" then
        return cfgPush(row.open())
      elseif row.kind == "key" then
        S.cfgCapture = row
      else
        Config.step(row, 1)
        cfgChanged(top, row)
      end
      sfx(SND_MOVE)
    end
  end
  if actionTriggered(BA.ACTION_MENUBACK) then
    S.cfg[#S.cfg] = nil
    if #S.cfg == 0 then closePanel() else sfx(SND_OUT) end
  elseif keyTriggered(KEY.KEY_O) then
    closePanel()
  end
end

-------------------------------------------------------------------- input

local function handleListInput()
  if S.applying then
    if actionTriggered(BA.ACTION_MENUBACK) then
      S.applying = nil
      toast(T("t_stopped"), nil)
      sfx(SND_OUT)
    end
    return
  end
  if repeating(BA.ACTION_MENUUP) then moveCursor(-1) end
  if repeating(BA.ACTION_MENUDOWN) then moveCursor(1) end
  if keyTriggered(KEY.KEY_PAGE_UP) or actionTriggered(BA.ACTION_MENULT) then moveCursor(-UI.ROWS) end
  if keyTriggered(KEY.KEY_PAGE_DOWN) or actionTriggered(BA.ACTION_MENURT) then moveCursor(UI.ROWS) end
  if keyTriggered(KEY.KEY_HOME) then moveCursor(-#S.list) end
  if keyTriggered(KEY.KEY_END) then moveCursor(#S.list) end
  local wheel = Input.GetMouseWheel and Input.GetMouseWheel()
  if wheel and wheel.Y ~= 0 then moveCursor(wheel.Y > 0 and -1 or 1) end

  if actionTriggered(BA.ACTION_MENULEFT) or actionTriggered(BA.ACTION_MENULB) then setFilter(S.filter - 1) end
  if actionTriggered(BA.ACTION_MENURIGHT) or actionTriggered(BA.ACTION_MENURB) then setFilter(S.filter + 1) end

  if keyTriggered(KEY.KEY_S) then
    S.sort = S.sort % NUM_SORTS + 1
    Save.data.sort = S.sort
    Save.write()
    sfx(SND_MOVE)
  end
  local m = S.list[S.cursor]
  if m and keyTriggered(KEY.KEY_B) then
    S.favs[m.dir] = (not S.favs[m.dir]) or nil
    Save.write()
    toast(S.favs[m.dir] and T("t_pinned", m.name) or T("t_unpinned", m.name), nil)
  end
  if m and keyTriggered(KEY.KEY_D) then
    local miss = Model.missingDeps(m)
    if #miss > 0 then
      local t = Model.snapshot()
      for _, d in ipairs(miss) do t[d.dir] = true end
      startApply(T("n_dependencies"), t)
    else
      toast(T("t_no_deps"), nil)
    end
  end
  if keyTriggered(KEY.KEY_RIGHT_BRACKET) and S.descCut then S.descScroll = S.descScroll + 3 end
  if keyTriggered(KEY.KEY_LEFT_BRACKET) then S.descScroll = math.max(0, S.descScroll - 3) end
  if keyTriggered(KEY.KEY_P) or actionTriggered(BA.ACTION_MENUEX) then openPanel("profiles") end
  if keyTriggered(KEY.KEY_O) then openPanel("settings") end
end

local function handleProfilesInput()
  if panelCycle() then return end
  if repeating(BA.ACTION_MENUUP) then
    S.profileCursor = (S.profileCursor - 2) % #S.profileRows + 1
    sfx(SND_MOVE)
  end
  if repeating(BA.ACTION_MENUDOWN) then
    S.profileCursor = S.profileCursor % #S.profileRows + 1
    sfx(SND_MOVE)
  end
  local row = S.profileRows[S.profileCursor]
  if actionTriggered(BA.ACTION_MENUCONFIRM) and row then
    local t = profileTarget(row)
    if t then startApply(row.special and row.label or T("n_profile", row.slot), t) else toast(T("t_empty_slot"), nil) end
    return
  end
  if row and row.slot and keyTriggered(KEY.KEY_S) then saveProfile(row.slot) end
  if row and row.slot and keyTriggered(KEY.KEY_C) then
    Save.data.profiles["p" .. row.slot] = nil
    Save.write()
    buildProfileRows()
  end
  for i = 1, 4 do
    if keyTriggered(KEY["KEY_" .. i]) then
      if Input.IsButtonPressed(KEY.KEY_LEFT_SHIFT, 0) then saveProfile(i) else
        local t = profileTarget(S.profileRows[i])
        if t then startApply(T("n_profile", i), t) end
      end
    end
  end
  if actionTriggered(BA.ACTION_MENUBACK) or keyTriggered(KEY.KEY_P) then closePanel() end
end

-------------------------------------------------------------------- frame

local function init()
  Model.load()
  Save.load(BMM)
  S.favs = Save.data.favs
  S.sort = U.clamp(tonumber(Save.data.sort) or 1, 1, NUM_SORTS)
  snapshot = Save.processSnapshot(Model.snapshot())
  Lang.set(Save.data.lang ~= "auto" and Save.data.lang or Lang.detect())
  Config.init(Model, Save, Lang)
  UI.init(Model, Lang, Config)
  Config.refresh()
  if DEV then U.log("language option: " .. tostring(Options.Language) .. " -> " .. Lang.current) end
  Rep.init(UI.font)
  numCtl = controllers()
  ready = true
end

local function clearMask()
  if maskSet then
    MenuManager.SetInputMask(ALL_INPUT)
    maskSet = false
  end
  confirmWasAllowed = false
  pointerMod = nil
end

local function updateAnchor(active)
  local o = Isaac.WorldToMenuPosition(MODS, Vector(0, 0))
  if active and lastOX and math.abs(o.X - lastOX) < 0.01 then
    settled = settled + 1
  else
    settled = 0
  end
  lastOX = o.X
  -- vanilla scrolls the whole page when its cursor moves; once the page is
  -- at rest we pin our layout so it doesn't bounce with that scroll
  if settled < 2 then restY = o.Y end
  S.A = Vector(o.X, settled >= 2 and restY or o.Y)
  S.settled = settled >= 2
  return o
end

local function activeFrame()
  -- 1) catch up with what REPENTOGON did in this frame's Update/Render
  local searchingAtUpdate = Rep.searching
  local ev = Rep.step(#Model.mods, S.gamepad)
  S.searching = Rep.searching
  if ev.changed then
    S.search = Rep.str
  end
  if ev.undo then
    Model.applyStates(snapshot)
    S.applying = nil
    toast(T("t_undone"), nil)
  end

  local confirm = actionTriggered(BA.ACTION_MENUCONFIRM)
  if confirm and confirmWasAllowed and pointerMod and not searchingAtUpdate
    and not Input.IsButtonTriggered(KEY.KEY_LEFT_CONTROL, 0) then
    pointerMod.enabled = not pointerMod.enabled
    if S.applying then
      S.applying.plan = planFor(S.applying.target)
    end
  end

  -- 2) our own controls
  if not S.cfgCapture and keyTriggered(KEY.KEY_F2) then
    Save.data.classic = true
    Save.write()
    return false
  end
  if not S.cfgCapture and keyTriggered(KEY.KEY_F9) then debugOverlay = not debugOverlay end
  if keyTriggered(KEY.KEY_L) and not S.searching and not S.cfgCapture then
    -- cycle UI language; saved, so it overrides the game's language from now on
    local order, nextLang = Lang.ORDER, Lang.ORDER[1]
    for i, code in ipairs(order) do
      if code == Lang.current then nextLang = order[i % #order + 1] end
    end
    Lang.set(nextLang)
    Save.data.lang = nextLang
    Save.write()
    buildProfileRows()
    toast(T("t_lang"), nil)
  end
  if not S.searching then
    if S.panel == "profiles" then handleProfilesInput()
    elseif S.panel == "settings" then handleSettingsInput()
    else handleListInput() end
  end

  rebuildList()

  -- 3) point the vanilla cursor at the mod the next confirm should toggle
  local target
  if S.applying then
    S.applying.plan = planFor(S.applying.target)
    target = S.applying.plan[1]
    if not target then
      toast(T("t_applied", S.applying.name), nil)
      S.applying = nil
    else
      for i, m in ipairs(S.list) do
        if m == target then S.cursor = i selectedDir = m.dir end
      end
      rebuildList()
    end
  end
  if not target and not S.panel then target = S.list[S.cursor] end

  local view = Model.vanillaView(S.search)
  local idx
  for i, m in ipairs(view) do
    if m == target then idx = i break end
  end
  local cur = ModsMenu.GetSelectedElement()
  S.dirty = false
  if idx then
    if cur ~= idx then
      ModsMenu.SetSelectedElement(idx)
      S.dirty = true
    end
  else
    if cur ~= 1 then ModsMenu.SetSelectedElement(1) end
    S.dirty = true
  end
  -- REPENTOGON's own Lua tweak moves the vanilla cursor on these, maybe after us
  if Input.IsButtonTriggered(KEY.KEY_PAGE_UP, 0) or Input.IsButtonTriggered(KEY.KEY_PAGE_DOWN, 0)
    or actionTriggered(BA.ACTION_MENULEFT) or actionTriggered(BA.ACTION_MENURIGHT)
    or actionTriggered(BA.ACTION_MENULT) or actionTriggered(BA.ACTION_MENURT) then
    S.dirty = true
  end
  pointerMod = (not S.dirty and idx) and target or nil

  -- 4) what the vanilla menu may see next frame
  local mask = bit(BA.ACTION_FULLSCREEN) | bit(BA.ACTION_MUTE)
  -- a key binding wait or a settings page must not switch all mods off
  if S.panel ~= "settings" then mask = mask | bit(BA.ACTION_MENUTAB) end
  if not S.panel and not S.applying then mask = mask | bit(BA.ACTION_MENUBACK) end
  local allowConfirm = pointerMod ~= nil and not S.panel
  if allowConfirm then mask = mask | bit(BA.ACTION_MENUCONFIRM) end
  MenuManager.SetInputMask(mask)
  maskSet = true
  confirmWasAllowed = allowConfirm

  S.debugView = view
  return true
end

-- Something broke: hand the menu back to vanilla for the rest of the session
-- instead of leaving its input masked.
local failed = false
local function fail(err)
  U.log("error, falling back to the vanilla menu: " .. tostring(err))
  maskSet = true
  clearMask()
  failed = true
end

local function onMainMenuRender()
  if failed then return end
  if not ready then
    local ok, err = pcall(init)
    if not ok then
      U.log("init failed: " .. tostring(err))
      BMM:RemoveCallback(ModCallbacks.MC_MAIN_MENU_RENDER, onMainMenuRender)
      return
    end
  end

  local menu = MenuManager.GetActiveMenu()
  if DEV and not jumped and menu == MainMenuType.TITLE then
    jumped = true
    MenuManager.SetActiveMenu(MODS)
    return
  end

  local active = menu == MODS
  if not active then Rep.leftMenu() end
  if active and not wasActive then Config.refresh() end -- mods add settings during a run
  wasActive = active

  if Save.data.classic then
    clearMask()
      if active and keyTriggered(KEY.KEY_F2) then
      Save.data.classic = false
      Save.write()
    end
    return
  end

  local o = updateAnchor(active)
  if active then
    local ok, res = pcall(activeFrame)
    if not ok then return fail(res) end
    if not res then
      clearMask()
      return
    end
  else
    clearMask()
    S.panel = nil
    S.cfg = nil
    S.cfgCapture = nil
    S.applying = nil
    S.dirty = true
  end

  -- draw while the page is on screen (also during the slide in/out). Check our
  -- pinned anchor, not the vanilla one: vanilla scrolls its page far up on long
  -- lists (more so on tall windows) and we must not stop covering it then
  local A = S.A
  if A.X > -480 and A.X < 480 and A.Y > -300 and A.Y < 300 then
    local ok, err = pcall(function()
      rebuildList()
      UI.draw(S, 1)
    end)
    if not ok then return fail(err) end
    if debugOverlay and active and S.debugView then
      UI.drawDebug(S, S.debugView, ModsMenu.GetSelectedElement() - 1)
    end
  end
end

BMM:AddCallback(ModCallbacks.MC_MAIN_MENU_RENDER, onMainMenuRender)

-- leaving the menu for a run: MenuManager is unavailable in game, so only mark the
-- mask stale; the first menu render after the run clears it
BMM:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
  maskSet = true
  confirmWasAllowed = false
  pointerMod = nil
end)

-- other mods have loaded their config by now: write what was changed in the menu
BMM:AddPriorityCallback(ModCallbacks.MC_POST_GAME_STARTED, 1000000, function()
  if ready then
    Config.commit()
    Config.rememberRunPages()
  end
end)
