-- Rendering. Everything is drawn with the vanilla mods-menu sprites
-- (ModsMenu.anm2 paper pieces, cursor, TAB note, REPENTOGON's search bar and
-- undo note) plus a few hand-drawn pieces in the same style, so the menu keeps
-- the original paper look.
local U = include("bmm.util")
local Model, Lang -- shared instances from main.lua (include() re-runs files, so no own copies)

local UI = {}

local ICON = { box = 0, box_on = 1, star = 2, warn = 3, dot = 4, glass = 5, arrow = 6, box_x = 7 }

UI.ROWS = 9
UI.ROW_H = 16
UI.NUM_FILTERS = 10
UI.NUM_SORTS = 3

-- Layout, relative to the mods page anchor (screen 39,15 when the page is at rest).
local L = {
  sprite = Vector(166, 62),     -- where vanilla renders ModsMenu.anm2
  rowX = 58, rowY = 66,         -- first row (checkbox top-left)
  nameX = 76,
  tagRightX = 262,
  scrollX = 268,
  headerY = 47,
  countX = 58, countY = 30,
  card = Vector(273, 105),      -- top-left of the info card paper (166x146)
  cardPad = 10,
  cardW = 166, cardH = 146,
  thumb = 48,                   -- 96px previews drawn at half scale (menu renders at 2x)
  undo = Vector(371, 81),       -- REPENTOGON's undo note, scaled down, clear of the list
  undoScale = Vector(0.75, 0.75),
  bar = Vector(160, 225),
  barText = Vector(50, 225),
}

-- solid inks: translucent black doubles up where glyphs overlap and looks "highlighted"
local INK = KColor(0, 0, 0, 1)
local SOFT = KColor(0.30, 0.28, 0.29, 1)
local FADED = KColor(0.53, 0.50, 0.51, 1)
local RED = KColor(0.55, 0.05, 0.05, 1)
local GREEN = KColor(0.05, 0.33, 0.12, 1)
local WALL = KColor(0.80, 0.748, 0.733, 1)   -- main menu wall texture colour

local SMALL_LINE = 8
local STAMP = 0.7   -- menu font scale for small labels (category stamps, sort)

local spr = {}
local rowNameX = 0
local fonts = {}

local function T(...) return Lang.T(...) end

local function loadSprite(path, anim)
  local s = Sprite()
  s:Load(path, true)
  if anim then s:SetFrame(anim, 0) end
  return s
end

function UI.init(model, lang)
  Model, Lang = model, lang
  spr.menu = loadSprite("gfx/ui/main menu/ModsMenu.anm2", "Main")
  spr.rgon = loadSprite("gfx/ui/modsmenupentogon.anm2", "SearchBar")
  spr.undo = loadSprite("gfx/ui/modsmenupentogon.anm2", "UndoPop")
  spr.icons = loadSprite("gfx/ui/bettermods/icons.anm2", "Icon")
  spr.pixel = loadSprite("gfx/ui/bettermods/pixel.anm2", "Idle")
  spr.thumb = loadSprite("gfx/ui/bettermods/thumb.anm2", "Idle")
  spr.card = loadSprite("gfx/ui/bettermods/card.anm2", "Idle")
  fonts.main = Font()
  fonts.main:Load("font/teammeatex/teammeatex10.fnt")
  fonts.small = Font()
  fonts.small:Load("font/luamini.fnt")
  UI.font = fonts.main
end

local function withAlpha(c, a)
  return KColor(c.Red, c.Green, c.Blue, c.Alpha * a)
end

-- luamini has no Cyrillic etc.: such strings use the menu font, shrunk to fit
local function resolve(str, font, scale)
  font = font or fonts.main
  scale = scale or 1
  if font == fonts.small and str:find("[\128-\255]") then
    return fonts.main, scale * 0.72, -2
  end
  return font, scale, 0
end

local function width(str, scale, font)
  local f, s = resolve(str, font, scale)
  return f:GetStringWidthUTF8(str) * s
end

local function text(str, x, y, color, scale, font)
  local f, s, dy = resolve(str, font, scale)
  f:DrawStringScaledUTF8(str, x, y + dy, s, s, color, 0, false)
end

local function textRight(str, x, y, color, scale, font)
  text(str, x - width(str, scale, font), y, color, scale, font)
end

-- fit/wrap with the same font fallback as text()
local function fit(str, scale, font, maxW)
  local f, s = resolve(str, font, scale)
  return U.fit(f, str, s, maxW)
end

local function wrap(str, scale, font, maxW, maxLines)
  local f, s = resolve(str, font, scale)
  return U.wrap(f, str, s, maxW, maxLines)
end

local function rect(x, y, w, h, color)
  spr.pixel.Scale = Vector(w, h)
  spr.pixel.Color = Color(color.Red, color.Green, color.Blue, color.Alpha)
  spr.pixel:Render(Vector(x, y))
end

local function icon(i, x, y, alpha)
  spr.icons:SetFrame("Icon", i)
  spr.icons.Color = Color(1, 1, 1, alpha or 1)
  spr.icons:Render(Vector(x, y))
end

-- Thumbnails, first match wins:
--  1. resources/gfx/ui/bettermods/thumbs/<dir>.png, made by tools/make_thumbs.py (96x96)
--  2. the mod's own thumb.png, read from its folder by absolute path (any size,
--     measured once). Sprites take absolute paths, Renderer.LoadImage does not.
-- Result per mod: { path, anim, w, h } or false.
local thumbCache = {}

-- REPENTOGON reports mods as "<game>\Repentogon/mods/<dir>" when started from its
-- launcher, but they live in "<game>\mods\<dir>"
local function folderCandidates(m)
  local full = m.fullDir
  if type(full) ~= "string" or full == "" then return {} end
  local fixed = full:gsub("[/\\]Repentogon[/\\]mods[/\\]", "/mods/")
  if fixed ~= full then return { fixed .. "/thumb.png", full .. "/thumb.png" } end
  return { full .. "/thumb.png" }
end

local function findThumb(m)
  local key = m.dir:gsub("[^%w%-_]", "_")
  local gen = "gfx/ui/bettermods/thumbs/" .. key .. ".png"
  if pcall(Renderer.LoadImage, gen) then
    return { path = gen, anim = "Idle", w = 96, h = 96 }
  end
  for _, path in ipairs(folderCandidates(m)) do
    spr.thumb:ReplaceSpritesheet(0, path, true)
    local ok, w, h = pcall(function()
      local img = spr.thumb:GetLayer(0):GetSpritesheet()
      return img:GetWidth(), img:GetHeight()
    end)
    -- 2048 is the "Big" frame; a JPEG renamed to .png (common on the Workshop) doesn't load
    if ok and w and w > 1 and h > 1 and w <= 2048 and h <= 2048 then
      return { path = path, anim = "Big", w = w, h = h }
    end
  end
  return false
end

local function thumbFor(S, m)
  if thumbCache[m.dir] == nil then
    S.thumbLoaded = nil -- findThumb swaps the sheet while probing
    thumbCache[m.dir] = findThumb(m)
  end
  return thumbCache[m.dir]
end

-- REPENTOGON flips the note's text crop by 64px when mods are globally on
local function modsGloballyEnabled()
  local ok, crop = pcall(function() return ModsMenu.GetSprite():GetLayer(12):GetCropOffset() end)
  if ok and crop then return crop.Y > 32, crop end
  return true, nil
end
UI.modsGloballyEnabled = modsGloballyEnabled

-------------------------------------------------------------------- paper

-- piece k (0-based) spans P.Y + 32k .. P.Y + 32(k+1)
local function pieces(P, A)
  local k = 0
  while P.Y + 32 * k < A.Y + 250 do
    spr.menu:SetFrame("Piece" .. tostring(k % 5 + 1), 0)
    spr.menu:RenderLayer(0, Vector(P.X, P.Y + 32 * (k + 1)))
    k = k + 1
  end
end

local function drawPaper(S, alpha)
  local A = S.A
  local P = A + L.sprite
  spr.menu.Color = Color(1, 1, 1, alpha)
  -- vanilla scrolls the whole scene (sketches, old page) with its cursor and
  -- ours stays put: cover the screen with the plain wall (the anm2's own wall
  -- layer is hidden), then lay a static copy of the sketches on top
  local sw, sh = Isaac.GetScreenWidth(), Isaac.GetScreenHeight()
  rect(A.X - 80, A.Y - 15 - sh, sw + 80, sh * 3, WALL)
  spr.menu:SetFrame("Main", 0)
  for layer = 2, 10 do spr.menu:RenderLayer(layer, P) end
  -- REPENTOGON's own undo note sticks out past the paper; ours sits elsewhere
  rect(A.X + 280, A.Y + 30, 110, 112, WALL)
  -- below the search bar (only visible on tall windows): REPENTOGON pins its
  -- own bar to the screen bottom and long names overflow the paper there
  rect(A.X + 10, A.Y + 250, 400, 900, WALL)
  -- the sheet itself stays put (its middle is a flat colour, so moving it
  -- would only shift the torn edges); the rows slide over it with S.camY
  pieces(P, A)
end

-- the page top stays put; rows slide under it
local function drawPaperHeader(A, alpha)
  spr.menu.Color = Color(1, 1, 1, alpha)
  spr.menu:SetFrame("Main", 0)
  spr.menu:RenderLayer(0, A + L.sprite)
end

local function drawCursor(x, y, alpha)
  spr.menu:SetFrame("Cursor", 0)
  spr.menu.Color = Color(1, 1, 1, alpha)
  spr.menu:RenderLayer(0, Vector(x, y))
end

-------------------------------------------------------------------- list

local function drawRow(S, m, x, y, a)
  local on = m.enabled
  -- the selection is shown by the vanilla arrow only, like the original menu
  local ink = on and INK or FADED

  icon(on and ICON.box_on or ICON.box, x, y - 1, a * (on and 1 or 0.7))

  local nx = rowNameX
  if S.favs[m.dir] then
    icon(ICON.star, nx - 1, y - 1, a * 0.85)
    nx = nx + 11
  end

  -- right side: category stamp + warnings
  local tag = T("cat")[m.category] or ""
  local rx = S.A.X + L.tagRightX
  textRight(tag, rx, y + 3, withAlpha(on and SOFT or FADED, a), STAMP)
  local maxX = rx - width(tag, STAMP) - 6

  if m.enabled and #Model.missingDeps(m) > 0 then
    icon(ICON.warn, maxX - 13, y, a)
    maxX = maxX - 15
  end
  if m.enabled ~= m.enabledAtLoad then
    -- pending change marker: green = will be added, red = will be removed
    text(m.enabled and "+" or "-", maxX - 7, y + 1, withAlpha(m.enabled and GREEN or RED, a), 1)
    maxX = maxX - 10
  end

  text(U.fit(fonts.main, m.name, 0.9, maxX - nx), nx, y + 1, withAlpha(ink, a), 0.9)
end

local function drawHeader(S, alpha)
  local A = S.A
  local x = A.X + L.rowX
  drawPaperHeader(A, alpha)
  -- counters next to the MODS title, filter + sort under it
  local on, total = Model.countOn(), #Model.mods
  if modsGloballyEnabled() then
    text(T("count", on, total), A.X + L.countX, A.Y + L.countY, withAlpha(SOFT, alpha), 0.75)
  else
    text(T("all_off"), A.X + L.countX, A.Y + L.countY, withAlpha(RED, alpha), 0.75)
  end
  local fy = A.Y + L.headerY
  local flabel = S.search ~= "" and T("search_label", #S.list)
    or ("< %s %d >"):format(T("filter")[S.filter], #S.list)
  text(flabel, x + 2, fy, withAlpha(INK, alpha), 0.75)
  local sx = x + 10 + width(flabel, 0.75)
  text(fit(T("sort_prefix") .. T("sort")[S.sort], STAMP, fonts.main, A.X + L.tagRightX - sx), sx, fy + 1,
    withAlpha(SOFT, alpha), STAMP)
end

-- camera: eases toward the scroll target, in pixels
local function updateCamera(S)
  local target = S.scroll * UI.ROW_H
  local cam = S.camY or target
  local d = target - cam
  if math.abs(d) < 0.5 or math.abs(d) > UI.ROWS * UI.ROW_H * 3 then
    cam = target   -- settled, or a jump too far to be worth animating
  else
    cam = cam + d * 0.25
  end
  S.camY = cam
end

local FADE = 10 -- rows fade out over this many pixels at the window edges

local function drawRows(S, alpha)
  local A = S.A
  local x = A.X + L.rowX
  rowNameX = A.X + L.nameX

  if not modsGloballyEnabled() then
    -- everything is switched off with TAB: the list still works, but fade it
    alpha = alpha * 0.45
  end

  local list = S.list
  if #list == 0 then
    text(S.search ~= "" and T("nothing_matches") or T("empty_filter"), x + 18, A.Y + L.rowY + 20,
      withAlpha(FADED, alpha), 0.9)
    return
  end

  local cam = S.camY
  local top = A.Y + L.rowY
  local bottom = top + UI.ROWS * UI.ROW_H
  local first = math.max(1, math.floor(cam / UI.ROW_H))
  for i = first, math.min(#list, first + UI.ROWS + 1) do
    local y = top + (i - 1) * UI.ROW_H - cam
    local a = math.min(1, (y - top + FADE) / FADE, (bottom - y) / FADE)
    if a > 0.02 then
      drawRow(S, list[i], x, y, alpha * a)
      if i == S.cursor then drawCursor(x - 1, y + 6, alpha * a) end
    end
  end

  -- scrollbar: thin pencil line with a knob
  if #list > UI.ROWS then
    local h = UI.ROWS * UI.ROW_H - 4
    local bx = A.X + L.scrollX
    rect(bx, top, 1, h, withAlpha(FADED, alpha))
    local kh = math.max(8, h * UI.ROWS / #list)
    local ky = top + (h - kh) * U.clamp(cam / (math.max(1, #list - UI.ROWS) * UI.ROW_H), 0, 1)
    rect(bx - 1, ky, 3, kh, withAlpha(SOFT, alpha))
  end
end

-------------------------------------------------------------------- notes

local function drawTabNote(S, alpha)
  -- the vanilla "PRESS TAB TO DISABLE MODS" note, re-rendered above our paper
  local P = S.A + L.sprite
  local _, crop = modsGloballyEnabled()
  spr.menu:SetFrame("Main", 0)
  spr.menu.Color = Color(1, 1, 1, alpha)
  if crop then
    pcall(function() spr.menu:GetLayer(12):SetCropOffset(crop) end)
  end
  spr.menu:RenderLayer(11, P)
  spr.menu:RenderLayer(12, P)
  if not S.gamepad then spr.menu:RenderLayer(13, P) end
end

local function drawUndoNote(S, alpha)
  spr.undo:SetFrame("UndoPop", S.gamepad and 1 or 0)
  spr.undo.Color = Color(1, 1, 1, alpha)
  spr.undo.Scale = L.undoScale
  spr.undo:Render(S.A + L.undo)
end

-- Straight note paper; returns the writable box (everything stays inside it).
local function cardPaper(S, alpha)
  local pos = S.A + L.card
  spr.card.Color = Color(1, 1, 1, alpha)
  spr.card:Render(pos)
  local p = L.cardPad
  return pos.X + p, pos.Y + p - 1, L.cardW - 2 * p, pos.Y + L.cardH - p - 2
end

local function drawThumb(S, m, x, y, alpha)
  local t = thumbFor(S, m)
  if not t then return false end
  if S.thumbLoaded ~= t.path then
    spr.thumb:ReplaceSpritesheet(0, t.path, true)
    spr.thumb:SetFrame(t.anim, 0)
    S.thumbLoaded = t.path
  end
  -- fit into the n x n box, centred, keeping the aspect ratio
  local n = L.thumb
  local k = n / math.max(t.w, t.h)
  local w, h = math.floor(t.w * k + 0.5), math.floor(t.h * k + 0.5)
  local px, py = x + (n - w) // 2, y + (n - h) // 2
  spr.thumb.Scale = Vector(k, k)
  spr.thumb.Color = Color(1, 1, 1, alpha)
  -- the "Big" frame is larger than the image: cut the rest off
  local frame = t.anim == "Big" and 2048 or 96
  spr.thumb:Render(Vector(px, py), Vector(0, 0), Vector(frame - t.w, frame - t.h))
  local c = withAlpha(INK, alpha)
  rect(px - 1, py - 1, w + 2, 1, c)
  rect(px - 1, py + h, w + 2, 1, c)
  rect(px - 1, py - 1, 1, h + 2, c)
  rect(px + w, py - 1, 1, h + 2, c)
  return true
end

local function drawInfoCard(S, alpha)
  local x, y, w, bottom = cardPaper(S, alpha)
  local m = S.list[S.cursor]

  if S.applying then
    text(T("applying"), x, y, withAlpha(RED, alpha), 1)
    y = y + 14
    local msg = T("applying_text", S.applying.name, #S.applying.plan)
    for _, line in ipairs(wrap(msg, 1, fonts.small, w, 6)) do
      text(line, x, y, withAlpha(INK, alpha), 1, fonts.small)
      y = y + SMALL_LINE + 1
    end
    return
  end
  if not m then
    text(T("no_mod"), x, y, withAlpha(FADED, alpha), 0.9)
    return
  end

  -- header: preview, title, version line, category line
  local tx = x
  local hasThumb = drawThumb(S, m, x + 1, y + 1, alpha)
  if hasThumb then tx = x + L.thumb + 6 end
  local tw = x + w - tx
  local ty = y
  for _, line in ipairs(U.wrap(fonts.main, m.name, 0.9, tw, 2)) do
    text(line, tx, ty, withAlpha(INK, alpha), 0.9)
    ty = ty + 11
  end
  local meta = (m.version ~= "" and ("v" .. m.version .. "  ") or "")
    .. (m.isWorkshop and T("workshop", m.id) or T("local_mod"))
  text(fit(meta, 1, fonts.small, tw), tx, ty + 1, withAlpha(SOFT, alpha), 1, fonts.small)
  ty = ty + SMALL_LINE + 1
  local cat = (T("cat")[m.category] or m.category)
    .. (#m.tags > 0 and (": " .. table.concat(m.tags, ", ", 1, math.min(#m.tags, 3))) or "")
  text(fit(cat, 1, fonts.small, tw), tx, ty + 1, withAlpha(SOFT, alpha), 1, fonts.small)
  y = math.max(ty + SMALL_LINE + 4, hasThumb and (y + L.thumb + 5) or 0)

  -- status line
  local status, color
  if m.enabled == m.enabledAtLoad then
    status, color = m.enabled and T("enabled") or T("disabled"), m.enabled and GREEN or FADED
  else
    status, color = m.enabled and T("will_enable") or T("will_disable"), m.enabled and GREEN or RED
  end
  text(fit(status, 0.75, fonts.main, w), x, y, withAlpha(color, alpha), 0.75)
  if m.isSelf and not m.enabled then
    textRight(T("this_menu"), x + w, y + 1, withAlpha(RED, alpha), 1, fonts.small)
  end
  y = y + 11

  -- dependencies
  if #m.deps > 0 then
    local parts, missing = {}, false
    for _, dir in ipairs(m.deps) do
      local d = Model.byDir[dir]
      if d then
        parts[#parts + 1] = d.name .. (d.enabled and "" or T("off_suffix"))
        if not d.enabled then missing = true end
      end
    end
    local warn = missing and m.enabled
    for _, line in ipairs(wrap(T("needs") .. table.concat(parts, ", "), 1, fonts.small, w, 2)) do
      text(line, x, y, withAlpha(warn and RED or SOFT, alpha), 1, fonts.small)
      y = y + SMALL_LINE + 1
    end
    if warn then
      text(fit(T("press_d"), 1, fonts.small, w), x, y, withAlpha(RED, alpha), 1, fonts.small)
      y = y + SMALL_LINE + 1
    end
  end

  -- description, clipped to the paper ([ / ] scroll it)
  y = y + 2
  local maxLines = math.floor((bottom - y) / SMALL_LINE)
  S.descCut = false
  if maxLines > 0 and m.desc ~= "" then
    local lines, cut = wrap(m.desc, 1, fonts.small, w, maxLines + S.descScroll + 1)
    local last = math.min(#lines, maxLines + S.descScroll)
    for i = 1 + S.descScroll, last do
      text(lines[i], x, y, withAlpha(SOFT, alpha), 1, fonts.small)
      y = y + SMALL_LINE
    end
    S.descCut = cut or #lines > last
  end
end

local function drawProfilesCard(S, alpha)
  local x, y, w, bottom = cardPaper(S, alpha)
  text(T("profiles"), x, y, withAlpha(INK, alpha), 1)
  y = y + 15
  for i, row in ipairs(S.profileRows) do
    if i == S.profileCursor then drawCursor(x + 8, y + 5, alpha) end
    local c = row.empty and FADED or INK
    local detail = row.detail or ""
    local dw = detail ~= "" and (width(detail, 1, fonts.small) + 4) or 0
    text(fit(row.label, 0.75, fonts.main, w - 12 - dw), x + 12, y, withAlpha(c, alpha), 0.75)
    if detail ~= "" then
      textRight(detail, x + w, y + 1, withAlpha(SOFT, alpha), 1, fonts.small)
    end
    y = y + 12
  end
  y = math.max(y + 3, bottom - 2 * (SMALL_LINE + 1))
  for _, line in ipairs(T("profile_hints")) do
    text(fit(line, 1, fonts.small, w), x, y, withAlpha(SOFT, alpha), 1, fonts.small)
    y = y + SMALL_LINE + 1
  end
end

-------------------------------------------------------------------- bottom bar

local function drawBar(S, alpha)
  spr.rgon:SetFrame("SearchBar", 0)
  spr.rgon.Color = Color(1, 1, 1, alpha)
  spr.rgon:Render(S.A + L.bar)
  local p = S.A + L.barText
  local maxW = 214  -- the info card covers the bar's right end
  if S.searching or S.search ~= "" then
    icon(ICON.glass, p.X - 14, p.Y, alpha * (S.searching and 1 or 0.5))
    local str = S.search
    text(str == "" and T("type_to_filter") or str, p.X, p.Y, withAlpha(S.searching and INK or SOFT, alpha), 1)
    if S.searching and (Isaac.GetFrameCount() // 20) % 2 == 0 then
      text("|", p.X + width(str), p.Y, withAlpha(INK, alpha), 1)
    end
    if not S.searching then
      textRight(T("ctrl_edit"), p.X + maxW, p.Y + 1, withAlpha(SOFT, alpha), 0.75)
    end
  elseif S.toast and S.toast.until_ > Isaac.GetFrameCount() then
    text(fit(S.toast.text, 0.9, fonts.main, maxW), p.X, p.Y, withAlpha(S.toast.color or INK, alpha), 0.9)
  else
    local hint = S.gamepad and T("hint_pad") or T("hint_keys")
    text(fit(hint, 0.75, fonts.main, maxW + 8), p.X - 8, p.Y + 1, withAlpha(SOFT, alpha), 0.75)
  end
end

-------------------------------------------------------------------- entry

function UI.draw(S, alpha)
  updateCamera(S)
  drawPaper(S, alpha)
  drawRows(S, alpha)
  drawHeader(S, alpha)
  drawTabNote(S, alpha)
  drawUndoNote(S, alpha)
  drawBar(S, alpha)
  -- the card lies on top of the bar's right end, like the vanilla notes do
  if S.panel == "profiles" then
    drawProfilesCard(S, alpha)
  else
    drawInfoCard(S, alpha)
  end
end

-- Debug overlay (F9): the list exactly as REPENTOGON sees it, to verify the mapping.
function UI.drawDebug(S, view, vanillaSel)
  local x, y = 2, 2
  text(("vanilla sel %d  search '%s'  dirty %s"):format(vanillaSel, S.search, tostring(S.dirty)), x, y, RED, 1, fonts.small)
  for i, m in ipairs(view) do
    if i > 26 then break end
    text(("%s%d.%s %s"):format(i - 1 == vanillaSel and ">" or " ", i, m.name, m.enabled and "ON" or "off"), x, y + i * 9,
      RED, 1, fonts.small)
  end
end

return UI
