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

return M
