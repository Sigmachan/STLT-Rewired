-- zip_util.lua — portable zip create/extract (PowerShell on Windows, zip/unzip on Linux).

local m_utils = require("utils")
local fs = require("fs")
local platform = require("platform")

local M = {}

local function sh_quote(value)
    if platform.is_windows() then
        return "'" .. tostring(value or ""):gsub("'", "''") .. "'"
    end
    return platform.shell_quote(value)
end

--- Extract archive into destination directory.
function M.extract(archive_path, dest_dir)
    archive_path = tostring(archive_path or "")
    dest_dir = tostring(dest_dir or "")
    if archive_path == "" or dest_dir == "" then return false, "missing path" end
    pcall(fs.create_directories, dest_dir)
    if platform.is_windows() then
        local cmd = string.format(
            "powershell -NoProfile -NonInteractive -Command \"Expand-Archive -LiteralPath %s -DestinationPath %s -Force\"",
            sh_quote(archive_path), sh_quote(dest_dir)
        )
        local ok = pcall(m_utils.exec, cmd)
        return ok == true
    end
    local cmd = string.format("unzip -o -q %s -d %s", sh_quote(archive_path), sh_quote(dest_dir))
    local ok = pcall(m_utils.exec, cmd)
    return ok == true
end

--- Compress one or more source paths into a zip archive.
--- Each source is stored under its basename (stplug-in/, depotcache/, lua/).
function M.compress(sources, zip_path)
    zip_path = tostring(zip_path or "")
    if type(sources) ~= "table" or #sources == 0 or zip_path == "" then
        return false, "missing sources"
    end
    pcall(fs.remove, zip_path)
    if platform.is_windows() then
        local quoted = {}
        for _, p in ipairs(sources) do table.insert(quoted, sh_quote(p)) end
        local cmd = "powershell -NoProfile -NonInteractive -Command \"Compress-Archive -Path "
            .. table.concat(quoted, ",") .. " -DestinationPath " .. sh_quote(zip_path) .. " -Force\""
        local ok = pcall(m_utils.exec, cmd)
        return ok == true and fs.is_file(zip_path)
    end
    for _, p in ipairs(sources) do
        local parent = fs.parent_path(p)
        local name = p:match("([^/\\]+)$") or p
        local add = string.format(
            "cd %s && zip -qr %s %s",
            sh_quote(parent), sh_quote(zip_path), sh_quote(name)
        )
        local ok = pcall(m_utils.exec, add)
        if not ok then return false, "zip failed for " .. tostring(name) end
    end
    return fs.is_file(zip_path) == true
end

return M
