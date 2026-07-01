-- achievements.lua — read-only achievement progress + schema seeding.
--
-- Faithful Lua port of achievement_watch.py + the steamtools.py achievement
-- functions. READ-ONLY progress (never fakes unlocks): parses UserGameStats_*.bin
-- with a conservative timestamp byte-scan, cross-references the Steam Web API
-- schema, and lists per-game progress. seed_achievement_files writes the empty
-- 38-byte stats template so Steam can populate it on first launch.

local cjson       = require("json")
local m_utils     = require("utils")
local fs          = require("fs")
local http_client = require("http_client")
local logger      = require("plugin_logger")
local steam_utils = require("steam_utils")
local st          = require("st_util")

local M = {}

local STEAMID64_BASE = "76561197960265728"

-- Empty UserGameStats template (38 bytes; bytes 9 and 17 are 0x01).
local USERGAMESTATS_TEMPLATE = string.char(
    0, 0, 0, 0, 0, 0, 0, 0,
    1, 0, 0, 0, 0, 0, 0, 0,
    1, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0)

local function stats_dir()
    local base = steam_utils.detect_steam_install_path()
    if not base or base == "" then return "" end
    return fs.join(base, "appcache", "stats")
end

-- Decimal string subtraction (a - b, a >= b) -> number. Needed because a
-- SteamID64 exceeds LuaJIT's exact-double range (2^53).
local function sub_decimal(a, b)
    local n = math.max(#a, #b)
    a = string.rep("0", n - #a) .. a
    b = string.rep("0", n - #b) .. b
    local out, borrow = {}, 0
    for i = n, 1, -1 do
        local d = (a:byte(i) - 48) - (b:byte(i) - 48) - borrow
        if d < 0 then d = d + 10; borrow = 1 else borrow = 0 end
        out[i] = string.char(48 + d)
    end
    return tonumber((table.concat(out):gsub("^0+", ""))) or 0
end

-- Parse loginusers.vdf -> accounts [{accountId32, steamId64, username, personaName, mostRecent}].
local function get_active_account_ids()
    local base = steam_utils.detect_steam_install_path()
    if not base or base == "" then return {} end
    local vdf = fs.join(base, "config", "loginusers.vdf")
    if not fs.is_file(vdf) then return {} end
    local raw = m_utils.read_file(vdf) or ""
    local accounts = {}
    for sid, body in raw:gmatch('"(%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d+)"%s*{(.-)}') do
        local name = body:match('"AccountName"%s*"([^"]+)"')
        local recent = body:match('"MostRecent"%s*"([01])"')
        local persona = body:match('"PersonaName"%s*"([^"]+)"')
        table.insert(accounts, {
            accountId32 = sub_decimal(sid, STEAMID64_BASE),
            steamId64 = sid,
            username = name or "",
            personaName = persona or "",
            mostRecent = recent == "1",
        })
    end
    table.sort(accounts, function(a, b)
        if a.mostRecent ~= b.mostRecent then return a.mostRecent end
        return a.username < b.username
    end)
    return accounts
end

local function check_schema_files(appid, account_id32)
    local sd = stats_dir()
    local schema_file = fs.join(sd, "UserGameStatsSchema_" .. appid .. ".bin")
    local user_file = fs.join(sd, "UserGameStats_" .. account_id32 .. "_" .. appid .. ".bin")
    return {
        statsDir = sd, schemaFile = schema_file, userStatsFile = user_file,
        schemaExists = fs.is_file(schema_file),
        userStatsExists = fs.is_file(user_file),
        schemaSize = fs.is_file(schema_file) and (fs.file_size(schema_file) or 0) or 0,
    }
end

-- ── binary stats scan ────────────────────────────────────────────────────────

local function read_u32le(data, i)
    local a, b, c, d = data:byte(i, i + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end

local function parse_user_stats_binary(path)
    if not fs.is_file(path) then return { exists = false } end
    local data = m_utils.read_file(path)
    if not data then return { exists = false } end
    local file_size = #data
    if file_size < 32 then
        return { exists = true, fileSize = file_size, unlockedCount = 0, timestamps = {}, seeded_empty = true }
    end
    local min_ts = 1062374400
    local max_ts = math.floor(m_utils.time()) + 86400
    local ts_set = {}
    for i = 1, file_size - 3 do
        local ts = read_u32le(data, i)
        if ts >= min_ts and ts <= max_ts then ts_set[ts] = true end
    end
    local uniq = {}
    for ts in pairs(ts_set) do table.insert(uniq, ts) end
    table.sort(uniq, function(a, b) return a > b end)
    local top = {}
    for i = 1, math.min(50, #uniq) do top[i] = uniq[i] end
    return { exists = true, fileSize = file_size, unlockedCount = #uniq, timestamps = top, seeded_empty = false }
end

-- ── web api schema ───────────────────────────────────────────────────────────

local function web_api_key()
    local ok, sm = pcall(require, "settings.manager")
    if ok and type(sm) == "table" and type(sm.get_steamtools_settings) == "function" then
        local ok2, s = pcall(sm.get_steamtools_settings)
        if ok2 and type(s) == "table" and type(s.steamtools) == "table" then
            return s.steamtools.steamWebApiKey or ""
        end
    end
    return ""
end

local function fetch_schema(appid, key)
    if key and key ~= "" then
        local url = "https://api.steampowered.com/ISteamUserStats/GetSchemaForGame/v2/?key=" ..
            key .. "&appid=" .. appid .. "&l=english"
        local ok, resp = pcall(http_client.get, url, { timeout = 10 })
        if ok and resp and resp.status == 200 and resp.body then
            local ok2, data = pcall(cjson.decode, resp.body)
            if ok2 and type(data) == "table" then
                local game = type(data.game) == "table" and data.game or {}
                local stats = type(game.availableGameStats) == "table" and game.availableGameStats or {}
                local achs = {}
                for _, a in ipairs(stats.achievements or {}) do
                    table.insert(achs, {
                        name = a.name or "", displayName = a.displayName or "",
                        description = a.description or "", hidden = a.hidden == 1,
                        icon = a.icon or "", iconGray = a.icongray or "",
                    })
                end
                return { success = true, source = "web_api_keyed", gameName = game.gameName or "", achievements = achs }
            end
        end
    end
    local url = "https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v2/?gameid=" .. appid
    local ok, resp = pcall(http_client.get, url, { timeout = 10 })
    if ok and resp and resp.status == 200 and resp.body then
        local ok2, data = pcall(cjson.decode, resp.body)
        if ok2 and type(data) == "table" then
            local pcts = (type(data.achievementpercentages) == "table" and data.achievementpercentages.achievements) or {}
            local achs = {}
            for _, p in ipairs(pcts) do
                table.insert(achs, { name = p.name or "", displayName = p.name or "", globalPercent = tonumber(p.percent) or 0 })
            end
            return { success = true, source = "public_global", achievements = achs }
        end
    end
    return { success = false, error = "Could not fetch achievement schema" }
end

-- ── public IPC ───────────────────────────────────────────────────────────────

function M.get_active_accounts()
    return { success = true, accounts = st.A(get_active_account_ids()) }
end

function M.get_achievement_info(appid)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "Invalid appid" } end
    local result = { success = true, appid = appid, count = 0, achievements = st.A({}), accounts = {}, apiAvailable = false }

    local url = "https://api.steampowered.com/ISteamUserStats/GetSchemaForGame/v2/?appid=" .. appid .. "&l=english&format=json"
    local ok, resp = pcall(http_client.get, url, { timeout = 15, headers = { ["User-Agent"] = "STLT-Rewired/1.0" } })
    if ok and resp and resp.status == 200 and resp.body then
        local ok2, data = pcall(cjson.decode, resp.body)
        if ok2 and type(data) == "table" then
            local game = type(data.game) == "table" and data.game or {}
            local stats = type(game.availableGameStats) == "table" and game.availableGameStats or {}
            local achievements = stats.achievements or {}
            result.count = #achievements
            result.apiAvailable = true
            local achs = {}
            for i = 1, math.min(50, #achievements) do
                local a = achievements[i]
                table.insert(achs, {
                    name = a.name or "", displayName = a.displayName or "",
                    description = a.description or "", hidden = a.hidden == 1, icon = a.icon or "",
                })
            end
            result.achievements = st.A(achs)
            if #achievements > 50 then result.truncated = #achievements - 50 end
        end
    elseif ok and resp and resp.status == 403 then
        result.apiNote = "Game schema is private or requires a Steam API key"
    elseif ok and resp then
        result.apiNote = "Steam Web API returned HTTP " .. tostring(resp.status)
    else
        result.apiNote = "Steam Web API unavailable"
    end

    local accounts = get_active_account_ids()
    if #accounts == 0 then result.accountNote = "No accounts found in loginusers.vdf" end
    local acc_out = {}
    for _, acc in ipairs(accounts) do
        local fi = check_schema_files(appid, acc.accountId32)
        table.insert(acc_out, {
            accountId32 = acc.accountId32, steamId64 = acc.steamId64,
            username = acc.username, personaName = acc.personaName, mostRecent = acc.mostRecent,
            schemaExists = fi.schemaExists, schemaSize = fi.schemaSize, userStatsExists = fi.userStatsExists,
        })
    end
    result.accounts = st.A(acc_out)
    return result
end

function M.seed_achievement_files(appid, account_id32)
    appid = tonumber(appid)
    account_id32 = tonumber(account_id32) or 0
    if not appid then return { success = false, error = "Invalid appid or account_id" } end
    local sd = stats_dir()
    if sd == "" then return { success = false, error = "Steam path not found" } end
    pcall(fs.create_directories, sd)

    local accounts
    if account_id32 == 0 then
        accounts = get_active_account_ids()
    else
        accounts = { { accountId32 = account_id32, username = "id:" .. account_id32, mostRecent = true } }
    end
    if #accounts == 0 then return { success = false, error = "No accounts found" } end

    local seeded, skipped, errors = {}, {}, {}
    for _, acc in ipairs(accounts) do
        local aid = acc.accountId32
        local user_file = fs.join(sd, "UserGameStats_" .. aid .. "_" .. appid .. ".bin")
        if fs.is_file(user_file) then
            table.insert(skipped, { accountId32 = aid, username = acc.username or "", reason = "already exists" })
        else
            local wrote = m_utils.write_file(user_file, USERGAMESTATS_TEMPLATE)
            if wrote == false then
                table.insert(errors, { accountId32 = aid, error = "write failed" })
            else
                logger.log("achievements: seeded " .. user_file)
                table.insert(seeded, { accountId32 = aid, username = acc.username or "", path = user_file })
            end
        end
    end

    local schema_file = fs.join(sd, "UserGameStatsSchema_" .. appid .. ".bin")
    local schema_exists = fs.is_file(schema_file)
    return {
        success = true, appid = appid,
        seeded = st.A(seeded), skipped = st.A(skipped), errors = st.A(errors),
        schemaExists = schema_exists,
        schemaNote = schema_exists and "Schema binary already present."
            or "Schema binary not found. Steam will download it automatically the first time you launch the game with an active .lua script.",
        statsDir = sd,
    }
end

function M.get_achievement_progress(appid, account_id32)
    appid = tonumber(appid)
    account_id32 = tonumber(account_id32)
    if not appid or not account_id32 then return { success = false, error = "invalid args" } end

    local user_file = fs.join(stats_dir(), "UserGameStats_" .. account_id32 .. "_" .. appid .. ".bin")
    local parsed = parse_user_stats_binary(user_file)

    local schema = fetch_schema(appid, web_api_key())
    local total = schema.success and #(schema.achievements or {}) or 0
    local unlocked = parsed.exists and (parsed.unlockedCount or 0) or 0
    if total > 0 and unlocked > total then unlocked = total end
    local percentage = total > 0 and st.round(100 * unlocked / total, 1) or 0

    local recent = {}
    local ts = parsed.timestamps or {}
    for i = 1, math.min(10, #ts) do recent[i] = ts[i] end

    return {
        success = true, appid = appid, accountId32 = account_id32,
        gameName = schema.gameName or "", schemaSource = schema.source or "",
        schemaAvailable = schema.success or false,
        statsFileExists = parsed.exists or false, statsFileSize = parsed.fileSize or 0,
        seeded_empty = parsed.seeded_empty or false,
        totalAchievements = total, unlockedCount = unlocked, percentage = percentage,
        recentUnlocks = st.A(recent),
    }
end

function M.list_watchlist(account_id32)
    account_id32 = tonumber(account_id32)
    if not account_id32 then return { success = false, error = "invalid accountId32" } end
    local stplug = st.stplug_dir()
    if stplug == "" or not fs.is_directory(stplug) then return { success = false, error = "stplug-in dir not found" } end
    local sd = stats_dir()

    local games = {}
    for _, e in ipairs(fs.list(stplug) or {}) do
        local aid = (e.name or ""):match("^(%d+)%.lua$")
        if aid then
            aid = tonumber(aid)
            local user_file = fs.join(sd, "UserGameStats_" .. account_id32 .. "_" .. aid .. ".bin")
            local schema_file = fs.join(sd, "UserGameStatsSchema_" .. aid .. ".bin")
            local parsed = parse_user_stats_binary(user_file)
            local tslist = parsed.timestamps or {}
            table.insert(games, {
                appid = aid, hasStatsFile = parsed.exists or false,
                hasSchema = fs.is_file(schema_file),
                schemaSize = fs.is_file(schema_file) and (fs.file_size(schema_file) or 0) or 0,
                unlockedCount = parsed.unlockedCount or 0,
                seeded_empty = parsed.seeded_empty or false,
                lastUnlockTs = (#tslist > 0) and tslist[1] or 0,
            })
        end
    end
    table.sort(games, function(a, b)
        if a.unlockedCount ~= b.unlockedCount then return a.unlockedCount > b.unlockedCount end
        return (a.lastUnlockTs or 0) > (b.lastUnlockTs or 0)
    end)

    local total_unlocked, with_progress = 0, 0
    for _, g in ipairs(games) do
        total_unlocked = total_unlocked + g.unlockedCount
        if g.unlockedCount > 0 then with_progress = with_progress + 1 end
    end
    return {
        success = true, accountId32 = account_id32, totalGames = #games,
        gamesWithProgress = with_progress, totalUnlocked = total_unlocked, games = st.A(games),
    }
end

function M.get_recent_unlocks(account_id32, limit)
    account_id32 = tonumber(account_id32)
    limit = math.max(1, math.min(math.floor(tonumber(limit) or 20), 100))
    if not account_id32 then return { success = false, error = "invalid args" } end
    local sd = stats_dir()
    if not fs.is_directory(sd) then return { success = true, unlocks = st.A({}) } end

    local prefix = "UserGameStats_" .. account_id32 .. "_"
    local all = {}
    for _, e in ipairs(fs.list(sd) or {}) do
        local n = e.name or ""
        if n:sub(1, #prefix) == prefix and n:match("%.bin$") then
            local aid = tonumber((n:sub(#prefix + 1):gsub("%.bin$", "")))
            if aid then
                local parsed = parse_user_stats_binary(e.path)
                for _, ts in ipairs(parsed.timestamps or {}) do
                    table.insert(all, { appid = aid, ts = ts })
                end
            end
        end
    end
    table.sort(all, function(a, b) return a.ts > b.ts end)
    local out = {}
    for i = 1, math.min(limit, #all) do out[i] = all[i] end
    return { success = true, accountId32 = account_id32, unlocks = st.A(out), totalCount = #all }
end

return M
