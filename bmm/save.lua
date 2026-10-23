-- Persistent settings: favourites, profiles, UI prefs, and the enabled-state
-- snapshot REPENTOGON's undo (Backspace) restores to.
local json = require("json")
local U = include("bmm.util")

local Save = {
  data = nil,
}

local DEFAULT = {
  version = 2,
  favs = {},
  profiles = {},      -- p1..p4 = { name = "...", set = { [dir] = true } }
  sort = 1,
  lang = "auto",      -- "auto" follows the game's language, or "en" / "ru"
  classic = false,    -- true = show the plain vanilla list
  proc = nil,         -- { start = <os.time estimate>, states = { [dir] = bool } }
}

function Save.load(mod)
  local data
  if mod:HasData() then
    local ok, res = pcall(json.decode, mod:LoadData())
    if ok and type(res) == "table" then data = res end
  end
  data = data or {}
  for k, v in pairs(DEFAULT) do
    if data[k] == nil then
      data[k] = type(v) == "table" and {} or v
    end
  end
  Save.data = data
  Save.mod = mod
end

function Save.write()
  if not Save.mod then return end
  local ok, res = pcall(json.encode, Save.data)
  if ok then
    Save.mod:SaveData(res)
  else
    U.log("save failed: " .. tostring(res))
  end
end

-- Estimated wall-clock start time of this game process.
local function processStart()
  return os.time() - Isaac.GetFrameCount() / 60
end

-- REPENTOGON snapshots every mod's state the first time the mods menu is
-- rendered in a process and Backspace restores that snapshot. Lua mods are
-- reloaded when the mod list changes, so we remember the snapshot per process.
function Save.processSnapshot(currentStates)
  local d = Save.data
  local start = processStart()
  if Isaac.GetFrameCount() < 120 or not d.proc or math.abs((d.proc.start or 0) - start) > 30 then
    -- fresh game start (or our mod got enabled mid-session): current states are the snapshot
    d.proc = { start = start, states = currentStates }
    Save.write()
  end
  return d.proc.states
end

return Save
