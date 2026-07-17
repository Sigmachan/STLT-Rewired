-- platform.lua — OS detection and portable shell helpers for Windows + Linux.

local m_utils = require("utils")
local fs = require("fs")

local M = {}

function M.is_windows()
    return m_utils.getenv("OS") == "Windows_NT"
end

function M.is_linux()
    return not M.is_windows()
end

function M.name()
    return M.is_windows() and "windows" or "linux"
end

--- Shared Rewired config directory (Manager + plugin).
--- Windows: %LOCALAPPDATA%\Rewired
--- Linux: $XDG_DATA_HOME/Rewired or ~/.local/share/Rewired
function M.config_dir()
    if M.is_windows() then
        local la = m_utils.getenv("LOCALAPPDATA")
        if la and la ~= "" then return fs.join(la, "Rewired") end
        return ""
    end
    local xdg = m_utils.getenv("XDG_DATA_HOME")
    if xdg and xdg ~= "" then return fs.join(xdg, "Rewired") end
    local home = m_utils.getenv("HOME")
    if home and home ~= "" then return fs.join(home, ".local", "share", "Rewired") end
    return ""
end

function M.shell_quote(value)
    return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
end

function M.open_url(url)
    url = tostring(url or "")
    if url == "" then return false end
    if M.is_windows() then
        return pcall(m_utils.exec, 'start "" "' .. url:gsub('"', "") .. '"') == true
    end
    local q = M.shell_quote(url)
    -- Prefer steam protocol handler when available for steam:// links.
    if url:find("^steam://", 1) then
        local ok = pcall(m_utils.exec, "steam " .. q .. " >/dev/null 2>&1 &")
        if ok then return true end
    end
    return pcall(m_utils.exec, "xdg-open " .. q .. " >/dev/null 2>&1 &") == true
end

function M.open_path(path)
    path = tostring(path or "")
    if path == "" or not fs.exists(path) then return false end
    if M.is_windows() then
        local win = path:gsub("/", "\\")
        return pcall(m_utils.exec, 'explorer "' .. win .. '"') == true
    end
    return pcall(m_utils.exec, "xdg-open " .. M.shell_quote(path) .. " >/dev/null 2>&1 &") == true
end

function M.kill_steam()
    if M.is_windows() then
        pcall(m_utils.exec, "taskkill /F /IM steam.exe >nul 2>&1")
        return true
    end
    pcall(m_utils.exec, "killall -q steam steam.sh 2>/dev/null || true")
    return true
end

function M.launch_steam()
    if M.is_windows() then
        return pcall(m_utils.exec, 'start "" steam://0') == true
    end
    return pcall(m_utils.exec, "steam >/dev/null 2>&1 &") == true
end

function M.trigger_steam_install(appid)
    appid = tonumber(appid)
    if not appid then return false end
    return M.open_url("steam://install/" .. tostring(appid))
end

return M
