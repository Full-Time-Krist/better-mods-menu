local t = ...
local function model(entries)
  local env = t.environment()
  env.XMLNode = { MOD = 1 }
  env.XMLData = { GetCurrentMod = function() return { realdirectory = "self" } end,
    GetNumEntries = function() return #entries end, GetEntryById = function(_, id) return entries[id] end }
  local m = env.include("bmm.model")
  m.load()
  return m
end
t.test("Workshop dependency IDs must match completely", function()
  local m = model({
    { name = "Content", realdirectory = "content", enabled = true,
      description = "Requires [url=https://steamcommunity.com/sharedfiles/filedetails/?id=1234567899]dependency[/url]" },
    { name = "Library A", realdirectory = "short", id = "123456", enabled = false },
    { name = "Library B", realdirectory = "exact", id = "1234567899", enabled = false },
  })
  local deps = m.missingDeps(m.byDir.content)
  t.eq(#deps, 1)
  t.eq(deps[1].dir, "exact")
end)
t.test("vanilla view groups enabled mods and numbers only matching rows", function()
  local m = model({
    { name = "Zulu", realdirectory = "z", enabled = true },
    { name = "Alpha", realdirectory = "a", enabled = false },
    { name = "Beta", realdirectory = "b", enabled = true },
  })
  local view = m.vanillaView("")
  t.eq(view[1].dir, "b")
  t.eq(view[2].dir, "z")
  t.eq(view[3].dir, "a")
  local filtered = m.vanillaView("1.")
  t.eq(#filtered, 1)
  t.eq(filtered[1].dir, "b")
end)
