-- stlt_migration.lua — one-time import from legacy STLT / LuaTools plugin data layouts.
-- Copies secrets from settings.json into secrets.local.json and restores missing data/
-- files from the newest millennium/_plugin-backups/luatools.backup-* snapshot.

local fs          = require("fs")
local cjson       = require("json")
local paths       = require("paths")
local st          = require("st_util")
local utils       = require("plugin_utils")
local steam_utils = require("steam_utils")
local logger      = require("plugin_logger")

local M = {}

local SECRETS_FILE  = paths.backend_path("data/secrets.local.json")
local SETTINGS_FILE = paths.backend_path("data/settings.json")
local MARKER        = paths.backend_path("data/.stlt_migration_v1")

local DATA_FILES = {
    "settings.json",
    "secrets.local.json",
    "custom_apis.json",
    "source_chain.json",
    "key_vault.json",
    "sentinel_config.json",
}

local function read_json(path)
    if not fs.exists(path) then return nil end
    local ok, data = pcall(utils.read_json, path)
    if ok and type(data) == "table" then return data end
    return nil
end

local function secret_empty(secrets, key)
    if type(secrets) ~= "table" then return true end
    local v = secrets[key]
    return type(v) ~= "string" or v == ""
end

function M.migrate_secrets_from_settings()
    local secrets = read_json(SECRETS_FILE) or {}
    local settings = read_json(SETTINGS_FILE)
    if not settings then return false end

    local general = type(settings.general) == "table" and settings.general or {}
    local changed = false

    if secret_empty(secrets, "ryuuSession") and type(general.ryuuSession) == "string" and general.ryuuSession ~= "" then
        secrets.ryuuSession = general.ryuuSession
        changed = true
    end

    if secret_empty(secrets, "morrenusApiKey") then
        for _, key in ipairs({ "morrenusApiKey", "manifestHubApiKey" }) do
            local v = general[key]
            if type(v) == "string" and v ~= "" then
                secrets.morrenusApiKey = v
                secrets.manifestHubApiKey = v
                changed = true
                break
            end
        end
    end

    if not changed then return false end

    local data_dir = paths.backend_path("data")
    if not fs.exists(data_dir) then pcall(fs.create_directories, data_dir) end
    utils.write_json(SECRETS_FILE, secrets)
    logger.log("stlt_migration: imported secrets from legacy settings.json")
    return true
end

local function latest_backup_data_dir()
    local steam = steam_utils.detect_steam_install_path()
    if not steam or steam == "" then return nil end
    local root = fs.join(steam, "millennium", "_plugin-backups")
    if not fs.is_directory(root) then return nil end

    local best_path, best_name = nil, ""
    for _, entry in ipairs(fs.list(root) or {}) do
        local name = entry.name or ""
        if name:match("^luatools%.backup%-") and fs.is_directory(entry.path) then
            local data_dir = fs.join(entry.path, "backend", "data")
            if fs.is_directory(data_dir) and name > best_name then
                best_name = name
                best_path = data_dir
            end
        end
    end
    return best_path
end

function M.restore_missing_data_from_backup()
    local backup_data = latest_backup_data_dir()
    if not backup_data then return 0 end

    local data_dir = paths.backend_path("data")
    if not fs.exists(data_dir) then pcall(fs.create_directories, data_dir) end

    local restored = 0
    for _, fname in ipairs(DATA_FILES) do
        local live = fs.join(data_dir, fname)
        if not fs.is_file(live) then
            local src = fs.join(backup_data, fname)
            if fs.is_file(src) then
                local ok = pcall(function()
                    utils.write_text(live, utils.read_text(src))
                end)
                if ok then
                    restored = restored + 1
                    logger.log("stlt_migration: restored " .. fname .. " from plugin backup")
                end
            end
        end
    end
    return restored
end

function M.run_once()
    if fs.exists(MARKER) then
        return { success = true, skipped = true, migrated = st.A({}) }
    end

    local migrated = {}
    if M.migrate_secrets_from_settings() then
        table.insert(migrated, "secrets-from-settings")
    end

    local restored = M.restore_missing_data_from_backup()
    if restored > 0 then
        table.insert(migrated, "data-files:" .. tostring(restored))
    end

    pcall(function() utils.write_text(MARKER, cjson.encode({ at = os.time(), migrated = migrated })) end)
    if #migrated > 0 then
        logger.log("stlt_migration: completed — " .. table.concat(migrated, ", "))
    end

    return { success = true, skipped = false, migrated = st.A(migrated), restored = restored }
end

return M
