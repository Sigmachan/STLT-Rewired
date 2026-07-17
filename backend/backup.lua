-- backup.lua — snapshot/restore of stplug-in + depotcache.
--
-- Faithful Lua port of the backup functions in steamtools.py. Python used
-- zipfile; Millennium's Lua has no zip module, so archives are created/extracted
-- via PowerShell Compress-Archive / Expand-Archive (Windows). Backups live in
-- backend/data/luatools_backups/. Archive layout (stplug-in/... + depotcache/...)
-- matches the Python format so old backups restore too.
--
-- On-machine-verified (shells to PowerShell; not exercised by the dev harness).

local m_utils = require("utils")
local fs      = require("fs")
local logger  = require("plugin_logger")
local st      = require("st_util")
local zip_util = require("zip_util")

local M = {}

local function backup_dir()
    local d = st.data_path("luatools_backups")
    if not fs.exists(d) then pcall(fs.create_directories, d) end
    return d
end

function M.create_backup(label)
    if type(label) == "table" then label = label.label end
    local base = st.steam_path()
    if base == "" then return { success = false, error = "Steam path not found" } end
    local stplug = st.lua_script_dir()
    local depot = fs.join(base, "depotcache")
    if (stplug == "" or not fs.is_directory(stplug)) and not fs.is_directory(depot) then
        return { success = false, error = "Nothing to backup" }
    end

    local sl = (tostring(label or ""):gsub("[^%w_%-]", "_")):sub(1, 32)
    local fname = "backup_" .. st.stamp() .. (sl ~= "" and ("_" .. sl) or "") .. ".zip"
    local zp = fs.join(backup_dir(), fname)

    local paths, fc = {}, 0
    if stplug ~= "" and fs.is_directory(stplug) then table.insert(paths, stplug) end
    if fs.is_directory(depot) then table.insert(paths, depot) end
    for _, p in ipairs(paths) do
        for _, e in ipairs(fs.list_recursive(p) or {}) do if e.is_file then fc = fc + 1 end end
    end

    if not zip_util.compress(paths, zp) then
        return { success = false, error = "zip compress failed" }
    end

    local sz = fs.file_size(zp) or 0
    logger.log("backup: created " .. fname .. " (" .. fc .. " files)")
    return { success = true, path = zp, filename = fname, fileCount = fc, sizeBytes = sz, sizeMB = st.mb(sz) }
end

function M.list_backups()
    local bd = backup_dir()
    if not fs.is_directory(bd) then return { success = true, backups = st.A({}), count = 0 } end
    local bk = {}
    for _, e in ipairs(fs.list(bd) or {}) do
        local n = e.name or ""
        if n:match("%.zip$") then
            local sz = fs.file_size(e.path) or 0
            table.insert(bk, {
                filename = n, path = e.path, sizeBytes = sz, sizeMB = st.mb(sz),
                created = st.fmt_ts(fs.last_write_time(e.path) or 0),
            })
        end
    end
    table.sort(bk, function(a, b) return a.filename > b.filename end)
    return { success = true, backups = st.A(bk), count = #bk }
end

function M.restore_backup(filename)
    if type(filename) == "table" then filename = filename.filename end
    filename = tostring(filename or "")
    local zp = fs.join(backup_dir(), filename)
    if not fs.is_file(zp) then return { success = false, error = "Not found" } end
    local base = st.steam_path()
    if base == "" then return { success = false, error = "Steam path not found" } end

    local tmp = fs.join(backup_dir(), ".restore_tmp_" .. math.floor(m_utils.time()))
    pcall(fs.remove_all, tmp)
    if not zip_util.extract(zp, tmp) then
        pcall(fs.remove_all, tmp)
        return { success = false, error = "zip extract failed" }
    end

    local routes = {
        ["stplug-in"] = fs.join(base, "config", "stplug-in"),
        ["lua"] = fs.join(base, "config", "lua"),
        ["depotcache"] = fs.join(base, "depotcache"),
    }
    local rc = 0
    for prefix, dest in pairs(routes) do
        local src = fs.join(tmp, prefix)
        if fs.is_directory(src) then
            pcall(fs.create_directories, dest)
            for _, e in ipairs(fs.list_recursive(src) or {}) do
                if e.is_file then
                    local rel = e.path:sub(#src + 1):gsub("^[/\\]+", "")
                    local target = fs.join(dest, rel)
                    pcall(fs.create_directories, fs.parent_path(target))
                    if fs.copy(e.path, target) then rc = rc + 1 end
                end
            end
        end
    end
    pcall(fs.remove_all, tmp)
    logger.log("backup: restored " .. rc .. " file(s) from " .. filename)
    return { success = true, restoredFiles = rc }
end

function M.delete_backup(filename)
    if type(filename) == "table" then filename = filename.filename end
    filename = tostring(filename or "")
    local zp = fs.join(backup_dir(), filename)
    if not fs.is_file(zp) then return { success = false, error = "Not found" } end
    local ok = fs.remove(zp)
    if ok == nil or ok == false then return { success = false, error = "delete failed" } end
    return { success = true }
end

return M
