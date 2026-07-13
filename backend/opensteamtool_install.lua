-- opensteamtool_install.lua — download and install OpenSteamTool into the Steam folder.
-- Mirrors the private Rewired Manager installer flow.

local cjson = require("json")
local fs = require("fs")
local http_client = require("http_client")
local m_utils = require("utils")
local steam_utils = require("steam_utils")
local unlock_paths = require("unlock_paths")
local logger = require("plugin_logger")

local M = {}

local RELEASES_API = "https://api.github.com/repos/OpenSteam001/OpenSteamTool/releases/latest"
local WANTED = { "dwmapi.dll", "xinput1_4.dll", "OpenSteamTool.dll" }

local function _find_file_recursive(root, file_name)
    local ok, entries = pcall(fs.list_recursive, root)
    if not ok or not entries then return nil end
    for _, e in ipairs(entries) do
        if not e.is_directory and e.name == file_name then return e.path end
    end
    return nil
end

local function _pick_release_zip(body)
    local ok, data = pcall(cjson.decode, body or "")
    if not ok or type(data) ~= "table" then return nil end
    for _, asset in ipairs(data.assets or {}) do
        local name = tostring(asset.name or "")
        local lower = name:lower()
        if lower:find("release", 1, true) and lower:match("%.zip$") and not lower:find("debug", 1, true) then
            return tostring(asset.browser_download_url or "")
        end
    end
    return nil
end

function M.install_latest(steam_path)
    steam_path = tostring(steam_path or steam_utils.detect_steam_install_path() or ""):gsub("/", "\\")
    if steam_path == "" or not fs.is_directory(steam_path) then
        return { success = false, error = "Steam path does not exist." }
    end

    local resp = http_client.get(RELEASES_API, {
        headers = {
            ["User-Agent"] = "STLT-Rewired/1.0 (+https://github.com/Sigmachan/STLT-Rewired)",
            ["Accept"] = "application/vnd.github+json",
        },
        timeout = 30,
    })
    if not resp or resp.status ~= 200 or not resp.body then
        return { success = false, error = "Could not reach GitHub releases API." }
    end

    local zip_url = _pick_release_zip(resp.body)
    if not zip_url or zip_url == "" then
        return { success = false, error = "No OpenSteamTool Release zip found on GitHub." }
    end

    local temp_root = m_utils.getenv("TEMP") or m_utils.getenv("TMP") or ""
    if temp_root == "" then temp_root = steam_path end
    local stamp = tostring(math.floor(m_utils.time() * 1000))
    local zip_path = fs.join(temp_root, "rewired-ost-" .. stamp .. ".zip")
    local extract_dir = fs.join(temp_root, "rewired-ost-" .. stamp)

    local dl_cmd = string.format(
        'curl.exe -fsSL -A "STLT-Rewired/1.0" "%s" -o "%s"',
        zip_url:gsub('"', '\\"'), zip_path:gsub('"', '\\"')
    )
    local dl_ok = pcall(m_utils.exec, dl_cmd)
    if not dl_ok or not fs.exists(zip_path) then
        pcall(fs.remove, zip_path)
        return { success = false, error = "Failed to download OpenSteamTool release." }
    end

    pcall(fs.create_directories, extract_dir)
    local ex_cmd = string.format(
        'powershell.exe -NoProfile -Command "Expand-Archive -LiteralPath ''%s'' -DestinationPath ''%s'' -Force"',
        zip_path:gsub("'", "''"), extract_dir:gsub("'", "''")
    )
    pcall(m_utils.exec, ex_cmd)

    local installed = {}
    for _, file_name in ipairs(WANTED) do
        local source = _find_file_recursive(extract_dir, file_name)
        if not source then
            pcall(fs.remove, zip_path)
            pcall(fs.remove_all, extract_dir)
            return { success = false, error = "Missing " .. file_name .. " in release archive.", installed = installed }
        end
        local dest = fs.join(steam_path, file_name)
        local copied = fs.copy(source, dest)
        if not copied then
            pcall(fs.remove, zip_path)
            pcall(fs.remove_all, extract_dir)
            return { success = false, error = "Could not copy " .. file_name .. " into Steam folder.", installed = installed }
        end
        table.insert(installed, dest)
    end

    pcall(unlock_paths.ensure_lua_script_dir)
    unlock_paths.invalidate_cache()
    unlock_paths.write_shared_config({
        unlockBackend = "opensteamtool",
        steamPath = steam_path,
    })

    pcall(fs.remove, zip_path)
    pcall(fs.remove_all, extract_dir)

    logger.log("opensteamtool_install: installed " .. table.concat(installed, ", "))
    return {
        success = true,
        message = "OpenSteamTool installed. Restart Steam so the unlock backend loads.",
        installed = installed,
    }
end

return M
