-- config_transfer.lua — full plugin config export/import.
--
-- Faithful Lua port of config_transfer.py. Exports settings, source chain +
-- blacklist, custom APIs, hooks, and the free-API manifest; import merges each
-- section independently, collecting per-section errors. Sections whose backing
-- module isn't present are skipped gracefully (mirrors the Python try/except).

local cjson   = require("json")
local m_utils = require("utils")
local fs      = require("fs")
local st      = require("st_util")

local M = {}

local VERSION = "1.0"

function M.export_config()
    local config = {
        _meta = { version = VERSION, exported_at = m_utils.time(), plugin = "STLT - Rewired" },
    }

    -- 1. settings
    config.settings = {}
    local ok_s, sm = pcall(require, "settings.manager")
    if ok_s and type(sm) == "table" then
        if type(sm.get_settings_state) == "function" then
            local ok, s = pcall(sm.get_settings_state)
            if ok and type(s) == "table" then config.settings = s.values or s end
        elseif type(sm.get_settings_payload) == "function" then
            local ok, s = pcall(sm.get_settings_payload)
            if ok and type(s) == "table" then config.settings = s.values or s end
        end
    end

    -- 2. source chain
    local ok_sc, sc = pcall(require, "source_chain")
    if ok_sc and type(sc) == "table" then
        local okc, chain = pcall(sc.load_chain)
        if okc and type(chain) == "table" then config.source_chain = st.A(chain) end
        local okb, bl = pcall(sc.load_blacklist)
        if okb and type(bl) == "table" then config.source_blacklist = st.A(bl) end
    end

    -- 3. custom APIs
    local ok_ca, ca = pcall(require, "custom_apis")
    if ok_ca and type(ca) == "table" and type(ca.get_custom_apis) == "function" then
        local ok, res = pcall(ca.get_custom_apis)
        if ok and type(res) == "table" then config.custom_apis = st.A(res.apis or {}) end
    end

    -- 4. hooks
    local ok_h, ev = pcall(require, "events")
    if ok_h and type(ev) == "table" and type(ev._load_hooks_config) == "function" then
        local ok, h = pcall(ev._load_hooks_config)
        if ok then config.hooks = h end
    end

    -- 5. API manifest
    local mp = st.data_path("api_manifest.json")
    if fs.is_file(mp) then
        local content = m_utils.read_file(mp)
        if content then
            local ok, data = pcall(cjson.decode, content)
            if ok then config.api_manifest = data end
        end
    end

    return { success = true, config = config }
end

function M.import_config(config_json)
    if type(config_json) == "table" and config_json.config_json ~= nil then config_json = config_json.config_json end
    local data
    if type(config_json) == "string" then
        local ok, parsed = pcall(cjson.decode, config_json)
        if not ok then return { success = false, error = tostring(parsed) } end
        data = parsed
    elseif type(config_json) == "table" then
        data = config_json
    else
        return { success = false, error = "Invalid config" }
    end
    if type(data) == "table" and data.config ~= nil then data = data.config end
    if type(data) ~= "table" then return { success = false, error = "Invalid config" } end

    local imported, errors = {}, {}

    -- 1. settings
    if data.settings ~= nil and next(data.settings) ~= nil then
        local ok_s, sm = pcall(require, "settings.manager")
        if ok_s and type(sm) == "table" and type(sm.apply_settings_changes) == "function" then
            local settings_payload = data.settings
            if type(settings_payload) == "table" and type(settings_payload.values) == "table" then
                settings_payload = settings_payload.values
            end
            local ok, err = pcall(sm.apply_settings_changes, settings_payload)
            if ok and type(err) == "table" and err.success == false then
                table.insert(errors, "settings: " .. tostring(err.error or "apply failed"))
            elseif ok then
                table.insert(imported, "settings")
            else
                table.insert(errors, "settings: " .. tostring(err))
            end
        else
            table.insert(errors, "settings: unsupported")
        end
    end

    -- 2. source chain
    if data.source_chain ~= nil then
        local ok_sc, sc = pcall(require, "source_chain")
        if ok_sc and type(sc) == "table" then
            local ok, err = pcall(function()
                sc.save_chain(data.source_chain)
                if data.source_blacklist ~= nil then sc.save_blacklist(data.source_blacklist) end
            end)
            if ok then table.insert(imported, "source_chain") else table.insert(errors, "source_chain: " .. tostring(err)) end
        else
            table.insert(errors, "source_chain: unsupported")
        end
    end

    -- 3. custom APIs
    if data.custom_apis ~= nil then
        local ok_ca, ca = pcall(require, "custom_apis")
        if ok_ca and type(ca) == "table" and type(ca.save_custom_apis) == "function" then
            local ok, err = pcall(ca.save_custom_apis, cjson.encode(st.A(data.custom_apis)))
            if ok then table.insert(imported, "custom_apis") else table.insert(errors, "custom_apis: " .. tostring(err)) end
        else
            table.insert(errors, "custom_apis: unsupported")
        end
    end

    -- 4. hooks
    if data.hooks ~= nil then
        local ok_h, ev = pcall(require, "events")
        if ok_h and type(ev) == "table" and type(ev.save_hooks_config) == "function" then
            local ok, err = pcall(ev.save_hooks_config, data.hooks)
            if ok then table.insert(imported, "hooks") else table.insert(errors, "hooks: " .. tostring(err)) end
        else
            table.insert(errors, "hooks: unsupported")
        end
    end

    -- 5. API manifest
    if data.api_manifest ~= nil then
        local ok, err = pcall(function()
            st.write_file(st.data_path("api_manifest.json"), cjson.encode(data.api_manifest))
        end)
        if ok then table.insert(imported, "api_manifest") else table.insert(errors, "api_manifest: " .. tostring(err)) end
    end

    return { success = #errors == 0, imported = st.A(imported), errors = st.A(errors) }
end

return M
