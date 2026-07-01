-- acf_lock.lua — per-game update lock via appmanifest AutoUpdateBehavior.
--
-- Faithful Lua port of acf_writer.py set_game_update_lock / get_game_update_lock_status.
-- Locking sets AutoUpdateBehavior="1" (update only on launch) and marks the .acf
-- read-only so Steam can't silently rewrite it; unlocking reverses both. Only
-- that one ACF key is mutated — the rest of the file round-trips byte-for-byte.

local m_utils     = require("utils")
local fs          = require("fs")
local logger      = require("plugin_logger")
local steam_utils = require("steam_utils")

local M = {}

local function find_appmanifest_path(appid)
    local base = steam_utils.detect_steam_install_path()
    if not base or base == "" then return nil end
    local candidates = { base }
    local lib_vdf = fs.join(base, "config", "libraryfolders.vdf")
    if fs.is_file(lib_vdf) then
        local content = m_utils.read_file(lib_vdf) or ""
        for p in content:gmatch('"path"%s+"([^"]+)"') do
            local pp = p:gsub('\\\\', '\\')
            if pp ~= "" then table.insert(candidates, pp) end
        end
    end
    for _, lib in ipairs(candidates) do
        local acf = fs.join(lib, "steamapps", "appmanifest_" .. appid .. ".acf")
        if fs.is_file(acf) then return acf end
    end
    return nil
end

-- Set AutoUpdateBehavior to `value`, touching only that key (insert if absent).
local function set_acf_autoupdate(text, value)
    local replaced = false
    local new_text = text:gsub('("AutoUpdateBehavior"[ \t]*")([^"]*)(")', function(a, _b, c)
        replaced = true
        return a .. value .. c
    end, 1)
    if replaced then return new_text end

    local bstart, bend = text:find('"AppState"%s*{')
    if not bstart then return text end

    local indent, sep = "\t", "\t\t"
    local si, ss = text:sub(bend + 1):match('\n([ \t]*)"[^"]+"([ \t]+)"[^"]*"')
    if si then indent, sep = si, ss end

    local insert = "\n" .. indent .. '"AutoUpdateBehavior"' .. sep .. '"' .. value .. '"'
    return text:sub(1, bend) .. insert .. text:sub(bend + 1)
end

-- Windows read-only attribute via attrib (fs has no chmod).
local function apply_readonly(path, readonly)
    pcall(m_utils.exec, "attrib " .. (readonly and "+R" or "-R") .. ' "' .. path .. '"')
end

local function is_readonly(path)
    local ok, out = pcall(m_utils.exec, 'attrib "' .. path .. '"')
    if not ok or not out then return false end
    out = tostring(out)
    -- attrib prints flag letters, then the path; strip the path (drive-letter start).
    local flags = out:match("^(.-)%a:[/\\]") or out
    return flags:find("R") ~= nil
end

function M.set_game_update_lock(appid, lock)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "Invalid appid" } end
    lock = lock and true or false

    local path = find_appmanifest_path(appid)
    if not path then
        return { success = false, error = "appmanifest_" .. appid .. ".acf not found in any Steam library" }
    end

    -- clear read-only before rewriting (Windows can't replace/edit a read-only file)
    apply_readonly(path, false)

    local original = m_utils.read_file(path)
    if original == nil then return { success = false, error = "read failed" } end
    local updated = set_acf_autoupdate(original, lock and "1" or "0")
    local ok = m_utils.write_file(path, updated)
    if ok == false then return { success = false, error = "write failed" } end

    apply_readonly(path, lock)

    logger.log("acf_lock: " .. (lock and "Locked" or "Unlocked") .. " updates for " .. appid)
    return { success = true, appid = appid, locked = lock, path = path }
end

function M.get_game_update_lock_status(appid)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "Invalid appid" } end
    local path = find_appmanifest_path(appid)
    if not path then
        return { success = false, error = "appmanifest_" .. appid .. ".acf not found in any Steam library" }
    end
    local text = m_utils.read_file(path) or ""
    local behavior = text:match('"AutoUpdateBehavior"[ \t]*"([^"]*)"') or "0"
    return {
        success = true, appid = appid,
        autoUpdateBehavior = behavior,
        readOnly = is_readonly(path),
        locked = behavior == "1",
        path = path,
    }
end

return M
