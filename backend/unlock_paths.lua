-- unlock_paths.lua — resolve Lua script directory from shared Rewired config + local detection.
-- Manager/plugin share rewired.json (Windows LOCALAPPDATA or Linux XDG data home).

local fs = require("fs")
local cjson = require("json")
local m_utils = require("utils")
local steam_utils = require("steam_utils")
local platform = require("platform")
local logger = require("plugin_logger")

local M = {}

local SHARED_CONFIG = nil
local RESOLVED_BACKEND = nil

local BACKENDS = {
    auto = true,
    opensteamtool = true,
    steamtools = true,
    lumacore = true,
    millennium = true,
}

local function _steam_path()
    local p = steam_utils.detect_steam_install_path()
    return (p and p ~= "") and p or ""
end

local function _shared_config_path()
    local dir = platform.config_dir()
    if dir == "" then return "" end
    return fs.join(dir, "rewired.json")
end

function M.read_shared_config()
    if SHARED_CONFIG ~= nil then return SHARED_CONFIG end
    local path = _shared_config_path()
    if path == "" or not fs.exists(path) then
        SHARED_CONFIG = {}
        return SHARED_CONFIG
    end
    local raw = m_utils.read_file(path)
    if not raw or raw == "" then
        SHARED_CONFIG = {}
        return SHARED_CONFIG
    end
    local ok, data = pcall(cjson.decode, raw)
    SHARED_CONFIG = (ok and type(data) == "table") and data or {}
    return SHARED_CONFIG
end

function M.invalidate_cache()
    SHARED_CONFIG = nil
    RESOLVED_BACKEND = nil
end

function M.write_shared_config(partial)
    if type(partial) ~= "table" then return false, "invalid payload" end
    SHARED_CONFIG = nil
    RESOLVED_BACKEND = nil
    local current = M.read_shared_config()
    for k, v in pairs(partial) do current[k] = v end
    local path = _shared_config_path()
    if path == "" then return false, "Rewired config directory not available" end
    local dir = platform.config_dir()
    if not fs.exists(dir) then pcall(fs.create_directories, dir) end
    local ok = pcall(m_utils.write_file, path, cjson.encode(current))
    if ok then SHARED_CONFIG = current end
    return ok, path
end

local function _read_plugin_unlock_backend()
    local ok, paths = pcall(require, "paths")
    if not ok or not paths or not paths.backend_path then return nil end
    local settings_file = paths.backend_path("data/settings.json")
    if not fs.exists(settings_file) then return nil end
    local raw = m_utils.read_file(settings_file)
    if not raw or raw == "" then return nil end
    local ok2, data = pcall(cjson.decode, raw)
    if not ok2 or type(data) ~= "table" then return nil end
    local values = data.values
    if type(values) ~= "table" or type(values.unlock) ~= "table" then return nil end
    local backend = tostring(values.unlock.backend or "")
    if backend == "" then return nil end
    return backend:lower()
end

function M.detect_opensteamtool(steam)
    steam = steam or _steam_path()
    if steam == "" then return false end
    return fs.exists(fs.join(steam, "OpenSteamTool.dll"))
        or fs.exists(fs.join(steam, "opensteamtool", "OpenSteamTool.dll"))
end

function M.detect_steamtools(steam)
    steam = steam or _steam_path()
    if steam == "" then return false end
    if fs.exists(fs.join(steam, "config", "stplug-in", "Steamtools.lua")) then return true end
    if fs.exists(fs.join(steam, "Steamtools.exe")) then return true end
    if fs.exists(fs.join(steam, "config", "stUI")) then return true end
    -- Linux SLSsteam / ACCELA stacks also consume config/stplug-in.
    if M.detect_slssteam(steam) then return true end
    return false
end

function M.detect_slssteam(steam)
    steam = steam or _steam_path()
    if steam == "" then return false end
    local home = m_utils.getenv("HOME") or ""
    local candidates = {
        fs.join(steam, "SLSsteam.so"),
        fs.join(steam, "slssteam", "SLSsteam.so"),
    }
    if home ~= "" then
        table.insert(candidates, fs.join(home, ".local", "share", "SLSsteam", "SLSsteam.so"))
        table.insert(candidates, fs.join(home, ".config", "SLSsteam", "config.yaml"))
    end
    for _, p in ipairs(candidates) do
        if fs.exists(p) then return true end
    end
    local ld = tostring(m_utils.getenv("LD_AUDIT") or "")
    if ld:lower():find("slssteam", 1, true) then return true end
    return false
end

function M.detect_lumacore(steam)
    steam = steam or _steam_path()
    if steam == "" then return false end
    return fs.exists(fs.join(steam, "LumaCore.dll"))
end

--- @return string one of: opensteamtool, steamtools, lumacore, millennium, none
function M.resolve_backend()
    if RESOLVED_BACKEND then return RESOLVED_BACKEND end

    local shared = M.read_shared_config()
    local pref = tostring(shared.unlockBackend or shared.unlock_backend or _read_plugin_unlock_backend() or "auto"):lower()
    if not BACKENDS[pref] then pref = "auto" end

    local steam = tostring(shared.steamPath or shared.steam_path or "")
    if steam == "" then steam = _steam_path() end
    -- Keep native separators; only normalize for Windows path compares below.
    if platform.is_windows() then steam = steam:gsub("/", "\\") end

    if pref == "opensteamtool" then
        -- OpenSteamTool is Windows-only; fall back to stplug-in on Linux.
        if platform.is_linux() then
            RESOLVED_BACKEND = "steamtools"
        else
            RESOLVED_BACKEND = "opensteamtool"
        end
        return RESOLVED_BACKEND
    end
    if pref == "steamtools" then
        RESOLVED_BACKEND = "steamtools"
        return RESOLVED_BACKEND
    end
    if pref == "lumacore" then
        RESOLVED_BACKEND = "lumacore"
        return RESOLVED_BACKEND
    end
    if pref == "millennium" then
        RESOLVED_BACKEND = "millennium"
        return RESOLVED_BACKEND
    end

    -- auto: SteamTools/SLSsteam (stplug-in) first, then LumaCore, then OpenSteamTool
    if M.detect_steamtools(steam) then
        RESOLVED_BACKEND = "steamtools"
    elseif M.detect_lumacore(steam) then
        RESOLVED_BACKEND = "lumacore"
    elseif platform.is_windows() and M.detect_opensteamtool(steam) then
        RESOLVED_BACKEND = "opensteamtool"
    else
        RESOLVED_BACKEND = "none"
    end
    return RESOLVED_BACKEND
end

--- Directory where per-app unlock Lua files are written.
function M.lua_script_dir()
    local steam = _steam_path()
    if steam == "" then return "" end

    local backend = M.resolve_backend()
    if backend == "opensteamtool" then
        return fs.join(steam, "config", "lua")
    end
    -- steamtools, lumacore, millennium, none — classic stplug-in layout
    return fs.join(steam, "config", "stplug-in")
end

function M.depotcache_dir()
    local steam = _steam_path()
    if steam == "" then return "" end
    return fs.join(steam, "depotcache")
end

function M.ensure_lua_script_dir()
    local dir = M.lua_script_dir()
    if dir == "" then return false, "Steam path not found" end
    if not fs.exists(dir) then
        local ok, err = pcall(fs.create_directories, dir)
        if not ok then return false, tostring(err) end
    end
    return true, dir
end

function M.get_unlock_status()
    local steam = _steam_path()
    return {
        steamPath = steam,
        sharedConfigPath = _shared_config_path(),
        backend = M.resolve_backend(),
        luaScriptDir = M.lua_script_dir(),
        depotcacheDir = M.depotcache_dir(),
        openSteamTool = M.detect_opensteamtool(steam),
        steamTools = M.detect_steamtools(steam),
        slsSteam = M.detect_slssteam(steam),
        lumaCore = M.detect_lumacore(steam),
        platform = platform.name(),
    }
end

return M
