-- Mod list, categories, dependencies, and the exact order of the vanilla
-- (REPENTOGON-patched) mods list, which is what ModsMenu.SetSelectedElement indexes.
local U = include("bmm.util")

local Model = {
  mods = {},        -- display data, one entry per installed mod
  byDir = {},
  loadOrder = {},   -- ModManager::_mods order (byte-sorted by metadata name)
  ownDir = nil,
}

-- REPENTOGON's workshop item is a dummy; the real thing is installed by the launcher.
local IGNORE_AS_DEP = { ["3127536138"] = true }

local DEP_WORDS = { "requir", "depends on", "dependenc", "in order to function", "to function", "must have", "make sure to have", "enabled!" }

local function simpleName(name)
  local s = U.lower(name)
  s = s:gsub("%b[]", "")          -- "[Rep]", "[BETA]"
  s = s:gsub("[^%w ]", "")        -- "!!~" prefixes etc.
  return U.trim(s:gsub("%s+", " "))
end

local function hasTag(m, ...)
  for _, want in ipairs({ ... }) do
    if m.tagSet[want] then return true end
  end
  return false
end

local VISUAL_HINTS = { "resprite", "only visual", "purely visual", "cosmetic", "texture pack", "reskin", "reactions" }
-- tags only real content mods carry (EID & co. also tag Items/Trinkets)
local STRONG_CONTENT = { "player characters", "enemies", "bosses", "familiars", "rooms", "hazards", "babies", "floors" }

local function categorize(m)
  local n = m.simple
  local d = U.lower(m.desc)
  if n:find("api") or n:find("lib") or d:find("this mod is an api") or d:find("it's an api") or d:find("is a library") then
    return "API"
  end
  for _, h in ipairs(VISUAL_HINTS) do
    if d:find(h, 1, true) or n:find(h, 1, true) then return "VISUAL" end
  end
  local strong = 0
  for _, t in ipairs(STRONG_CONTENT) do
    if m.tagSet[t] then strong = strong + 1 end
  end
  if strong >= 2 then return "CONTENT" end
  if hasTag(m, "tweaks", "removals") then return "QOL" end
  local content = 0
  for _, t in ipairs({ "items", "active items", "characters", "enemies", "bosses", "floors", "trinkets", "challenges", "cards", "pills", "pickups" }) do
    if m.tagSet[t] then content = content + 1 end
  end
  if content >= 3 then return "CONTENT" end
  if hasTag(m, "graphics", "sound", "music") then return "VISUAL" end
  return "QOL"
end

local function findDeps(m, all)
  local raw = U.lower(m.descRaw or "")
  if raw == "" then return {} end
  local deps = {}
  for _, word in ipairs(DEP_WORDS) do
    local from = 1
    while true do
      local s = raw:find(word, from, true)
      if not s then break end
      local window = raw:sub(math.max(1, s - 220), s + 260)
      for _, o in ipairs(all) do
        if o ~= m and not IGNORE_AS_DEP[o.id] and not deps[o.dir] then
          local hit = false
          if o.id ~= "" and o.id:match("^%d+$") and window:find("id=" .. o.id, 1, true) then hit = true end
          if not hit and #o.simple >= 6 and window:find(o.simple, 1, true) then hit = true end
          if not hit and o.alias and window:find(o.alias, 1, true) then hit = true end
          -- "needed for new version" style sentences describe the reverse relation
          if hit and raw:sub(s, s + 12):find("needed for", 1, true) then hit = false end
          if hit then deps[o.dir] = true end
        end
      end
      from = s + #word
    end
  end
  local list = {}
  for dir in pairs(deps) do list[#list + 1] = dir end
  table.sort(list)
  return list
end

function Model.load()
  Model.mods, Model.byDir, Model.loadOrder = {}, {}, {}
  local okCur, cur = pcall(XMLData.GetCurrentMod)
  Model.ownDir = okCur and cur and cur.realdirectory or "better-mods-menu"

  local n = XMLData.GetNumEntries(XMLNode.MOD) or 0
  -- ids are 1..n, but be lenient in case of gaps
  local i, found = 0, 0
  while found < n and i < n + 64 do
    local e = XMLData.GetEntryById(XMLNode.MOD, i)
    i = i + 1
    if e and e.name then
      found = found + 1
      local tags, tagSet = {}, {}
      for rawTag in tostring(e.tags or ""):gmatch("[^,]+") do
        local t = U.trim(rawTag)
        if t ~= "" and t ~= "Lua" then tags[#tags + 1] = t end
        tagSet[U.lower(t)] = true
      end
      local m = {
        rawName = e.name,                         -- byte-exact, used for vanilla ordering/search
        name = U.trim(e.name),
        dir = e.realdirectory or e.directory or e.name,
        fullDir = e.fulldirectory,                -- absolute path, for the mod's own thumb.png
        id = tostring(e.id or ""),
        version = e.version or "",
        descRaw = e.description or "",
        tags = tags,
        tagSet = tagSet,
        enabledAtLoad = e.enabled == "true" or e.enabled == true,
      }
      m.enabled = m.enabledAtLoad
      m.desc = U.cleanDescription(m.descRaw)
      m.simple = simpleName(m.name)
      m.isWorkshop = m.id:match("^%d+$") ~= nil and m.id ~= m.dir
      m.isSelf = m.dir == Model.ownDir
      if m.simple:find("stage api") then m.alias = "stageapi" end
      Model.mods[#Model.mods + 1] = m
      Model.byDir[m.dir] = m
    end
  end

  for _, m in ipairs(Model.mods) do
    m.category = categorize(m)
    m.deps = m.isSelf and {} or findDeps(m, Model.mods)
  end

  for _, m in ipairs(Model.mods) do Model.loadOrder[#Model.loadOrder + 1] = m end
  table.sort(Model.loadOrder, function(a, b)
    if a.rawName ~= b.rawName then return U.byteLess(a.rawName, b.rawName) end
    return U.byteLess(a.dir, b.dir)
  end)
  U.log(("loaded %d mods (%s)"):format(#Model.mods, Model.ownDir))
end

-- Exact replica of the list REPENTOGON draws: enabled mods first, then
-- disabled ones, each group in load order, filtered by its search string.
-- Returns array of mods (index 1 == vanilla SelectedElement 0).
function Model.vanillaView(search)
  local view = {}
  local i = 1
  local function pass(wantEnabled)
    for _, m in ipairs(Model.loadOrder) do
      if m.enabled == wantEnabled then
        local label = tostring(i) .. "." .. m.rawName
        if search == "" or U.lower(label):find(search, 1, true) then
          view[#view + 1] = m
          i = i + 1
        end
      end
    end
  end
  pass(true)
  pass(false)
  return view
end

function Model.countOn()
  local on = 0
  for _, m in ipairs(Model.mods) do if m.enabled then on = on + 1 end end
  return on
end

function Model.pending()
  local list = {}
  for _, m in ipairs(Model.mods) do
    if m.enabled ~= m.enabledAtLoad then list[#list + 1] = m end
  end
  return list
end

function Model.missingDeps(m)
  local miss = {}
  for _, dir in ipairs(m.deps or {}) do
    local d = Model.byDir[dir]
    if d and not d.enabled then miss[#miss + 1] = d end
  end
  return miss
end

function Model.snapshot()
  local t = {}
  for _, m in ipairs(Model.mods) do t[m.dir] = m.enabled end
  return t
end

function Model.applyStates(states)
  for _, m in ipairs(Model.mods) do
    if states[m.dir] ~= nil then m.enabled = states[m.dir] end
  end
end

return Model
