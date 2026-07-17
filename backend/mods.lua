-- mods.lua — plugin-within-plugin mod loader (Kite-compatible).
--
-- Faithful Lua port of mod_system.py. Scans <plugin>/mods for folder mods
-- (manifest.json + mod.js) and single-file .js mods, serves files with path-
-- traversal protection, and manages enable/disable state in mods_config.json.
-- install_mod_from_url downloads an HTTPS ZIP (SSRF-guarded) and extracts it via
-- PowerShell Expand-Archive (Windows).

local cjson   = require("json")
local m_utils = require("utils")
local fs      = require("fs")
local paths   = require("paths")
local logger  = require("plugin_logger")
local st      = require("st_util")

local M = {}

local MOD_LOADER_VERSION = "1.0.0"
local MAX_ZIP_SIZE = 100 * 1024 * 1024

-- ── helpers ──────────────────────────────────────────────────────────────────

local function is_safe_mod_id(mod_id)
    mod_id = tostring(mod_id or "")
    if #mod_id < 1 or #mod_id > 80 then return false end
    return mod_id:match("^[%w_%.%-]+$") ~= nil
end

local function path_is_within(base, candidate)
    local b = (fs.absolute(base) or base):gsub("[/\\]+$", ""):lower()
    local t = (fs.absolute(candidate) or candidate):lower()
    return t == b or t:sub(1, #b + 1) == (b .. "\\") or t:sub(1, #b + 1) == (b .. "/")
end

local function is_safe_download_url(url)
    url = tostring(url or "")
    if url:sub(1, 8):lower() ~= "https://" then return false end
    if url:match("^https://[^/]*@") then return false end -- reject credentials
    local host = url:match("^https://([^/:@]+)")
    if not host then return false end
    host = host:lower():gsub("%.$", "")
    if host == "localhost" or host == "127.0.0.1" or host == "::1" then return false end
    local a, b = host:match("^(%d+)%.(%d+)%.")
    if a then
        a, b = tonumber(a), tonumber(b)
        if a == 10 or a == 127 then return false end
        if a == 192 and b == 168 then return false end
        if a == 172 and b >= 16 and b <= 31 then return false end
        if a == 169 and b == 254 then return false end
    end
    return true
end

local function get_mods_dir()
    local d = fs.join(paths.get_plugin_dir(), "mods")
    if not fs.exists(d) then pcall(fs.create_directories, d) end
    return d
end

local function config_path() return fs.join(get_mods_dir(), "mods_config.json") end

local config_cache = nil
local config_mtime = 0

local function load_config()
    local path = config_path()
    if not fs.is_file(path) then return {} end
    local mtime = fs.last_write_time(path) or 0
    if config_cache ~= nil and mtime == config_mtime then return config_cache end
    local content = m_utils.read_file(path)
    if not content then return {} end
    local ok, data = pcall(cjson.decode, content)
    if ok and type(data) == "table" then
        config_cache = data
        config_mtime = mtime
        return data
    end
    return {}
end

local function save_config(config)
    local path = config_path()
    st.write_file(path, cjson.encode(config))
    config_cache = config
    config_mtime = fs.last_write_time(path) or 0
end

-- ── discovery ────────────────────────────────────────────────────────────────

function M.get_mod_list()
    local mods_dir = get_mods_dir()
    local config = load_config()
    local mods = {}
    if not fs.is_directory(mods_dir) then return st.A(mods) end

    local entries = fs.list(mods_dir) or {}
    table.sort(entries, function(a, b) return (a.name or "") < (b.name or "") end)

    for _, e in ipairs(entries) do
        local name = e.name or ""
        if name ~= "mods_config.json" then
            if e.is_file and name:match("%.js$") then
                local mod_id = name:sub(1, #name - 3)
                if is_safe_mod_id(mod_id) then
                    local enabled = config[mod_id]
                    if enabled == nil then enabled = true end
                    table.insert(mods, {
                        id = mod_id, name = mod_id, version = "1.0.0", author = "Unknown",
                        description = "Single-file mod", main = name, style = cjson.null,
                        enabled = enabled, type = "single-file",
                        hooks = st.A({}), dependencies = st.A({}),
                    })
                else
                    logger.warn("mods: skipping single-file mod " .. name .. ": unsafe name")
                end
            elseif e.is_directory then
                local manifest_path = fs.join(e.path, "manifest.json")
                if fs.is_file(manifest_path) then
                    local content = m_utils.read_file(manifest_path)
                    local ok, manifest = pcall(cjson.decode, content or "")
                    if ok and type(manifest) == "table" then
                        local mod_id = tostring(manifest.id or name)
                        if is_safe_mod_id(mod_id) then
                            local enabled = config[mod_id]
                            if enabled == nil then enabled = true end
                            table.insert(mods, {
                                id = mod_id,
                                name = manifest.name or name,
                                version = manifest.version or "1.0.0",
                                author = manifest.author or "Unknown",
                                description = manifest.description or "",
                                main = manifest.main or "mod.js",
                                style = manifest.style ~= nil and manifest.style or cjson.null,
                                enabled = enabled, type = "folder",
                                hooks = st.A(type(manifest.hooks) == "table" and manifest.hooks or {}),
                                dependencies = st.A(type(manifest.dependencies) == "table" and manifest.dependencies or {}),
                                repository = manifest.repository or "",
                                minLuaToolsVersion = manifest.minLuaToolsVersion or "",
                            })
                        else
                            logger.warn("mods: skipping " .. name .. ": unsafe mod id")
                        end
                    else
                        logger.warn("mods: skipping " .. name .. ": bad manifest.json")
                    end
                end
            end
        end
    end
    return st.A(mods)
end

-- Returns raw file content (not JSON) or "" — matches Python get_mod_file.
function M.get_mod_file(mod_id, filename)
    if not is_safe_mod_id(mod_id) then return "" end
    filename = tostring(filename or "")
    if filename:find("..", 1, true) then return "" end
    filename = filename:gsub("\\", "/")
    if filename:sub(1, 1) == "/" or filename:find("..", 1, true) then return "" end

    local mods_dir = get_mods_dir()
    local folder_path = fs.join(mods_dir, mod_id, filename)
    if path_is_within(mods_dir, folder_path) and fs.is_file(folder_path) then
        return m_utils.read_file(folder_path) or ""
    end
    if filename:match("%.js$") then
        local single = fs.join(mods_dir, filename)
        if path_is_within(mods_dir, single) and fs.is_file(single) then
            return m_utils.read_file(single) or ""
        end
    end
    return ""
end

function M.toggle_mod(mod_id, enabled)
    if not is_safe_mod_id(mod_id) then return { success = false, error = "Invalid mod_id" } end
    if enabled == nil then enabled = true end
    local config = load_config()
    config[mod_id] = enabled
    save_config(config)
    logger.log("mods: '" .. mod_id .. "' " .. (enabled and "enabled" or "disabled"))
    return { success = true, mod_id = mod_id, enabled = enabled }
end

function M.get_mod_loader_info()
    local mods_dir = get_mods_dir()
    local count = 0
    if fs.is_directory(mods_dir) then
        for _, e in ipairs(fs.list(mods_dir) or {}) do
            local n = e.name or ""
            if n ~= "mods_config.json" then
                if e.is_directory and fs.is_file(fs.join(e.path, "manifest.json")) then
                    count = count + 1
                elseif e.is_file and n:match("%.js$") then
                    count = count + 1
                end
            end
        end
    end
    return {
        version = MOD_LOADER_VERSION, mods_dir = mods_dir,
        mod_count = count, compatible_with = "kite-loader",
    }
end

function M.uninstall_mod(mod_id)
    if not is_safe_mod_id(mod_id) then return { success = false, error = "Invalid mod_id" } end
    local mods_dir = get_mods_dir()
    local folder = fs.join(mods_dir, mod_id)
    if fs.is_directory(folder) and path_is_within(mods_dir, folder) then
        fs.remove_all(folder)
        logger.log("mods: uninstalled '" .. mod_id .. "'")
        return { success = true }
    end
    local single = fs.join(mods_dir, mod_id .. ".js")
    if fs.is_file(single) and path_is_within(mods_dir, single) then
        fs.remove(single)
        return { success = true }
    end
    return { success = false, error = "Mod not found" }
end

-- Install from an HTTPS ZIP URL. Extract via PowerShell Expand-Archive (Windows).
function M.install_mod_from_url(url)
    url = st.trim(tostring(url or ""))
    if not is_safe_download_url(url) then
        return { success = false, error = "Only HTTPS mod ZIP URLs from public hosts are allowed" }
    end
    local ok, result = pcall(function()
        local http_client = require("http_client")
        local mods_dir = get_mods_dir()
        local tmp = fs.join(mods_dir, ".ltmod_tmp_" .. tostring(math.floor(m_utils.time())))
        fs.create_directories(tmp)
        local zip_path = fs.join(tmp, "mod.zip")
        local extract_dir = fs.join(tmp, "extracted")

        local resp = http_client.get(url, { timeout = 30 })
        if not (resp and resp.status == 200 and resp.body) then
            fs.remove_all(tmp)
            return { success = false, error = "Download failed" }
        end
        if #resp.body > MAX_ZIP_SIZE then
            fs.remove_all(tmp)
            return { success = false, error = "Archive too large: " .. #resp.body .. " bytes" }
        end
        local f = io.open(zip_path, "wb")
        if not f then fs.remove_all(tmp); return { success = false, error = "write failed" } end
        f:write(resp.body); f:close()

        local zip_util = require("zip_util")
        if not zip_util.extract(zip_path, extract_dir) then
            fs.remove_all(tmp)
            return { success = false, error = "Archive extract failed" }
        end

        local manifest, manifest_dir = nil, nil
        for _, e in ipairs(fs.list_recursive(extract_dir) or {}) do
            if e.is_file and (e.name or "") == "manifest.json" then
                local okm, parsed = pcall(cjson.decode, m_utils.read_file(e.path) or "")
                if okm and type(parsed) == "table" then
                    manifest = parsed
                    manifest_dir = fs.parent_path(e.path)
                    break
                end
            end
        end
        if not manifest or not manifest_dir then
            fs.remove_all(tmp)
            return { success = false, error = "No manifest.json found in archive" }
        end
        local mod_id = st.trim(tostring(manifest.id or ""))
        if not is_safe_mod_id(mod_id) then
            fs.remove_all(tmp)
            return { success = false, error = "manifest.json contains an invalid mod id" }
        end
        local dest = fs.join(mods_dir, mod_id)
        if not path_is_within(mods_dir, dest) then
            fs.remove_all(tmp)
            return { success = false, error = "Invalid mod destination" }
        end
        if fs.exists(dest) then fs.remove_all(dest) end
        fs.copy_recursive(manifest_dir, dest)
        fs.remove_all(tmp)
        logger.log("mods: installed '" .. mod_id .. "' from " .. url)
        return { success = true, mod_id = mod_id, name = manifest.name or mod_id }
    end)
    if not ok then return { success = false, error = tostring(result) } end
    return result
end

return M
