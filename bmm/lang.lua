-- UI strings. Add a language by copying the `en` table.
local Lang = {}

local STRINGS = {
  en = {
    count = "%d/%d on",
    all_off = "all off!",
    filter = { "ALL", "ON", "OFF", "PINNED", "API", "CONTENT", "QOL", "VISUAL", "CHANGED", "BROKEN" },
    search_label = "SEARCH %d",
    sort_prefix = "S sort: ",
    sort = { "NAME", "ON FIRST", "CATEGORY" },
    cat = { API = "API", CONTENT = "CONTENT", QOL = "QOL", VISUAL = "VISUAL" },
    nothing_matches = "nothing matches the search",
    empty_filter = "no mods in this filter",
    no_mod = "no mod selected",
    local_mod = "local mod",
    workshop = "workshop %s",
    enabled = "ENABLED",
    disabled = "DISABLED",
    will_enable = "WILL BE ENABLED",
    will_disable = "WILL BE DISABLED",
    this_menu = "(this menu!)",
    needs = "needs: ",
    off_suffix = " (OFF)",
    press_d = "press D to enable them",
    applying = "APPLYING",
    applying_text = "%s: %d left. Press ENTER for each mod, ESC to stop.",
    profiles = "PROFILES",
    profile_name = "Profile %d",
    slot_empty = "%d. empty",
    slot = "%d. %s",
    n_on = "%d on",
    at_start = "as at game start",
    everything_off = "everything off",
    profile_hints = { "ENTER apply   S save here", "C clear   P / ESC close" },
    type_to_filter = "type to filter...",
    ctrl_edit = "CTRL to edit",
    hint_keys = "CTRL search  Q/E filter  B pin  P profiles",
    hint_pad = "LB/RB filter   LT/RT page   Y profiles",
    t_undone = "all changes undone",
    t_stopped = "stopped applying",
    t_pinned = "pinned %s",
    t_unpinned = "unpinned %s",
    t_no_deps = "no missing dependencies",
    t_nothing = "%s: nothing to change",
    t_clear_search = "clear the search first (CTRL, BACKSPACE)",
    t_saved = "saved %d mods to profile %d",
    t_empty_slot = "this slot is empty",
    t_applied = "%s: done",
    t_lang = "language: English",
    n_dependencies = "dependencies",
    n_profile = "profile %d",
  },
  ru = {
    count = "вкл %d/%d",
    all_off = "всё выкл!",
    filter = { "ВСЕ", "ВКЛ", "ВЫКЛ", "ЗАКРЕП.", "API", "КОНТЕНТ", "QOL", "ВИЗУАЛ", "ИЗМЕН.", "СЛОМАНО" },
    search_label = "ПОИСК %d",
    sort_prefix = "S сорт: ",
    sort = { "ИМЯ", "ВКЛ. СНАЧАЛА", "КАТЕГОРИЯ" },
    cat = { API = "API", CONTENT = "КОНТЕНТ", QOL = "QOL", VISUAL = "ВИЗУАЛ" },
    nothing_matches = "ничего не найдено",
    empty_filter = "в этом фильтре пусто",
    no_mod = "мод не выбран",
    local_mod = "локальный мод",
    workshop = "мастерская %s",
    enabled = "ВКЛЮЧЁН",
    disabled = "ВЫКЛЮЧЕН",
    will_enable = "БУДЕТ ВКЛЮЧЁН",
    will_disable = "БУДЕТ ВЫКЛЮЧЕН",
    this_menu = "(это меню!)",
    needs = "нужно: ",
    off_suffix = " (выкл)",
    press_d = "D - включить их",
    applying = "ПРИМЕНЯЮ",
    applying_text = "%s: осталось %d. ENTER на каждый мод, ESC - стоп.",
    profiles = "ПРОФИЛИ",
    profile_name = "Профиль %d",
    slot_empty = "%d. пусто",
    slot = "%d. %s",
    n_on = "вкл %d",
    at_start = "как при запуске",
    everything_off = "всё выключить",
    profile_hints = { "ENTER применить  S сохранить", "C очистить  P / ESC закрыть" },
    type_to_filter = "печатай для поиска...",
    ctrl_edit = "CTRL - изменить",
    hint_keys = "CTRL поиск  Q/E фильтр  B закреп  P профили",
    hint_pad = "LB/RB фильтр   LT/RT листать   Y профили",
    t_undone = "все изменения отменены",
    t_stopped = "применение остановлено",
    t_pinned = "закреплён: %s",
    t_unpinned = "откреплён: %s",
    t_no_deps = "все зависимости на месте",
    t_nothing = "%s: менять нечего",
    t_clear_search = "сначала очисти поиск (CTRL, BACKSPACE)",
    t_saved = "%d модов сохранено в профиль %d",
    t_empty_slot = "этот слот пуст",
    t_applied = "%s: готово",
    t_lang = "язык: русский",
    n_dependencies = "зависимости",
    n_profile = "профиль %d",
  },
}

Lang.ORDER = { "en", "ru" }
Lang.current = "en"

-- Game language from the options, falls back to English.
function Lang.detect()
  local ok, lang = pcall(function() return Options.Language end)
  if ok and type(lang) == "string" and STRINGS[lang:sub(1, 2):lower()] then
    return lang:sub(1, 2):lower()
  end
  return "en"
end

function Lang.set(code)
  Lang.current = STRINGS[code] and code or "en"
end

-- T("key") or T("key", fmt args...)
function Lang.T(key, ...)
  local v = STRINGS[Lang.current][key]
  if v == nil then v = STRINGS.en[key] end
  if select("#", ...) > 0 and type(v) == "string" then return v:format(...) end
  return v
end

return Lang
