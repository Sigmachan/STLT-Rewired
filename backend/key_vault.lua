-- key_vault.lua — named profiles of premium API credentials.
--
-- Faithful Lua port of key_vault.py. Stores named credential sets in
-- backend/data/key_vault.json (plain JSON, like the Python original -- no
-- encryption) and exports/imports them as base64 .ltkeys blobs. Snapshotting
-- and applying keys goes through settings.manager when its getters/setters are
-- present; otherwise those fields are simply empty (graceful).

local cjson  = require("json")
local m_utils = require("utils")
local fs      = require("fs")
local logger  = require("plugin_logger")
local st      = require("st_util")

local M = {}

local VAULT_FIELDS = {
    { "morrenusApiKey",   "Morrenus API Key" },
    { "ryuuSession",      "Ryuu Session" },
    { "depotboxSid",      "DepotBox SID" },
    { "manifestHubApiKey", "ManifestHub API Key" },
    { "steamGridDbKey",   "SteamGridDB Key" },
    { "githubToken",      "GitHub Token" },
}

local FIELD_GROUPS = {
    morrenusApiKey = "general", ryuuSession = "general", depotboxSid = "general",
    manifestHubApiKey = "steamtools", steamGridDbKey = "steamtools", githubToken = "steamtools",
}

local GETTERS = {
    morrenusApiKey = "get_morrenus_api_key", ryuuSession = "get_ryuu_session",
    depotboxSid = "get_depotbox_sid", manifestHubApiKey = "get_manifesthub_api_key",
    steamGridDbKey = "get_steamgriddb_key", githubToken = "get_github_token",
}

local function vault_path() return st.data_path("key_vault.json") end

local function read_vault()
    local p = vault_path()
    if not fs.is_file(p) then return { profiles = {}, active = "", updated_at = 0 } end
    local ok, data = pcall(cjson.decode, m_utils.read_file(p) or "")
    if ok and type(data) == "table" then
        if type(data.profiles) ~= "table" then data.profiles = {} end
        return data
    end
    logger.warn("key_vault: read failed")
    return { profiles = {}, active = "", updated_at = 0 }
end

local function write_vault(data)
    data.updated_at = math.floor(m_utils.time())
    if next(data.profiles) == nil then data.profiles = cjson.decode("{}") end
    m_utils.write_file(vault_path(), cjson.encode(data))
end

local function current_keys()
    local ok, sm = pcall(require, "settings.manager")
    local result = {}
    for field, fn in pairs(GETTERS) do
        local v = ""
        if ok and type(sm) == "table" and type(sm[fn]) == "function" then
            local ok2, val = pcall(sm[fn])
            if ok2 and val then v = tostring(val) end
        end
        result[field] = v
    end
    return result
end

local function mask(v)
    v = tostring(v or "")
    if v == "" then return "" end
    if #v <= 10 then return v:sub(1, 2) .. "***" end
    return v:sub(1, 4) .. "***" .. v:sub(-4) .. " (" .. #v .. " chars)"
end

local function bad_name(name)
    return name == "" or name:find("/", 1, true) or name:find("\\", 1, true) or name:find("..", 1, true)
end

function M.list_profiles()
    local vault = read_vault()
    local summary = {}
    for name, keys in pairs(vault.profiles or {}) do
        local non_empty = 0
        for k, v in pairs(keys) do
            if k ~= "_savedAt" and v ~= nil and v ~= "" then non_empty = non_empty + 1 end
        end
        local masked = {}
        for _, f in ipairs(VAULT_FIELDS) do masked[f[1]] = mask(keys[f[1]] or "") end
        table.insert(summary, {
            name = name, fieldsSet = non_empty, totalFields = #VAULT_FIELDS,
            savedAt = keys._savedAt or 0, masked = masked,
        })
    end
    local fields = {}
    for _, f in ipairs(VAULT_FIELDS) do table.insert(fields, { key = f[1], label = f[2] }) end
    return {
        success = true, profiles = st.A(summary),
        active = vault.active or "", fields = st.A(fields),
    }
end

function M.save_profile(name)
    name = st.trim(name or "main")
    if name == "" then name = "main" end
    if bad_name(name) then return { success = false, error = "Invalid profile name" } end

    local vault = read_vault()
    local keys = current_keys()
    keys._savedAt = math.floor(m_utils.time())
    vault.profiles[name] = keys
    if not vault.active or vault.active == "" then vault.active = name end
    write_vault(vault)

    local non_empty = 0
    for k, v in pairs(keys) do if k ~= "_savedAt" and v ~= "" then non_empty = non_empty + 1 end end
    logger.log("key_vault: saved profile '" .. name .. "' (" .. non_empty .. " fields)")
    return { success = true, name = name, fieldsSet = non_empty }
end

function M.load_profile(name)
    name = tostring(name or "")
    local vault = read_vault()
    local keys = vault.profiles[name]
    if not keys then return { success = false, error = "Profile '" .. name .. "' not found" } end

    local bulk, applied = {}, {}
    for _, f in ipairs(VAULT_FIELDS) do
        local value = keys[f[1]]
        if value and value ~= "" then
            local group = FIELD_GROUPS[f[1]] or "general"
            bulk[group] = bulk[group] or {}
            bulk[group][f[1]] = value
            table.insert(applied, f[1])
        end
    end
    if next(bulk) ~= nil then
        local ok, sm = pcall(require, "settings.manager")
        if ok and type(sm) == "table" and type(sm.apply_settings_bulk) == "function" then
            pcall(sm.apply_settings_bulk, bulk)
        end
    end

    vault.active = name
    write_vault(vault)
    logger.log("key_vault: loaded profile '" .. name .. "' (" .. #applied .. " fields)")
    return { success = true, name = name, applied = st.A(applied) }
end

function M.delete_profile(name)
    name = tostring(name or "")
    local vault = read_vault()
    if vault.profiles[name] == nil then return { success = false, error = "Profile '" .. name .. "' not found" } end
    vault.profiles[name] = nil
    if vault.active == name then
        vault.active = next(vault.profiles) or ""
    end
    write_vault(vault)
    return { success = true, deleted = name }
end

function M.export_profile(name)
    name = tostring(name or "")
    local vault = read_vault()
    local keys = vault.profiles[name]
    if not keys then return { success = false, error = "Profile '" .. name .. "' not found" } end

    local out_keys = {}
    for _, f in ipairs(VAULT_FIELDS) do out_keys[f[1]] = keys[f[1]] or "" end
    local payload = { format = "ltkeys-v1", name = name, exportedAt = math.floor(m_utils.time()), keys = out_keys }
    local encoded = m_utils.base64_encode(cjson.encode(payload))
    local preview = {}
    for _, f in ipairs(VAULT_FIELDS) do preview[f[1]] = mask(out_keys[f[1]]) end
    return { success = true, name = name, blob = encoded, preview = preview }
end

function M.import_profile(blob, name_override, activate)
    local ok, payload = pcall(function() return cjson.decode(st.b64decode(st.trim(blob or ""))) end)
    if not ok or type(payload) ~= "table" then return { success = false, error = "Import failed: bad blob" } end
    if payload.format ~= "ltkeys-v1" then return { success = false, error = "Invalid or unsupported format" } end
    if type(payload.keys) ~= "table" then return { success = false, error = "Malformed keys" } end

    local target = st.trim(name_override or "")
    if target == "" then target = payload.name or "imported" end
    if bad_name(target) then target = "imported" end

    local vault = read_vault()
    local keys = {}
    for k, v in pairs(payload.keys) do keys[k] = v end
    keys._savedAt = math.floor(m_utils.time())
    vault.profiles[target] = keys
    write_vault(vault)

    if activate == true then return M.load_profile(target) end

    local fieldsSet = 0
    for _, f in ipairs(VAULT_FIELDS) do if keys[f[1]] and keys[f[1]] ~= "" then fieldsSet = fieldsSet + 1 end end
    return { success = true, name = target, fieldsSet = fieldsSet }
end

return M
