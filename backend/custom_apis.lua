-- custom_apis.lua — user-defined download source endpoints.
--
-- Faithful Lua port of custom_apis.py. Each API: name, url (must contain the
-- <appid> placeholder), api_key (optional), enabled. Stored in
-- backend/data/custom_apis.json as { "apis": [...] }.

local cjson   = require("json")
local m_utils = require("utils")
local fs      = require("fs")
local logger  = require("plugin_logger")
local st      = require("st_util")

local M = {}

local FILE = "custom_apis.json"

local function apis_path() return st.data_path(FILE) end

function M.get_custom_apis()
    local fp = apis_path()
    if not fs.is_file(fp) then return { success = true, apis = st.A({}) } end
    local content = m_utils.read_file(fp)
    if not content then return { success = true, apis = st.A({}) } end
    local ok, data = pcall(cjson.decode, content)
    if not ok then
        logger.warn("custom_apis: failed to load: " .. tostring(data))
        return { success = true, apis = st.A({}) }
    end
    local apis
    if type(data) == "table" and data.apis ~= nil then
        apis = data.apis
    else
        apis = data
    end
    if type(apis) ~= "table" then apis = {} end
    return { success = true, apis = st.A(apis) }
end

function M.save_custom_apis(apis_json)
    if type(apis_json) == "table" and apis_json.apis_json ~= nil then apis_json = apis_json.apis_json end
    local ok, apis = pcall(cjson.decode, tostring(apis_json))
    if not ok then return { success = false, error = "Invalid JSON" } end
    if type(apis) ~= "table" then return { success = false, error = "Expected a JSON array" } end
    -- Reject a non-empty JSON object (only arrays are valid here).
    if next(apis) ~= nil and #apis == 0 then
        return { success = false, error = "Expected a JSON array" }
    end

    local cleaned = {}
    for _, api in ipairs(apis) do
        if type(api) == "table" then
            local name = st.trim(tostring(api.name or ""))
            local url = st.trim(tostring(api.url or ""))
            if name ~= "" and url ~= "" then
                if not url:find("<appid>", 1, true) then
                    return { success = false, error = "API '" .. name .. "' URL must contain <appid> placeholder" }
                end
                table.insert(cleaned, {
                    name = name,
                    url = url,
                    api_key = st.trim(tostring(api.api_key or "")),
                    enabled = api.enabled ~= false,
                })
            end
        end
    end

    st.write_file(apis_path(), cjson.encode({ apis = st.A(cleaned) }))
    logger.log("custom_apis: saved " .. #cleaned .. " endpoint(s)")
    return { success = true, count = #cleaned }
end

-- Enabled custom APIs only (for the download pipeline). Returns a Lua array.
function M.get_enabled_custom_apis()
    local res = M.get_custom_apis()
    local out = {}
    for _, a in ipairs(res.apis or {}) do
        if a.enabled then table.insert(out, a) end
    end
    return out
end

return M
