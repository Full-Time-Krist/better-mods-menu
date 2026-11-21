local t = ...
local function fixture(images)
  local env = t.environment()
  local replacements = 0
  env.Renderer = { LoadImage = function(path) return images[path] end }
  env.Sprite = function()
    local path
    return {
      Load = function() end, SetFrame = function() end,
      ReplaceSpritesheet = function(_, _, p) path = p; replacements = replacements + 1 end,
      GetLayer = function() return { GetSpritesheet = function()
        local size = images[path] or { 1, 1 }
        return { GetWidth = function() return size[1] end, GetHeight = function() return size[2] end }
      end } end,
    }
  end
  return env.include("bmm.thumbs"), function() return replacements end
end
local root = "gfx/ui/bettermods/thumbs/"
t.test("Workshop ID preview wins over folder and local previews", function()
  local thumbs = fixture({ [root .. "workshop/123456789.png"] = {96,96}, [root .. "example.png"] = {96,96} })
  local got = thumbs.get({ dir = "example", id = "123456789", fullDir = "/mods/example" })
  t.eq(got.path, root .. "workshop/123456789.png")
end)
t.test("folder preview remains available when Steam cover is missing", function()
  local thumbs = fixture({ [root .. "example.png"] = {96,96} })
  t.eq(thumbs.get({ dir = "example", id = "123456789" }).path, root .. "example.png")
end)
t.test("local PNG path resolves through REPENTOGON launcher directory", function()
  local thumbs = fixture({ ["S:/game/mods/example/thumb.png"] = {512,256} })
  local got = thumbs.get({ dir = "example", fullDir = "S:/game/Repentogon/mods/example" })
  t.eq(got.path, "S:/game/mods/example/thumb.png")
  t.eq(got.w, 512)
  t.eq(got.h, 256)
end)
t.test("missing images return false instead of a broken sprite", function()
  local thumbs = fixture({})
  t.eq(thumbs.get({ dir = "example", id = "123456789" }), false)
end)
t.test("each mod keeps its own texture without reloading it every frame", function()
  local thumbs, replacements = fixture({ [root .. "a.png"] = {96,96}, [root .. "b.png"] = {96,96} })
  local a, b = {dir="a"}, {dir="b"}
  local first = thumbs.get(a)
  local second = thumbs.get(b)
  assert(first.sprite ~= second.sprite)
  t.eq(thumbs.get(a), first)
  t.eq(replacements(), 2)
end)
t.test("our own cover alone doesn't make a cover column", function()
  local thumbs = fixture({ [root .. "better-mods-menu.png"] = {96,96} })
  t.eq(thumbs.any({ { dir = "better-mods-menu", isSelf = true }, { dir = "other" } }), false)
  local thumbs2 = fixture({ [root .. "other.png"] = {96,96} })
  t.eq(thumbs2.any({ { dir = "better-mods-menu", isSelf = true }, { dir = "other" } }), true)
end)
