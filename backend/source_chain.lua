-- source_chain.lua — customizable download-source priority pipeline.
--
-- Faithful Lua port of source_chain.py: reorder/enable/timeout/retries per
-- source, a free-API blacklist, and live per-source stats (pulled from the
-- history module when present). Stored in backend/data/source_chain.json.

local cjson   = require("json")
local m_utils = require("utils")
local fs      = require("fs")
local st      = require("st_util")

local M = {}

-- Default chain (matches the original hardcoded order).
local DEFAULT_CHAIN = {
    { id = "local",           name = "Local Folder",       enabled = true, timeout = 10,  retries = 0 },
    { id = "twentytwo",       name = "TwentyTwo Cloud",    enabled = true, timeout = 15,  retries = 1 },
    { id = "ryuu",            name = "Ryuu Premium",       enabled = true, timeout = 20,  retries = 1 },
    { id = "depotbox",        name = "DepotBox Premium",   enabled = true, timeout = 120, retries = 0 },
    { id = "manifesthub_api", name = "ManifestHub API",    enabled = true, timeout = 30,  retries = 1 },
    { id = "custom_apis",     name = "Custom APIs",        enabled = true, timeout = 20,  retries = 0 },
    { id = "free_apis",       name = "Free APIs",          enabled = true, timeout = 20,  retries = 0 },
    { id = "fallbacks",       name = "SLStools Fallbacks", enabled = true, timeout = 15,  retries = 1 },
    { id = "github_repos",    name = "GitHub Repos (SDO)", enabled = true, timeout = 30,  retries = 0 },
}

local function config_path() return st.data_path("source_chain.json") end

local function copy_entry(e)
    local t = {}
    for k, v in pairs(e) do t[k] = v end
    return t
end

local function default_chain_copy()
    local out = {}
    for _, e in ipairs(DEFAULT_CHAIN) do table.insert(out, copy_entry(e)) end
    return out
end

local function read_config()
    local path = config_path()
    if not fs.is_file(path) then return nil end
    local content = m_utils.read_file(path)
    if not content then return nil end
    local ok, data = pcall(cjson.decode, content)
    if ok and type(data) == "table" then return data end
    return nil
end

function M.load_chain()
    local cfg = read_config()
    if not cfg or type(cfg.chain) ~= "table" then return default_chain_copy() end
    local chain = cfg.chain
    local known = {}
    for _, s in ipairs(chain) do if s.id then known[s.id] = true end end
    for _, d in ipairs(DEFAULT_CHAIN) do
        if not known[d.id] then table.insert(chain, copy_entry(d)) end
    end
    return chain
end

function M.load_blacklist()
    local cfg = read_config()
    if cfg and type(cfg.blacklist) == "table" then return cfg.blacklist end
    return {}
end

function M.save_chain(chain)
    local config = { chain = st.A(chain), blacklist = st.A(M.load_blacklist()) }
    st.write_file(config_path(), cjson.encode(config))
end

function M.save_blacklist(blacklist)
    local cfg = read_config() or {}
    cfg.blacklist = st.A(blacklist)
    st.write_file(config_path(), cjson.encode(cfg))
end

-- Per-source stats from the history module, if it's been ported/loaded.
local function get_source_stats()
    local ok, history = pcall(require, "history")
    if ok and type(history) == "table" and type(history.get_stats_by_source) == "function" then
        local ok2, stats = pcall(history.get_stats_by_source)
        if ok2 and type(stats) == "table" then return stats end
    end
    return {}
end

function M.get_source_chain_json()
    local chain = M.load_chain()
    local stats = get_source_stats()
    for _, entry in ipairs(chain) do
        local ss = stats[entry.id] or stats[entry.name] or {}
        entry.stats = {
            total = ss.total or 0,
            success = ss.success or 0,
            failed = ss.failed or 0,
            success_rate = ss.success_rate ~= nil and ss.success_rate or st.null,
            avg_speed_kbps = ss.avg_speed_kbps ~= nil and ss.avg_speed_kbps or st.null,
            last_success_at = ss.last_success_at ~= nil and ss.last_success_at or st.null,
        }
    end
    return {
        success = true,
        chain = st.A(chain),
        blacklist = st.A(M.load_blacklist()),
        defaults = st.A(DEFAULT_CHAIN),
    }
end

function M.save_source_chain_json(chain_json)
    if type(chain_json) == "table" and chain_json.chain_json ~= nil then chain_json = chain_json.chain_json end
    local data
    if type(chain_json) == "string" then
        local ok, parsed = pcall(cjson.decode, chain_json)
        if not ok then return { success = false, error = tostring(parsed) } end
        data = parsed
    elseif type(chain_json) == "table" then
        data = chain_json
    else
        data = {}
    end
    if type(data) == "table" then
        if data.chain ~= nil then M.save_chain(data.chain) end
        if data.blacklist ~= nil then M.save_blacklist(data.blacklist) end
    end
    return { success = true }
end

return M
