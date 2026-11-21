-- Workshop covers and local previews. One sprite per mod avoids changing and
-- reloading the same spritesheet for every visible row on every frame.
local Thumbs = {}
local cache = {}
local ROOT = "gfx/ui/bettermods/thumbs/"

local function sprite(path, anim)
  local s = Sprite()
  s:Load("gfx/ui/bettermods/thumb.anm2", true)
  s:ReplaceSpritesheet(0, path, true)
  s:SetFrame(anim, 0)
  return s
end

local function find(m)
  local paths = {}
  if type(m.id) == "string" and m.id:match("^%d+$") then
    paths[#paths + 1] = ROOT .. "workshop/" .. m.id .. ".png"
  end
  paths[#paths + 1] = ROOT .. m.dir:gsub("[^%w%-_]", "_") .. ".png"
  for _, path in ipairs(paths) do
    local ok, img = pcall(Renderer.LoadImage, path)
    if ok and img then
      return { path = path, anim = "Idle", w = 96, h = 96, sprite = sprite(path, "Idle") }
    end
  end

  local full = m.fullDir
  if type(full) ~= "string" or full == "" then return false end
  local fixed = full:gsub("[/\\]Repentogon[/\\]mods[/\\]", "/mods/")
  local folders = fixed ~= full and { fixed, full } or { full }
  for _, folder in ipairs(folders) do
    local path = folder .. "/thumb.png"
    local s = sprite(path, "Big")
    local ok, w, h = pcall(function()
      local img = s:GetLayer(0):GetSpritesheet()
      return img:GetWidth(), img:GetHeight()
    end)
    if ok and w and h and w > 1 and h > 1 and w <= 2048 and h <= 2048 then
      return { path = path, anim = "Big", w = w, h = h, sprite = s }
    end
  end
  return false
end

function Thumbs.get(m)
  if cache[m.dir] == nil then cache[m.dir] = find(m) end
  return cache[m.dir]
end

-- Covers only come from tools/make_thumbs.py or a mod's own PNG thumb.png, so
-- most players have none: without any (our own doesn't count) the list drops
-- the cover column instead of showing a row of empty frames.
function Thumbs.any(mods)
  for _, m in ipairs(mods) do
    if not m.isSelf and Thumbs.get(m) then return true end
  end
  return false
end

return Thumbs
