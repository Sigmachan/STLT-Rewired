-- sentinel.lua — Sentinel config + ignore-list manager.
--
-- sentinel.py was a background watcher: a Python daemon thread + a scheduled
-- task running sentinel_worker.py. Millennium 3.x is single-threaded LuaJIT with
-- no persistent background process and no Python runtime, so the *continuous
-- watcher* and the *scheduled-task service* cannot be reproduced here (analogous
-- to the dropped Linux/ACCELA layer). What IS ported: the configuration + ignore
-- list (persisted to <Steam>/config/sentinel_config.json), which the UI manages;
-- update checks are available on demand via CheckManifestStaleness / dashboard.

local cjson       = require("json")
local m_utils     = require("utils")
local fs          = require("fs")
local logger      = require("plugin_logger")
local steam_utils = require("steam_utils")
local st          = require("st_util")

local M = {}

local UNAVAILABLE = "Sentinel's continuous background watcher isn't available in the Lua backend " ..
    "(Millennium 3.x removed the Python runtime it required). Config is managed here; run update " ..
    "checks on demand via CheckManifestStaleness or the dashboard."

local function config_path()
    local base = steam_utils.detect_steam_install_path()
    if not base or base == "" then return "" end
    return fs.join(base, "config", "sentinel_config.json")
end

local function default_config()
    return {
        enabled = false, poll_interval = 45,
        auto_activation_enabled = false, auto_fix_enabled = false,
        auto_apply_policy = "ask", notification_style = "toast",
        per_game_ignore = {}, per_game_auto_apply = {},
    }
end

local function read_config()
    local p = config_path()
    if p == "" or not fs.is_file(p) then return default_config() end
    local ok, data = pcall(cjson.decode, m_utils.read_file(p) or "")
    if ok and type(data) == "table" then
        local d = default_config()
        for k, v in pairs(data) do d[k] = v end
        return d
    end
    return default_config()
end

local function write_config(cfg)
    local p = config_path()
    if p == "" then return false end
    return m_utils.write_file(p, cjson.encode({
        enabled = cfg.enabled == true, poll_interval = tonumber(cfg.poll_interval) or 45,
        auto_activation_enabled = cfg.auto_activation_enabled == true,
        auto_fix_enabled = cfg.auto_fix_enabled == true,
        auto_apply_policy = cfg.auto_apply_policy or "ask",
        notification_style = cfg.notification_style or "toast",
        per_game_ignore = st.A(cfg.per_game_ignore or {}),
        per_game_auto_apply = st.A(cfg.per_game_auto_apply or {}),
    })) ~= false
end

-- ── config IPC (functional) ──────────────────────────────────────────────────

function M.get_config()
    return { success = true, config = read_config() }
end

function M.set_config(config_json)
    if type(config_json) == "table" then config_json = config_json.config_json or config_json end
    local updates
    if type(config_json) == "string" then
        local ok, parsed = pcall(cjson.decode, config_json)
        if not ok then return { success = false, error = tostring(parsed) } end
        updates = parsed
    elseif type(config_json) == "table" then
        updates = config_json
    else
        updates = {}
    end
    local cfg = read_config()
    for k, v in pairs(updates) do cfg[k] = v end
    if not write_config(cfg) then return { success = false, error = "write failed" } end
    return { success = true, config = read_config() }
end

function M.ignore_game(appid)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "Invalid appid" } end
    local cfg = read_config()
    local list, seen = {}, false
    for _, id in ipairs(cfg.per_game_ignore or {}) do
        if tonumber(id) == appid then seen = true end
        table.insert(list, tonumber(id))
    end
    if not seen then table.insert(list, appid) end
    cfg.per_game_ignore = list
    if not write_config(cfg) then return { success = false, error = "write failed" } end
    return { success = true, appid = appid, ignored = st.A(list) }
end

function M.unignore_game(appid)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "Invalid appid" } end
    local cfg = read_config()
    local list = {}
    for _, id in ipairs(cfg.per_game_ignore or {}) do
        if tonumber(id) ~= appid then table.insert(list, tonumber(id)) end
    end
    cfg.per_game_ignore = list
    if not write_config(cfg) then return { success = false, error = "write failed" } end
    return { success = true, appid = appid, ignored = st.A(list) }
end

function M.get_status()
    return {
        success = true, running = false, backgroundWatcher = false,
        config = read_config(), note = UNAVAILABLE,
    }
end

-- ── daemon / service lifecycle (unavailable in the Lua backend) ──────────────

local function unavailable() return { success = false, error = UNAVAILABLE, unsupported = true } end

M.start = unavailable
M.stop = unavailable
M.get_service = unavailable
M.install_service = unavailable
M.uninstall_service = unavailable
M.start_service_now = unavailable

return M
