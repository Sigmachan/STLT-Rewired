-- steam_version.lua — Steam client version + self-update block manager.
--
-- Faithful Lua port of steam_version.py (safe subset): detect the installed
-- client build from steam.inf, report SteamTools compatibility, and (un)block
-- Steam self-update via <Steam>/steam.cfg (reversible, backed up). Never touches
-- client binaries.

local m_utils     = require("utils")
local fs          = require("fs")
local logger      = require("plugin_logger")
local steam_utils = require("steam_utils")
local st          = require("st_util")

local M = {}

-- Advisory data only (build id == ClientVersion in steam.inf), newest first.
local KNOWN_COMPATIBLE_VERSIONS = {
    { version = "1773426488", label = "Mar 13 2026 - SteamTools compatible" },
    { version = "1773099986", label = "Mar 10 2026" },
    { version = "1769025840", label = "Jan 22 2026" },
    { version = "1766451605", label = "Dec 23 2025" },
    { version = "1766177208", label = "Dec 19 2025" },
    { version = "1763795278", label = "Nov 26 2025" },
}

local BLOCK_CFG = "BootStrapperInhibitAll=enable\nBootStrapperForceSelfUpdate=disable\n"

local function read_steam_inf(root)
    local info = {}
    local content = m_utils.read_file(fs.join(root, "steam.inf"))
    if not content then return info end
    for line in (content .. "\n"):gmatch("([^\n]*)\n") do
        local l = st.trim(line)
        if l ~= "" and l:sub(1, 1) ~= "#" and l:find("=", 1, true) then
            local k, v = l:match("^([^=]*)=(.*)$")
            if k then info[st.trim(k)] = st.trim(v) end
        end
    end
    return info
end

local function cfg_blocks_updates(content)
    return tostring(content or ""):lower():gsub(" ", ""):find("bootstrapperinhibitall=enable", 1, true) ~= nil
end

function M.get_steam_version_info()
    local root = steam_utils.detect_steam_install_path()
    if not root or root == "" or not fs.is_directory(root) then
        return { success = false, error = "Steam installation not found" }
    end
    local inf = read_steam_inf(root)
    local client_version = inf.ClientVersion or inf.Clientversion or ""
    local package_version = inf.PackageVersion or ""
    local cfg_path = fs.join(root, "steam.cfg")
    local cfg_content = ""
    if fs.is_file(cfg_path) then cfg_content = m_utils.read_file(cfg_path) or "" end

    local compat = nil
    for _, v in ipairs(KNOWN_COMPATIBLE_VERSIONS) do
        if v.version == client_version then compat = v; break end
    end

    return {
        success = true,
        steamPath = root,
        clientVersion = client_version,
        packageVersion = package_version,
        updatesBlocked = cfg_blocks_updates(cfg_content),
        isKnownCompatible = compat ~= nil,
        compatibilityLabel = compat and compat.label or "",
        knownCompatibleVersions = st.A(KNOWN_COMPATIBLE_VERSIONS),
        steamCfgExists = fs.is_file(cfg_path),
    }
end

function M.set_steam_update_block(enabled)
    if type(enabled) == "table" then enabled = enabled.enabled end
    enabled = enabled ~= false
    local root = steam_utils.detect_steam_install_path()
    if not root or root == "" or not fs.is_directory(root) then
        return { success = false, error = "Steam installation not found" }
    end
    if st.steam_is_running() then
        return { success = false, error = "Steam is running - close Steam fully, then retry.", steamRunning = true }
    end

    local cfg_path = fs.join(root, "steam.cfg")
    local backup_made = ""
    if fs.is_file(cfg_path) then
        local existing = m_utils.read_file(cfg_path)
        if existing then
            local bp = cfg_path .. ".luatools-bak-" .. math.floor(m_utils.time())
            m_utils.write_file(bp, existing)
            backup_made = bp
        end
    end

    local state
    if enabled then
        m_utils.write_file(cfg_path, BLOCK_CFG)
        logger.log("steam_version: Steam auto-updates BLOCKED via steam.cfg")
        state = true
    else
        if fs.is_file(cfg_path) then
            local cur = m_utils.read_file(cfg_path) or ""
            if cfg_blocks_updates(cur) then
                pcall(fs.remove, cfg_path)
                logger.log("steam_version: Steam auto-updates UNBLOCKED (steam.cfg removed)")
            end
        end
        state = false
    end

    return { success = true, updatesBlocked = state, steamCfgPath = cfg_path, backup = backup_made }
end

function M.list_steam_cfg_backups()
    local root = steam_utils.detect_steam_install_path()
    if not root or root == "" then return { success = false, error = "Steam installation not found" } end
    local backups = {}
    for _, e in ipairs(fs.list(root) or {}) do
        local n = e.name or ""
        if n:find("^steam%.cfg%.luatools%-bak%-") then
            table.insert(backups, {
                filename = n, path = e.path,
                size = fs.file_size(e.path) or 0,
                mtime = fs.last_write_time(e.path) or 0,
            })
        end
    end
    table.sort(backups, function(a, b) return (a.mtime or 0) > (b.mtime or 0) end)
    return { success = true, backups = st.A(backups) }
end

return M
