-- tokeer.lua — Tokeer auto-launcher integration for Denuvo-protected games.
--
-- Faithful Lua port of tokeer_launcher.py. Some Denuvo titles must launch through
-- tokeer_launcher.exe; this sets the per-user localconfig.vdf LaunchOptions to
-- '"<launcher>" %command%'. The VDF editor uses brace-counting to target the
-- exact appid block (robust vs the Python lazy-regex). Writes require Steam
-- closed. list/check are read-only. On-machine-verified for the file bits.

local cjson       = require("json")
local m_utils     = require("utils")
local fs          = require("fs")
local logger      = require("plugin_logger")
local steam_utils = require("steam_utils")
local st          = require("st_util")

local M = {}

-- appid -> { exe (relative), name } (from Devuvo.ps1 2026-05)
local TOKEER_GAMES = {
    [3357650] = { exe = "tokeer_launcher.exe", name = "Pragmata" },
    [3764200] = { exe = "tokeer_launcher.exe", name = "Resident Evil Requiem" },
    [2852190] = { exe = "tokeer_launcher.exe", name = "Monster Hunter Stories 3: Twisted Reflection" },
    [629820]  = { exe = "tokeer_launcher.exe", name = "Maneater" },
    [1570010] = { exe = "tokeer_launcher.exe", name = "FAR: Changing Tides" },
    [493340]  = { exe = "tokeer_launcher.exe", name = "Planet Coaster" },
    [3321460] = { exe = "tokeer_launcher.exe", name = "Crimson Desert" },
    [637100]  = { exe = "tokeer_launcher.exe", name = "Sonic Forces" },
    [2688950] = { exe = "tokeer_launcher.exe", name = "Planet Coaster 2" },
    [2358720] = { exe = "tokeer_launcher.exe", name = "Black Myth: Wukong" },
    [3489700] = { exe = "tokeer_launcher.exe", name = "Stellar Blade" },
    [287700]  = { exe = "tokeer_launcher.exe", name = "METAL GEAR SOLID V: THE PHANTOM PAIN" },
    [312660]  = { exe = "tokeer_launcher.exe", name = "Sniper Elite 4" },
    [594570]  = { exe = "tokeer_launcher.exe", name = "Total War: WARHAMMER II" },
    [626690]  = { exe = "tokeer_launcher.exe", name = "Sword Art Online: Fatal Bullet" },
    [668580]  = { exe = "tokeer_launcher.exe", name = "Atomic Heart" },
    [990080]  = { exe = "tokeer_launcher.exe", name = "Hogwarts Legacy" },
    [1029690] = { exe = "tokeer_launcher.exe", name = "Sniper Elite 5" },
    [1142710] = { exe = "tokeer_launcher.exe", name = "Total War: WARHAMMER III" },
    [1237320] = { exe = "tokeer_launcher.exe", name = "Sonic Frontiers" },
    [1413480] = { exe = "tokeer_launcher.exe", name = "Shin Megami Tensei III Nocturne HD Remaster" },
    [1687950] = { exe = "tokeer_launcher.exe", name = "Persona 5 Royal" },
    [1693980] = { exe = "tokeer_launcher.exe", name = "Dead Space" },
    [1844380] = { exe = "tokeer_launcher.exe", name = "Warhammer Age of Sigmar: Realms of Ruin" },
    [1971870] = { exe = "tokeer_launcher.exe", name = "Mortal Kombat 1" },
    [2161700] = { exe = "tokeer_launcher.exe", name = "Persona 3 Reload" },
    [2375550] = { exe = "runtime\\media\\tokeer_launcher.exe", name = "Like a Dragon Gaiden: The Man Who Erased His Name" },
    [2513280] = { exe = "tokeer_launcher.exe", name = "SONIC X SHADOW GENERATIONS" },
    [3061810] = { exe = "runtime\\media\\tokeer_launcher.exe", name = "Like a Dragon: Pirate Yakuza in Hawaii" },
    [3717070] = { exe = "tokeer_launcher.exe", name = "WWE 2K26" },
    [1364780] = { exe = "tokeer_launcher.exe", name = "Street Fighter 6" },
    [3059520] = { exe = "tokeer_launcher.exe", name = "F1 25" },
}

local function localconfig_path(account_id32)
    local base = steam_utils.detect_steam_install_path()
    if not base or base == "" then return "" end
    return fs.join(base, "userdata", tostring(account_id32), "config", "localconfig.vdf")
end

local function find_game_install_dir(appid)
    local r = steam_utils.get_game_install_path_response(appid)
    if r.success and r.installPath and fs.is_directory(r.installPath) then return r.installPath end
    return ""
end

local function find_launcher_exe(install_dir, relative_exe)
    if install_dir == "" or not fs.is_directory(install_dir) then return "" end
    local hinted = fs.join(install_dir, relative_exe)
    if fs.is_file(hinted) then return hinted end
    local target = fs.filename(relative_exe):lower()
    for _, e in ipairs(fs.list_recursive(install_dir) or {}) do
        if e.is_file and (e.depth == nil or e.depth <= 4) and (e.name or ""):lower() == target then
            return e.path
        end
    end
    return ""
end

-- Find the matching close-brace index for the '{' at open_pos (inclusive).
local function match_brace(text, open_pos)
    local depth = 0
    for i = open_pos, #text do
        local c = text:sub(i, i)
        if c == "{" then depth = depth + 1
        elseif c == "}" then depth = depth - 1; if depth == 0 then return i end end
    end
    return nil
end

-- Inject/replace LaunchOptions for appid. Returns (new_text, action) where action
-- is 'inserted' | 'replaced' | 'unchanged' | 'no_file' | 'no_apps_section'.
function M.set_launch_options(text, appid, options)
    if not text or text == "" then return text, "no_file" end
    appid = tonumber(appid)

    local apps_kw = text:find('"apps"%s*{')
    if not apps_kw then return text, "no_apps_section" end
    local apps_open = text:find("{", apps_kw, true)
    local apps_close = match_brace(text, apps_open)
    if not apps_close then return text, "no_apps_section" end

    local body_start, body_end = apps_open + 1, apps_close - 1
    local apps_body = text:sub(body_start, body_end)

    -- locate this appid's block inside apps_body
    local aid_kw = apps_body:find('"%s*' .. appid .. '%s*"%s*{')
    local new_apps_body, action
    if aid_kw then
        local aid_open = apps_body:find("{", aid_kw, true)
        local aid_close = match_brace(apps_body, aid_open)
        local app_body = apps_body:sub(aid_open + 1, (aid_close or #apps_body) - 1)

        if app_body:find('"LaunchOptions"%s*"') then
            local current = app_body:match('"LaunchOptions"%s*"([^"]*)"')
            if current == options then return text, "unchanged" end
            local new_app_body = app_body:gsub('("LaunchOptions"%s*")[^"]*(")', function(a, b)
                return a .. options .. b
            end, 1)
            new_apps_body = apps_body:sub(1, aid_open) .. new_app_body .. apps_body:sub(aid_close)
            action = "replaced"
        else
            local trimmed = app_body:gsub("[\n\t ]+$", "")
            local new_app_body = trimmed .. '\n\t\t\t\t\t"LaunchOptions"\t\t"' .. options .. '"\n\t\t\t\t'
            new_apps_body = apps_body:sub(1, aid_open) .. new_app_body .. apps_body:sub(aid_close)
            action = "inserted"
        end
    else
        local trimmed = apps_body:gsub("[\n\t ]+$", "")
        new_apps_body = trimmed ..
            '\n\t\t\t\t"' .. appid .. '"\n\t\t\t\t{\n\t\t\t\t\t"LaunchOptions"\t\t"' .. options .. '"\n\t\t\t\t}\n\t\t\t'
        action = "inserted"
    end

    local new_text = text:sub(1, body_start - 1) .. new_apps_body .. text:sub(body_end + 1)
    return new_text, action
end

local function read_current_launch_options(account_id32, appid)
    local lc = localconfig_path(account_id32)
    if lc == "" or not fs.is_file(lc) then return "" end
    local text = m_utils.read_file(lc) or ""
    local apps_kw = text:find('"apps"%s*{')
    if not apps_kw then return "" end
    local apps_open = text:find("{", apps_kw, true)
    local apps_close = match_brace(text, apps_open)
    if not apps_close then return "" end
    local apps_body = text:sub(apps_open + 1, apps_close - 1)
    local aid_kw = apps_body:find('"%s*' .. appid .. '%s*"%s*{')
    if not aid_kw then return "" end
    local aid_open = apps_body:find("{", aid_kw, true)
    local aid_close = match_brace(apps_body, aid_open)
    local app_body = apps_body:sub(aid_open + 1, (aid_close or #apps_body) - 1)
    return app_body:match('"LaunchOptions"%s*"([^"]*)"') or ""
end

-- ── public IPC ───────────────────────────────────────────────────────────────

function M.list_tokeer_games()
    local rows = {}
    for appid, meta in pairs(TOKEER_GAMES) do
        local install_dir = find_game_install_dir(appid)
        local launcher = install_dir ~= "" and find_launcher_exe(install_dir, meta.exe) or ""
        table.insert(rows, {
            appid = appid, name = meta.name, expectedExe = meta.exe,
            installed = install_dir ~= "", installDir = install_dir,
            launcherFound = launcher ~= "", launcherPath = launcher, ready = launcher ~= "",
        })
    end
    table.sort(rows, function(a, b)
        if a.installed ~= b.installed then return a.installed end
        if a.launcherFound ~= b.launcherFound then return a.launcherFound end
        return a.name < b.name
    end)
    return { success = true, games = st.A(rows), total = #rows }
end

function M.check_tokeer_status(appid, account_id32)
    appid = tonumber(appid)
    account_id32 = tonumber(account_id32) or 0
    if not appid then return { success = false, error = "Invalid appid or account_id" } end

    local meta = TOKEER_GAMES[appid]
    if not meta then
        return { success = true, supported = false, message = "This AppID is not in the Tokeer-compatible games list." }
    end
    local install_dir = find_game_install_dir(appid)
    local launcher = install_dir ~= "" and find_launcher_exe(install_dir, meta.exe) or ""
    local current = account_id32 ~= 0 and read_current_launch_options(account_id32, appid) or ""
    local expected = launcher ~= "" and ('"' .. launcher .. '" %command%') or ""
    local configured = current ~= "" and current:lower():find("tokeer_launcher", 1, true) ~= nil

    return {
        success = true, supported = true, appid = appid, name = meta.name,
        installed = install_dir ~= "", installDir = install_dir,
        launcherFound = launcher ~= "", launcherPath = launcher,
        configured = configured, currentLaunchOptions = current,
        recommendedLaunchOptions = expected, needsAction = (launcher ~= "" and not configured),
    }
end

function M.configure_tokeer_launch(appid, account_id32)
    appid = tonumber(appid)
    account_id32 = tonumber(account_id32)
    if not appid or not account_id32 then return { success = false, error = "Invalid appid or account_id" } end

    local meta = TOKEER_GAMES[appid]
    if not meta then return { success = false, error = "AppID is not Tokeer-supported" } end
    if st.steam_is_running() then
        return { success = false, requiresSteamClose = true,
            error = "Steam is running. Close it first -- otherwise Steam will overwrite our launch options on exit." }
    end

    local install_dir = find_game_install_dir(appid)
    if install_dir == "" then return { success = false, error = "Game not installed (no appmanifest for " .. appid .. ")" } end
    local launcher = find_launcher_exe(install_dir, meta.exe)
    if launcher == "" then
        return { success = false, expectedPath = fs.join(install_dir, meta.exe),
            error = "tokeer_launcher.exe not found inside '" .. install_dir .. "'. Install Tokeer for this game first." }
    end

    local lc_path = localconfig_path(account_id32)
    if not fs.is_file(lc_path) then
        return { success = false, error = "localconfig.vdf not found at " .. lc_path .. ". This account has never logged in here." }
    end

    local lc_text = m_utils.read_file(lc_path) or ""
    m_utils.write_file(lc_path .. ".bak-" .. st.stamp(), lc_text)
    local options = '"' .. launcher .. '" %command%'
    local new_text, action = M.set_launch_options(lc_text, appid, options)
    if action == "no_file" or action == "no_apps_section" then
        return { success = false, error = "localconfig.vdf parse: " .. action }
    end
    if action == "unchanged" then
        return { success = true, action = "unchanged", appid = appid, launchOptions = options, message = "Launch options already correct." }
    end
    local ok = m_utils.write_file(lc_path, new_text)
    if ok == false then return { success = false, error = "Write failed" } end

    logger.log("tokeer: " .. action .. " launch options for " .. meta.name .. " (appid=" .. appid .. ")")
    return {
        success = true, action = action, appid = appid, name = meta.name,
        launcherPath = launcher, launchOptions = options, localconfigPath = lc_path,
        message = (action == "replaced" and "Replaced" or "Added") .. " launch options. Start Steam to apply.",
    }
end

function M.remove_tokeer_launch(appid, account_id32)
    appid = tonumber(appid)
    account_id32 = tonumber(account_id32)
    if not appid or not account_id32 then return { success = false, error = "Invalid appid or account_id" } end
    local lc_path = localconfig_path(account_id32)
    local lc_text = fs.is_file(lc_path) and m_utils.read_file(lc_path) or ""
    if not lc_text or lc_text == "" then return { success = false, error = "localconfig.vdf not found" } end
    local new_text, action = M.set_launch_options(lc_text, appid, "")
    if action == "unchanged" then return { success = true, message = "Launch options were already empty." } end
    local ok = m_utils.write_file(lc_path, new_text)
    if ok == false then return { success = false, error = "Write failed" } end
    return { success = true, action = action, message = "Launch options cleared." }
end

return M
