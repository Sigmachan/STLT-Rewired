-- events.lua — hook system for download-lifecycle events.
--
-- Faithful Lua port of events.py. Config (hooks.json) load/save + the IPC
-- get/save, plus emit/dispatch with webhook (Discord/ntfy/generic) and exec
-- hooks. Python dispatched on a background thread; Lua is single-threaded so
-- emit() runs hooks inline (each guarded) — a download-complete webhook briefly
-- blocks, which is acceptable for fire-and-forget notifications.

local cjson   = require("json")
local m_utils = require("utils")
local fs      = require("fs")
local logger  = require("plugin_logger")
local st      = require("st_util")

local M = {}

-- ── internal listeners (parity; used by the pipeline when wired) ──────────────

local listeners = {}

function M.on(event, callback)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], callback)
end

function M.off(event, callback)
    if callback == nil then
        listeners[event] = nil
    elseif listeners[event] then
        local kept = {}
        for _, cb in ipairs(listeners[event]) do
            if cb ~= callback then table.insert(kept, cb) end
        end
        listeners[event] = kept
    end
end

-- ── config load/save (mtime-cached) ──────────────────────────────────────────

local function hooks_config_path() return st.data_path("hooks.json") end

local hooks_cache = nil
local hooks_mtime = 0

function M.load_hooks_config()
    local path = hooks_config_path()
    if not fs.is_file(path) then return {} end
    local mtime = fs.last_write_time(path) or 0
    if hooks_cache ~= nil and mtime == hooks_mtime then return hooks_cache end
    local content = m_utils.read_file(path)
    if not content then return {} end
    local ok, data = pcall(cjson.decode, content)
    if ok and type(data) == "table" then
        hooks_cache = data
        hooks_mtime = mtime
        return data
    end
    return {}
end

-- alias used by config_transfer
M._load_hooks_config = M.load_hooks_config

function M.save_hooks_config(config)
    local path = hooks_config_path()
    st.write_file(path, cjson.encode(config))
    hooks_cache = config
    hooks_mtime = fs.last_write_time(path) or 0
end

-- ── payload formatting + handlers ────────────────────────────────────────────

local function format_payload(payload)
    local parts = {}
    if payload.appid ~= nil then table.insert(parts, "AppID: " .. tostring(payload.appid)) end
    if payload.name ~= nil then table.insert(parts, "Game: " .. tostring(payload.name)) end
    if payload.source ~= nil then table.insert(parts, "Source: " .. tostring(payload.source)) end
    if payload.error ~= nil then table.insert(parts, "Error: " .. tostring(payload.error)) end
    if payload.success ~= nil then
        table.insert(parts, "Success: " .. tostring(payload.success) .. "/" .. tostring(payload.total or "?"))
    end
    if payload.failed ~= nil then table.insert(parts, "Failed: " .. tostring(payload.failed)) end
    if #parts > 0 then return table.concat(parts, " | ") end
    return cjson.encode(payload)
end

local function fire_webhook(url, payload, extra_headers)
    local ok_h, http = pcall(require, "http")
    if not ok_h or type(http) ~= "table" or type(http.post) ~= "function" then
        logger.warn("events: HTTP client unavailable for webhook")
        return
    end
    local headers = { ["Content-Type"] = "application/json", ["User-Agent"] = "STLT-Rewired-Hooks/1.0" }
    if type(extra_headers) == "table" then for k, v in pairs(extra_headers) do headers[k] = v end end
    local event = tostring(payload.event or "unknown")
    local ok = pcall(function()
        if url:find("discord.com/api/webhooks", 1, true) then
            local color = event:find("fail", 1, true) and 0xf44336 or 0x66c0f4
            local body = cjson.encode({
                content = cjson.null,
                embeds = { { title = "STLT: " .. event, description = format_payload(payload), color = color } },
            })
            http.post(url, body, { headers = headers, timeout = 10 })
        elseif url:find("ntfy.sh", 1, true) or url:find("/ntfy.", 1, true) then
            headers["Title"] = "STLT: " .. event
            headers["Priority"] = event:find("fail", 1, true) and "high" or "default"
            headers["Content-Type"] = nil
            http.post(url, format_payload(payload), { headers = headers, timeout = 10 })
        else
            http.post(url, cjson.encode(payload), { headers = headers, timeout = 10 })
        end
    end)
    if not ok then logger.warn("events: webhook POST failed for " .. tostring(url)) end
end

local function fire_exec(command_template, payload)
    local cmd = tostring(command_template or "")
    for key, val in pairs(payload) do
        local rep = tostring(val):gsub("%%", "%%%%")
        cmd = cmd:gsub("{" .. key .. "}", rep)
    end
    if st.trim(cmd) == "" then return end
    local is_win = (m_utils.getenv("OS") or ""):find("Windows") ~= nil
    pcall(function()
        if is_win then
            os.execute('start "" /b ' .. cmd)
        else
            os.execute(cmd .. " >/dev/null 2>&1 &")
        end
    end)
end

function M.emit(event, data)
    local payload = { event = event }
    if type(data) == "table" then for k, v in pairs(data) do payload[k] = v end end

    local cbs = {}
    for _, cb in ipairs(listeners[event] or {}) do table.insert(cbs, cb) end
    for _, cb in ipairs(listeners["*"] or {}) do table.insert(cbs, cb) end
    for _, cb in ipairs(cbs) do pcall(cb, payload) end

    local hooks = M.load_hooks_config()
    for _, hook in ipairs(hooks[event] or {}) do
        local ht = hook.type or ""
        if ht == "webhook" and hook.url then
            fire_webhook(hook.url, payload, hook.headers)
        elseif ht == "exec" and hook.command then
            fire_exec(hook.command, payload)
        end
    end
end

-- ── IPC ──────────────────────────────────────────────────────────────────────

function M.get_hooks_config()
    return { success = true, hooks = M.load_hooks_config() }
end

function M.save_hooks_config_json(config_json)
    if type(config_json) == "table" and config_json.config_json ~= nil then config_json = config_json.config_json end
    local config
    if type(config_json) == "string" then
        local ok, parsed = pcall(cjson.decode, config_json)
        if not ok then return { success = false, error = tostring(parsed) } end
        config = parsed
    elseif type(config_json) == "table" then
        config = config_json
    else
        config = {}
    end
    if type(config) ~= "table" then return { success = false, error = "Invalid hooks config" } end
    M.save_hooks_config(config)
    return { success = true }
end

return M
