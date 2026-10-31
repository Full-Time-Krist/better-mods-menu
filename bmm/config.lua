-- Settings of other mods, read from Mod Config Menu (global ModConfigMenu) and
-- Dead Sea Scrolls (global DeadSeaScrollsMenu) and turned into plain pages of rows
-- that bmm/ui.lua draws on our own paper.
--
-- Page: { title = str, source = "MCM"|"DSS"|nil, rows = {...}, build = fn -> rows }
-- Row:  { id, kind, label = fn -> str, info = fn -> str, ... }
--   kind: "head" "text" "space" "run" (not selectable), "bool" "choice" "number"
--         "key" (values), "link" (opens row.open())
--
-- Many mods load their config on MC_POST_GAME_STARTED and save it on game exit, so
-- in the main menu a write could be overwritten, or a DSS save could store an
-- unloaded table over the mod's real data. Every change therefore goes to a queue in
-- our own save and is written into the mod after its load, when a run starts.
-- MCM options also get the value at once: OnChange is what MCM itself would call.
-- Some mods add their MCM pages only when a run starts. Those pages are remembered
-- as plain data in our save, so they exist in the menu from then on; their changes
-- go through the same queue.
-- DSS rows only touch the mod at commit time, and "func" buttons never run here,
-- they expect a run in progress.
local U = include("bmm.util")

local Config = {}
local Model, Save, T

local resynced = {}
local atLoad = {} -- MCM categories that exist in the main menu before any run
local MAX_REMEMBERED_ROWS = 30 -- per subcategory: ReactionAPI lists every item in the game
local VALUE_KINDS = { bool = true, number = true }

-- a mod's Display function may fail every frame until its config is loaded: log once
local logged = {}

local function try(f, ...)
  local ok, res = pcall(f, ...)
  if ok then return res end
  res = tostring(res)
  if not logged[res] then
    logged[res] = true
    U.log("config: " .. res)
  end
end

-- MCM and DSS texts may be strings, numbers, lists of lines or functions
local function str(v, ...)
  if type(v) == "function" then v = try(v, ...) end
  if type(v) == "table" then
    local parts = {}
    for _, line in ipairs(v) do parts[#parts + 1] = tostring(line) end
    return table.concat(parts, " ")
  end
  return v ~= nil and tostring(v) or ""
end

local function queue() return Save.data.pendingConfig end

function Config.isQueued(row) return queue()[row.id] ~= nil end

function Config.value(row)
  local v = queue()[row.id]
  if v ~= nil then return v end
  return row.read and row.read()
end

function Config.change(row, v)
  queue()[row.id] = v
  resynced[row.id] = true
  Save.write()
  if row.live then try(row.write, v) end
end

-- left/right: dir = -1/1
function Config.step(row, dir)
  local cur = Config.value(row)
  if row.kind == "bool" then
    Config.change(row, not cur)
  elseif row.kind == "choice" then
    Config.change(row, ((cur or 1) + dir - 1) % row.count + 1)
  elseif row.kind == "number" then
    local n, by = (cur or row.min or 0) + dir * row.by, row.by
    if row.min and row.max then
      if n > row.max then n = row.noLoop and row.max or row.min end
      if n < row.min then n = row.noLoop and row.min or row.max end
    end
    if math.floor(by) == by then n = math.floor(n) else n = math.floor(n * 1000 + 0.5) / 1000 end
    Config.change(row, n)
  end
end

--------------------------------------------------------------------------- keys

local keyNames, padNames

local function namesOf(enum, prefix)
  local out = {}
  for name, v in pairs(enum) do
    out[v] = name:gsub("^" .. prefix, ""):gsub("_", " ")
  end
  return out
end

function Config.keyName(row, v)
  keyNames = keyNames or namesOf(Keyboard, "KEY_")
  padNames = padNames or namesOf(Controller, "")
  if v == nil or v < 0 then return T("cfg_unbound") end
  return (row.pad and padNames or keyNames)[v] or tostring(v)
end

-- Returns the key pressed this frame while waiting for a binding. CTRL and
-- BACKSPACE are REPENTOGON's own search and undo, ESC cancels the wait.
function Config.capture(row, numControllers)
  if row.pad then
    for i = 1, numControllers do
      for _, v in pairs(Controller) do
        if Input.IsButtonTriggered(v, i) then return v end
      end
    end
    return nil
  end
  for _, v in pairs(Keyboard) do
    if v ~= Keyboard.KEY_ESCAPE and v ~= Keyboard.KEY_BACKSPACE and v ~= Keyboard.KEY_LEFT_CONTROL
      and Input.IsButtonTriggered(v, 0) then
      return v
    end
  end
end

--------------------------------------------------------------------------- MCM

local function mcmRow(opt, id)
  local OT = ModConfigMenu.OptionType
  local kinds = {
    [OT.SCROLL] = "number", [OT.BOOLEAN] = "bool", [OT.NUMBER] = "number",
    [OT.KEYBIND_KEYBOARD] = "key", [OT.KEYBIND_CONTROLLER] = "key",
    [OT.TEXT] = "text", [OT.TITLE] = "head", [OT.SPACE] = "space",
  }
  local row = { id = id, kind = kinds[opt.Type] or "text", live = true }
  -- MCM draws a slider in place of "$scroll5"; we show the number on the right
  row.label = function()
    local s = str(opt.Display):gsub("%$scroll%d*", "")
    row.noDisplay = s == ""
    if s == "" then s = str(opt.Info) end -- Display failed: not loaded before a run
    return s
  end
  row.info = function() return str(opt.Info) end
  row.read = function()
    if type(opt.CurrentSetting) == "function" then return try(opt.CurrentSetting) end
    return opt.CurrentSetting
  end
  row.write = function(v)
    if type(opt.CurrentSetting) ~= "function" then opt.CurrentSetting = v end
    if opt.OnChange then opt.OnChange(v) end
  end
  row.restart = opt.Restart or opt.Rerun
  if opt.Type == OT.SCROLL then
    row.min, row.max, row.by, row.noLoop, row.scroll = 0, 10, 1, true, true
  elseif row.kind == "number" then
    row.min, row.max, row.noLoop = opt.Minimum, opt.Maximum, opt.NoLoopFromMaxMin
    row.by = math.max(opt.ModifyBy or 1, 0.001)
  end
  row.pad = opt.Type == OT.KEYBIND_CONTROLLER
  local locked = opt.NoCursorHere
  if type(locked) == "function" then locked = try(locked) end
  if locked or (row.kind == "bool" or row.kind == "number") and not opt.OnChange and type(opt.CurrentSetting) == "function" then
    row.kind = "text"
  end
  if row.kind == "text" and not opt.Display then row.kind = "space" end
  return row
end

-- a remembered row: no link to the mod, it only reads the saved data
local function cachedRow(d)
  local row = { id = d.id, kind = d.kind, min = d.min, max = d.max, by = d.by, noLoop = d.noLoop,
    scroll = d.scroll, pad = d.pad, restart = d.restart }
  row.read = function() return d.value end
  row.info = function() return d.info end
  row.label = function()
    if not VALUE_KINDS[d.kind] then return d.label end
    local shown = d.labels and d.labels[tostring(Config.value(row))]
    row.noDisplay = not shown
    return shown or (d.label:gsub(":.*$", ""))
  end
  return row
end

local function mcmOptions(cat, sub)
  local rows = {}
  if sub.cached then
    for i, d in ipairs(sub.cached) do rows[i] = cachedRow(d) end
    return rows
  end
  for i, opt in ipairs(sub.Options or {}) do
    local row = mcmRow(opt, ("mcm|%s|%s|%d"):format(cat.Name, sub.Name, i))
    -- queued from an earlier session: the mod has just reloaded its old value
    if queue()[row.id] ~= nil and not resynced[row.id] then
      resynced[row.id] = true
      try(row.write, queue()[row.id])
    end
    rows[i] = row
  end
  return rows
end

local function mcmPage(cat, sub)
  return { title = sub.Name, source = "MCM", info = str(sub.Info), build = function() return mcmOptions(cat, sub) end }
end

local function mcmCategory(cat)
  local subs = cat.Subcategories or {}
  if #subs == 1 then
    local page = mcmPage(cat, subs[1])
    page.title = cat.Name
    return page
  end
  return { title = cat.Name, source = "MCM", info = str(cat.Info), build = function()
    local rows = {}
    for i, sub in ipairs(subs) do
      rows[i] = { kind = "link", label = function() return sub.Name end, info = function() return str(sub.Info) end,
        open = function() return mcmPage(cat, sub) end }
    end
    return rows
  end }
end

--------------------------------------------------------------------------- DSS

local function dssReload(tbl, item, btn)
  if not btn.load then return end
  local ok, v = pcall(btn.load, btn, item, tbl)
  if ok then
    btn.setting = v
    if btn.variable then tbl.DirectoryKey.Settings[btn.variable] = v end
  end
end

local function dssButtonText(btn)
  if btn.str ~= nil then return str(btn.str) end
  return str(btn.strset)
end

local dssPage

local function dssRow(tbl, key, item, btn, i)
  local tip = btn.tooltip or item.tooltip
  local row = {
    id = ("dss|%s|%s|%s"):format(tbl.Name, key, btn.variable or i),
    label = function() return dssButtonText(btn) end,
    info = function() return tip and str(tip.strset or tip.str) or "" end,
    read = function() return btn.setting end,
  }
  row.write = function(v)
    btn.setting = v
    if btn.variable then
      tbl.DirectoryKey.Settings[btn.variable] = v
      tbl.DirectoryKey.SettingsChanged = true
    end
    if btn.store then btn.store(v, btn, item, tbl) end
    if btn.changefunc then btn.changefunc(btn, item) end
  end
  if btn.action == "resume" or btn.action == "back" or btn.action == "openmenu" then
    return nil
  elseif dssButtonText(btn) == "" and not btn.variable then
    row.kind = "space" -- sprites only, like credits pages
  elseif btn.dest and tbl.Directory[btn.dest] and not btn.menu then
    row.kind = "link"
    row.open = function() return dssPage(tbl, btn.dest) end
  elseif btn.variable or btn.setting ~= nil then
    if btn.choices then
      row.kind, row.count = "choice", #btn.choices
      row.choices = btn.choices
    elseif btn.max then
      row.kind, row.min, row.max, row.by = "number", btn.min or 0, btn.max, btn.increment or 1
      row.suffix = btn.suf or ""
    elseif btn.keybind then
      row.kind = "key"
    else
      row.kind = "text"
    end
  elseif btn.func then
    row.kind = "run"
  else
    row.kind = "text"
  end
  return row
end

local function dssRows(tbl, key)
  local item = tbl.Directory[key]
  if item.generate then try(item.generate, item, tbl) end
  local rows = {}
  for i, btn in ipairs(item.buttons or {}) do
    if btn.generate then try(btn.generate, btn, item, tbl) end
    dssReload(tbl, item, btn)
    local shown = btn.display ~= false
    if shown and btn.displayif then shown = try(btn.displayif, btn, item, tbl) ~= false end
    local row = shown and dssRow(tbl, key, item, btn, i)
    if row then rows[#rows + 1] = row end
  end
  return rows
end

dssPage = function(tbl, key)
  local item = tbl.Directory[key]
  local title = key == (tbl.DirectoryKey.Main or "main") and tbl.Name or str(item.title)
  return { title = title, source = "DSS", build = function() return dssRows(tbl, key) end }
end

local function dssEntry(tbl)
  local core = tbl.Name == "Menu"
  return { name = core and "Dead Sea Scrolls" or tbl.Name, source = "DSS",
    open = function()
      local page = dssPage(tbl, tbl.DirectoryKey.Main or "main")
      page.title = core and "Dead Sea Scrolls" or page.title
      return page
    end }
end

--------------------------------------------------------------------------- list

local matches

local function modIsOn(name)
  for _, m in ipairs(Model.mods) do
    if m.enabledAtLoad and matches({ name = name }, m) then return true end
  end
  return false
end

function Config.entries()
  local out = {}
  local live = {}
  if type(ModConfigMenu) == "table" and ModConfigMenu.MenuData then
    for _, cat in ipairs(ModConfigMenu.MenuData) do
      live[cat.Name] = true
      out[#out + 1] = { name = cat.Name, source = "MCM", open = function() return mcmCategory(cat) end }
    end
  end
  for name, data in pairs(Save.data.cfgCache) do
    if not live[name] and modIsOn(name) then
      local cat = { Name = name, Subcategories = {} }
      for i, sub in ipairs(data.subs) do
        cat.Subcategories[i] = { Name = sub.name, cached = sub.rows }
      end
      out[#out + 1] = { name = name, source = "MCM", open = function() return mcmCategory(cat) end }
    end
  end
  if type(DeadSeaScrollsMenu) == "table" and DeadSeaScrollsMenu.Menus then
    local names = {}
    for name in pairs(DeadSeaScrollsMenu.Menus) do names[#names + 1] = name end
    table.sort(names, U.byteLess)
    for _, name in ipairs(names) do
      local tbl = DeadSeaScrollsMenu.Menus[name]
      if tbl.Directory then out[#out + 1] = dssEntry(tbl) end
    end
  end
  return out
end

local function norm(s) return U.lower(s):gsub("[^%w]", "") end

-- "External item descriptions" -> "eid"
local function initials(s)
  local out = {}
  for word in U.lower(s):gmatch("%a+") do out[#out + 1] = word:sub(1, 1) end
  return table.concat(out)
end

local function sharedPrefix(a, b)
  local n = 0
  while n < #a and n < #b and a:byte(n + 1) == b:byte(n + 1) do n = n + 1 end
  return n
end

-- settings pages rarely carry the exact mod name: "EID", "Minimap API" for "!!miniMAPI"
matches = function(entry, m)
  local a, b = norm(entry.name), norm(m.name)
  if a == b then return true end
  if #a < 3 or #b < 3 then return false end
  if a:find(b, 1, true) or b:find(a, 1, true) then return true end
  if a == initials(m.name) then return true end
  return sharedPrefix(a, b) >= math.max(6, math.min(#a, #b) * 0.8)
end

-- attaches m.cfg = { entries } to the mods that have settings
function Config.refresh()
  for _, m in ipairs(Model.mods) do m.cfg = nil end
  for _, entry in ipairs(Config.entries()) do
    for _, m in ipairs(Model.mods) do
      if matches(entry, m) then
        m.cfg = m.cfg or {}
        m.cfg[#m.cfg + 1] = entry
      end
    end
  end
end

function Config.listPage(entries, title)
  return { title = title, build = function()
    local rows = {}
    for i, entry in ipairs(entries) do
      rows[i] = { kind = "link", tag = entry.source, label = function() return entry.name end,
        info = function() return "" end, open = entry.open }
    end
    if #rows == 0 then
      rows[1] = { kind = "text", label = function() return T("cfg_none") end, info = function() return "" end }
    end
    return rows
  end }
end

-- the page for a mod, or the list of everything when it has no settings of its own
function Config.pageFor(m)
  if m and m.cfg then
    if #m.cfg == 1 then return m.cfg[1].open() end
    return Config.listPage(m.cfg, m.name)
  end
  return Config.listPage(Config.entries(), T("settings"))
end

------------------------------------------------------------------------- commit

local function queuedDssMenus()
  local names = {}
  for id in pairs(queue()) do
    local name = id:match("^dss|(.-)|")
    if name then names[name] = true end
  end
  return names
end

local function allRows()
  local byId = {}
  if type(ModConfigMenu) == "table" and ModConfigMenu.MenuData then
    for _, cat in ipairs(ModConfigMenu.MenuData) do
      for _, sub in ipairs(cat.Subcategories or {}) do
        for i, opt in ipairs(sub.Options or {}) do
          local row = mcmRow(opt, ("mcm|%s|%s|%d"):format(cat.Name, sub.Name, i))
          byId[row.id] = row
        end
      end
    end
  end
  if type(DeadSeaScrollsMenu) == "table" and DeadSeaScrollsMenu.Menus then
    for name in pairs(queuedDssMenus()) do
      local tbl = DeadSeaScrollsMenu.Menus[name]
      for key, item in pairs(tbl and tbl.Directory or {}) do
        if type(item) == "table" and item.buttons then
          for _, row in ipairs(dssRows(tbl, key)) do
            row.tbl = tbl
            byId[row.id] = row
          end
        end
      end
    end
  end
  return byId
end

-- DSS has no save call of its own: only its close handler reaches the mod's save
-- function, and that handler also calls store on every button of the menu. Fiend
-- Folio has one per achievement and writing them zeroes its counters, so the handler
-- sees an empty directory here; the changed buttons have already been stored.
local function dssSave(tbl)
  if not tbl.Close then return end
  local directory = tbl.Directory
  local main = tbl.DirectoryKey.Main or "main"
  tbl.Directory = { [main] = { buttons = {} } }
  tbl.DirectoryKey.SettingsChanged = true
  try(tbl.Close, tbl, false, true)
  tbl.Directory = directory
  tbl.DirectoryKey.Item = directory[main]
end

-- writes the queued values into their mods; runs in a run, after the mods loaded
function Config.commit()
  if next(queue()) == nil then return end
  local rows = allRows()
  local touched = {}
  for id, v in pairs(queue()) do
    local row = rows[id]
    if row then
      try(row.write, v)
      if row.tbl then touched[row.tbl] = true end
    end
  end
  for tbl in pairs(touched) do dssSave(tbl) end
  Save.data.pendingConfig = {}
  Save.write()
end

local function remember(cat, known)
  local data = { subs = {} }
  for _, sub in ipairs(cat.Subcategories or {}) do
    local rows = {}
    local options = sub.Options or {}
    for i = 1, #options <= MAX_REMEMBERED_ROWS and #options or 0 do
      local opt = options[i]
      local row = mcmRow(opt, ("mcm|%s|%s|%d"):format(cat.Name, sub.Name, i))
      local d = { id = row.id, kind = row.kind, label = row.label(), info = row.info(), value = row.read(),
        min = row.min, max = row.max, by = row.by, noLoop = row.noLoop, scroll = row.scroll, pad = row.pad,
        restart = row.restart and true or nil }
      -- a label is known only for values seen in a run; the rest show the raw value
      if VALUE_KINDS[row.kind] and not row.scroll and d.value ~= nil then
        d.labels = known[row.id] or {}
        d.labels[tostring(d.value)] = d.label
      end
      rows[i] = d
    end
    if #rows > 0 then data.subs[#data.subs + 1] = { name = sub.Name, rows = rows } end
  end
  return data
end

-- after commit: remember the MCM pages that did not exist when the menu first opened
function Config.rememberRunPages()
  if type(ModConfigMenu) ~= "table" or not ModConfigMenu.MenuData then return end
  local changed = false
  for _, cat in ipairs(ModConfigMenu.MenuData) do
    if not atLoad[cat.Name] then
      local known = {}
      for _, sub in ipairs((Save.data.cfgCache[cat.Name] or { subs = {} }).subs) do
        for _, d in ipairs(sub.rows) do known[d.id] = d.labels end
      end
      Save.data.cfgCache[cat.Name] = remember(cat, known)
      changed = true
    end
  end
  if changed then Save.write() end
end

function Config.init(model, save, lang)
  Model, Save, T = model, save, lang.T
  if type(ModConfigMenu) == "table" and ModConfigMenu.MenuData then
    for _, cat in ipairs(ModConfigMenu.MenuData) do atLoad[cat.Name] = true end
  end
end

return Config
