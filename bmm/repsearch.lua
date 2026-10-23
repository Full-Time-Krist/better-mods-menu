-- Frame-exact mirror of REPENTOGON's mods menu search + undo
-- (repentogon/Patches/ModsMenuStuff.cpp, Menu_Mods::Render).
-- REPENTOGON reads raw keyboard keys we can't mask, and its search string
-- filters the list that SetSelectedElement indexes into, so we must track it.
local U = include("bmm.util")

local KEY_SPACE, KEY_ESCAPE, KEY_ENTER, KEY_BACKSPACE = 32, 256, 257, 259
local KEY_LEFT_CONTROL = 341
local KEY_DELAY = 20
local MIN_MODS = 15

local R = {
  searching = false,
  str = "",
  last = {},          -- lastKeyPressTimeMap
  font = nil,
}

local function last(k) return R.last[k] or 0 end

local function pressed(k) return Input.IsButtonPressed(k, 0) end
local function triggered(k) return Input.IsButtonTriggered(k, 0) end

local function isTypable(i)
  return (i >= 48 and i <= 57) or (i >= 65 and i <= 90) or (i >= 97 and i <= 122) or i == KEY_SPACE
end

-- Call once per frame while the mods menu is the active menu.
-- Returns events: { changed = bool, undo = bool, opened = bool, closed = bool }
function R.step(numMods, gamepadMode)
  local ev = {}
  local t = Isaac.GetFrameCount()
  local did = false
  if R.searching then
    if numMods > MIN_MODS then
      for i = 32, 347 do
        if pressed(i) then
          if (t - last(i)) >= KEY_DELAY then
            if i == KEY_LEFT_CONTROL or i == KEY_ENTER or i == KEY_ESCAPE then
              R.searching = false
              R.last[i] = t
              ev.closed = true
              break
            elseif i == KEY_BACKSPACE then
              if #R.str > 0 then
                R.str = R.str:sub(1, -2)
                did = true
              end
            elseif R.font:GetStringWidth(R.str) < 225 and isTypable(i) then
              R.str = R.str .. U.lower(string.char(i))
              did = true
            end
            if did then
              if last(i) > 0 then
                R.last[i] = t - math.floor(KEY_DELAY * 0.7)
              else
                R.last[i] = t
              end
            end
          end
        else
          R.last[i] = 0
        end
      end
    end
  elseif numMods > MIN_MODS and triggered(KEY_LEFT_CONTROL) and (t - last(KEY_LEFT_CONTROL)) > KEY_DELAY then
    R.searching = true
    R.last[KEY_LEFT_CONTROL] = t
    ev.opened = true
  elseif not gamepadMode and triggered(KEY_BACKSPACE) and (t - last(KEY_BACKSPACE)) > KEY_DELAY then
    ev.undo = true
  end
  ev.changed = did
  return ev
end

-- REPENTOGON clears "searching" whenever another menu is active.
function R.leftMenu()
  R.searching = false
end

function R.init(font)
  R.font = font
end

return R
