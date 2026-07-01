-- st_util.lua — shared helpers for the ported SteamTools-Ultimate feature modules.
--
-- Faithful Lua equivalents of the small helpers that steamtools.py / paths.py
-- shared across every feature. Every ported cluster requires this module so the
-- behaviour (paths, sizes, timestamps, JSON array/null encoding) stays identical
-- to the original Python backend.

local cjson       = require("json")
local m_utils     = require("utils")
local fs          = require("fs")
local paths       = require("paths")
local steam_utils = require("steam_utils")
local http_client = require("http_client")

local M = {}

-- ── JSON helpers ─────────────────────────────────────────────────────────────
-- Millennium's json is OpenResty lua-cjson: array_mt forces array encoding
-- (empty -> [], sequence -> [...]); cjson.null encodes as JSON null. The Python
-- backend used json.dumps(), which emits [] and null, so the frontend depends on
-- these exact shapes.
M.ARRAY_MT = cjson.array_mt
M.null     = cjson.null

-- Pin encoding: empty plain tables -> {} (object), matching Python json.dumps of
-- an empty dict. Empty *arrays* still encode as [] via array_mt (see M.A).
pcall(cjson.encode_empty_table_as_object, true)

--- Force a Lua table to encode as a JSON array.
function M.A(t)
    return setmetatable(t or {}, M.ARRAY_MT)
end

-- ── Numbers ──────────────────────────────────────────────────────────────────

--- Round to `d` decimal places (default 0), matching Python round().
function M.round(n, d)
    n = tonumber(n) or 0
    if n ~= n then return 0 end -- NaN guard
    d = d or 0
    local mult = 10 ^ d
    return math.floor(n * mult + 0.5) / mult
end

function M.mb(bytes) return M.round((bytes or 0) / (1024 * 1024), 2) end
function M.gb(bytes) return M.round((bytes or 0) / (1024 * 1024 * 1024), 2) end

-- ── Paths ────────────────────────────────────────────────────────────────────

--- Steam install path ("" if not found). Cached inside steam_utils.
function M.steam_path()
    local p = steam_utils.detect_steam_install_path()
    return p or ""
end

--- <Steam>/config/stplug-in ("" if Steam not found).
function M.stplug_dir()
    local base = M.steam_path()
    if base == "" then return "" end
    return fs.join(base, "config", "stplug-in")
end

--- Windows: %LOCALAPPDATA%\Steam (holds htmlcache/shadercache mirrors).
function M.localappdata_steam()
    local la = m_utils.getenv("LOCALAPPDATA")
    if la and la ~= "" then return fs.join(la, "Steam") end
    return ""
end

--- backend/data directory (mirrors paths.data_path in Python; created on demand).
function M.data_dir()
    local d = paths.backend_path("data")
    if not fs.exists(d) then pcall(fs.create_directories, d) end
    return d
end

--- Absolute path inside backend/data (returns the dir itself when name is empty).
function M.data_path(name)
    if not name or name == "" then return M.data_dir() end
    return fs.join(M.data_dir(), name)
end

-- ── Sizes ────────────────────────────────────────────────────────────────────

--- Recursive byte size of a directory (0 if missing).
function M.dir_size(path)
    if not path or path == "" or not fs.is_directory(path) then return 0 end
    local total = 0
    local entries = fs.list_recursive(path)
    if entries then
        for _, e in ipairs(entries) do
            if e.is_file then
                local sz = fs.file_size(e.path)
                if sz then total = total + sz end
            end
        end
    end
    return total
end

-- ── Time ─────────────────────────────────────────────────────────────────────

function M.stamp() return os.date("%Y%m%d_%H%M%S") end

function M.fmt_ts(t) return os.date("%Y-%m-%d %H:%M:%S", t) end

-- ── File I/O passthroughs (byte-clean via Millennium utils) ──────────────────

function M.read_file(path) return m_utils.read_file(path) end

function M.write_file(path, content) return m_utils.write_file(path, content) end

-- ── Misc ─────────────────────────────────────────────────────────────────────

--- Trim leading/trailing whitespace.
function M.trim(s)
    return (tostring(s or ""):match("^%s*(.-)%s*$"))
end

--- Is Steam currently running? (Windows tasklist probe.)
function M.steam_is_running()
    local ok, out = pcall(m_utils.exec, 'tasklist /FI "IMAGENAME eq steam.exe" /FO CSV /NH')
    if ok and out then
        return tostring(out):lower():find("steam.exe") ~= nil
    end
    return false
end

--- Trim trailing whitespace only (Python str.rstrip()).
function M.rtrim(s)
    return (tostring(s or ""):gsub("%s+$", ""))
end

--- Split text into lines, matching Python file.readlines() line counting:
--- a trailing newline does NOT yield an extra empty final line.
function M.split_lines(content)
    content = tostring(content or "")
    local lines = {}
    local start = 1
    while true do
        local nl = content:find("\n", start, true)
        if nl then
            table.insert(lines, content:sub(start, nl - 1))
            start = nl + 1
        else
            if start <= #content then table.insert(lines, content:sub(start)) end
            break
        end
    end
    return lines
end

--- Read <appid>.lua (or .lua.disabled) from stplug-in. Returns (content, path)
--- or (nil, errmsg). Shared by feature modules.
function M.read_lua_file(appid)
    local stplug = M.stplug_dir()
    if stplug == "" then return nil, "Steam path not found" end
    for _, ext in ipairs({ ".lua", ".lua.disabled" }) do
        local p = fs.join(stplug, tostring(appid) .. ext)
        if fs.is_file(p) then
            local content = m_utils.read_file(p)
            if content then return content, p end
            return nil, "read failed"
        end
    end
    return nil, "Lua file not found"
end

--- Depot IDs carrying a decryption key: addappid(id, N, "hex"). Returns a sorted
--- array of id strings.
function M.get_depot_ids_from_lua(content)
    local seen, out = {}, {}
    for line in (tostring(content) .. "\n"):gmatch("([^\n]*)\n") do
        local did = line:match('addappid%s*%(%s*(%d+)%s*,%s*%d+%s*,%s*"%x+"')
        if did and not seen[did] then
            seen[did] = true
            table.insert(out, did)
        end
    end
    table.sort(out, function(a, b) return tonumber(a) < tonumber(b) end)
    return out
end

--- Resolve a depot's public manifest gid from steamcmd depots data.
function M.get_manifest_id(depots_data, depot_id)
    if type(depots_data) ~= "table" then return nil end
    local d = depots_data[depot_id]
    if type(d) ~= "table" then return nil end
    local m = d.manifests
    if type(m) ~= "table" then return nil end
    local pub = m.public
    if type(pub) == "table" then return tostring(pub.gid or "") end
    if type(pub) == "string" and M.trim(pub) ~= "" then return M.trim(pub) end
    return nil
end

-- steamcmd app info (name / depots / workshop / dlc list), cached per process.
local APP_INFO_CACHE = {}
function M.fetch_app_info(appid)
    if APP_INFO_CACHE[appid] ~= nil then return APP_INFO_CACHE[appid] end
    local out = { depots = {}, name = "", workshop_depot = 0, dlc_list = "" }
    local ok, resp = pcall(http_client.get, "https://api.steamcmd.net/v1/info/" .. tostring(appid), { timeout = 10 })
    if ok and resp and resp.status == 200 and resp.body then
        local ok2, parsed = pcall(cjson.decode, resp.body)
        if ok2 and type(parsed) == "table" and type(parsed.data) == "table" then
            local root = parsed.data[tostring(appid)]
            if type(root) == "table" then
                local depots = type(root.depots) == "table" and root.depots or {}
                local common = type(root.common) == "table" and root.common or {}
                local extended = type(root.extended) == "table" and root.extended or {}
                out = {
                    depots = depots, name = common.name or "",
                    workshop_depot = depots.workshopdepot or 0, dlc_list = extended.listofdlc or "",
                }
            end
        end
    end
    APP_INFO_CACHE[appid] = out
    return out
end

-- Manifest present in either depotcache location, non-empty. Returns path or nil.
function M.find_manifest_file(base, depot_id, manifest_id)
    local fname = depot_id .. "_" .. manifest_id .. ".manifest"
    for _, subdir in ipairs({ "depotcache", fs.join("config", "depotcache") }) do
        local fp = fs.join(base, subdir, fname)
        if fs.is_file(fp) then
            local sz = fs.file_size(fp)
            if sz and sz > 0 then return fp end
        end
    end
    return nil
end

-- Steam manifest magic bytes 0x27 0x44 0x56 0x01 (cheap 4-byte read via io).
function M.verify_manifest_magic(path)
    local f = io.open(path, "rb")
    if not f then return false end
    local magic = f:read(4)
    f:close()
    return magic == "\39\68\86\1"
end

-- Base64 decode (Millennium utils has base64_encode but not decode).
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function M.b64decode(data)
    data = tostring(data or ""):gsub("[^" .. B64 .. "=]", "")
    return (data:gsub(".", function(x)
        if x == "=" then return "" end
        local r, f = "", (B64:find(x, 1, true) - 1)
        for i = 6, 1, -1 do r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and "1" or "0") end
        return r
    end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
        if #x ~= 8 then return "" end
        local c = 0
        for i = 1, 8 do c = c + (x:sub(i, i) == "1" and 2 ^ (8 - i) or 0) end
        return string.char(c)
    end))
end

return M
