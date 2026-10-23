-- Small helpers shared by the other modules.
local U = {}

-- Plain byte-wise string compare, same as std::string operator< in the game
-- (Lua's < goes through strcoll, which we don't want to depend on).
function U.byteLess(a, b)
  local la, lb = #a, #b
  for i = 1, math.min(la, lb) do
    local ca, cb = a:byte(i), b:byte(i)
    if ca ~= cb then return ca < cb end
  end
  return la < lb
end

-- ASCII-only lowercase, matches REPENTOGON's stringlower().
function U.lower(s)
  return (s:gsub("%u", function(c) return string.char(c:byte() + 32) end))
end

function U.trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Workshop BBCode -> readable plain text.
function U.cleanDescription(s)
  if not s or s == "" then return "" end
  s = s:gsub("\r", "")
  s = s:gsub("%[img%].-%[/img%]", "")
  s = s:gsub("%[previewyoutube=.-%]%[/previewyoutube%]", "")
  s = s:gsub("%[url=[^%]]*%](.-)%[/url%]", "%1")
  s = s:gsub("%[%*%]", "\n- ")
  s = s:gsub("%[h%d%](.-)%[/h%d%]", "%1\n")
  s = s:gsub("%[/?[%a%d]+[^%]]*%]", "")
  s = s:gsub("https?://%S+", "")
  s = s:gsub("&quot;", "\""):gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&#39;", "'")
  -- typographic punctuation -> ASCII, so plain English stays in the small pixel font
  local PUNCT = { ["\226\128\152"] = "'", ["\226\128\153"] = "'", ["\226\128\156"] = "\"", ["\226\128\157"] = "\"",
    ["\226\128\147"] = "-", ["\226\128\148"] = "-", ["\226\128\166"] = "...", ["\226\128\162"] = "-",
    ["\194\160"] = " ", ["\194\183"] = "-" }
  for k, v in pairs(PUNCT) do s = s:gsub(k, v) end
  s = s:gsub("[ \t]+", " ")
  s = s:gsub("\n%s*\n+", "\n")
  s = s:gsub("%-%-%-%-+", "")
  return U.trim(s)
end

-- Splits a UTF-8 string into characters (keeps multi-byte sequences intact).
local function utf8chars(s)
  local t = {}
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do t[#t + 1] = ch end
  return t
end

-- Cuts text to fit maxW (in already-scaled pixels), appending "..".
function U.fit(font, text, scale, maxW)
  if font:GetStringWidthUTF8(text) * scale <= maxW then return text end
  local chars = utf8chars(text)
  local lo = #chars
  while lo > 0 do
    local s = table.concat(chars, "", 1, lo) .. ".."
    if font:GetStringWidthUTF8(s) * scale <= maxW then return s end
    lo = lo - 1
  end
  return ".."
end

-- Word wrap. Returns an array of lines; respects explicit newlines.
function U.wrap(font, text, scale, maxW, maxLines)
  local lines = {}
  for para in (text .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      local try = line == "" and word or (line .. " " .. word)
      if font:GetStringWidthUTF8(try) * scale <= maxW then
        line = try
      else
        if line ~= "" then lines[#lines + 1] = line end
        line = U.fit(font, word, scale, maxW)
      end
      if maxLines and #lines >= maxLines then return lines, true end
    end
    if line ~= "" then lines[#lines + 1] = line end
    if maxLines and #lines >= maxLines then return lines, true end
  end
  return lines, false
end

function U.clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

function U.log(msg)
  Isaac.DebugString("[BetterModsMenu] " .. tostring(msg))
end

return U
