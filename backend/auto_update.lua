local m_utils = require("utils")
local fs = require("fs")
local http_client = require("http_client")
local config = require("config")
local logger = require("plugin_logger")
local paths = require("paths")
local utils = require("plugin_utils")
local cjson = require("json")

local auto_update = {}

local function _github_release_info(cfg)
    local gh_cfg = cfg.github or {}
    local owner = gh_cfg.owner or ""
    local repo = gh_cfg.repo or ""
    if owner == "" or repo == "" then
        return nil, "GitHub owner/repo not configured"
    end

    local asset_name = gh_cfg.asset_name or "STLT-Rewired.zip"
    local tag_prefix = gh_cfg.tag_prefix or "v"
    local tag = gh_cfg.tag or ""
    local endpoint = "https://api.github.com/repos/" .. owner .. "/" .. repo .. "/releases/latest"
    if tag ~= "" then
        endpoint = "https://api.github.com/repos/" .. owner .. "/" .. repo .. "/releases/tags/" .. tag
    end

    local resp = http_client.get(endpoint, {
        headers = {
            ["Accept"] = "application/vnd.github+json",
            ["User-Agent"] = "Rewired-Updater"
        },
        timeout = 15
    })
    if not resp or resp.status ~= 200 or not resp.body then
        return nil, "GitHub release API HTTP " .. tostring(resp and resp.status or 0)
    end

    local ok, data = pcall(cjson.decode, resp.body)
    if not ok or type(data) ~= "table" then
        return nil, "Invalid GitHub release JSON"
    end

    local latest_version = data.tag_name or data.name or ""
    if tag_prefix ~= "" and latest_version:sub(1, #tag_prefix) == tag_prefix then
        latest_version = latest_version:sub(#tag_prefix + 1)
    end

    local zip_url = ""
    for _, asset in ipairs(data.assets or {}) do
        if asset.name == asset_name then
            zip_url = asset.browser_download_url or ""
            break
        end
    end
    if latest_version == "" or zip_url == "" then
        return nil, "Release missing version or asset " .. asset_name
    end

    return {
        latest_version = latest_version,
        zip_url = zip_url,
        html_url = data.html_url or "",
        tag_name = data.tag_name or "",
    }, nil
end

local function _preserve_and_restore_data(plugin_dir, work_dir)
    local live_data = fs.join(plugin_dir, "backend", "data")
    local preserved = fs.join(work_dir, "preserved-data")
    if fs.exists(live_data) and fs.is_directory(live_data) then
        pcall(function()
            if fs.exists(preserved) then fs.remove_all(preserved) end
            -- shallow copy via list_recursive would be heavy; exec when available
            local is_windows = m_utils.getenv("OS") == "Windows_NT"
            if is_windows then
                m_utils.exec(string.format('xcopy "%s" "%s" /E /I /Y /Q', live_data, preserved))
            else
                m_utils.exec(string.format('cp -a "%s/." "%s/"', live_data, preserved))
            end
        end)
    end
    return preserved
end

local function _restore_data(plugin_dir, preserved)
    if not preserved or preserved == "" or not fs.exists(preserved) then return end
    local new_data = fs.join(plugin_dir, "backend", "data")
    if not fs.exists(new_data) then fs.create_directories(new_data) end
    local is_windows = m_utils.getenv("OS") == "Windows_NT"
    if is_windows then
        m_utils.exec(string.format('xcopy "%s" "%s" /E /I /Y /Q', preserved, new_data))
    else
        m_utils.exec(string.format('cp -a "%s/." "%s/"', preserved, new_data))
    end
end

function auto_update.get_update_status()
    local cfg_path = paths.backend_path(config.UPDATE_CONFIG_FILE)
    local cfg = utils.read_json(cfg_path) or {}
    local current_version = utils.get_plugin_version()
    local info, err = _github_release_info(cfg)
    if not info then
        return { success = false, error = err, current_version = current_version }
    end
    local update_available = utils.is_newer_version(info.latest_version, current_version)
    return {
        success = true,
        current_version = current_version,
        latest_version = info.latest_version,
        update_available = update_available,
        release_url = info.html_url,
        install_windows = (cfg.install or {}).windows_install or "",
        install_linux = (cfg.install or {}).linux_install or "",
    }
end

function auto_update.check_for_updates_now()
    local cfg_path = paths.backend_path(config.UPDATE_CONFIG_FILE)
    local cfg = utils.read_json(cfg_path) or {}
    local current_version = utils.get_plugin_version()
    local info, err = _github_release_info(cfg)
    if not info then
        return { success = false, error = err }
    end

    if not utils.is_newer_version(info.latest_version, current_version) then
        return { success = true, message = "Up-to-date (current " .. current_version .. ")", latest_version = info.latest_version }
    end

    local plugin_dir = paths.get_plugin_dir()
    local work_dir = fs.join(paths.backend_path("temp_dl"), "update-" .. tostring(os.time()))
    if not fs.exists(work_dir) then fs.create_directories(work_dir) end

    local zip_path = fs.join(work_dir, "release.zip")
    local extract_dir = fs.join(work_dir, "extract")
    if not fs.exists(extract_dir) then fs.create_directories(extract_dir) end

    local preserved = _preserve_and_restore_data(plugin_dir, work_dir)

    local is_windows = m_utils.getenv("OS") == "Windows_NT"
    local dl_ok, dl_err = pcall(function()
        if is_windows then
            m_utils.exec(string.format('curl.exe -sL -A "Rewired-Updater" "%s" -o "%s"', info.zip_url, zip_path))
            m_utils.exec(string.format('tar.exe -xf "%s" -C "%s"', zip_path, extract_dir))
        else
            m_utils.exec(string.format('curl -fsSL -A "Rewired-Updater" "%s" -o "%s"', info.zip_url, zip_path))
            m_utils.exec(string.format('unzip -o -q "%s" -d "%s"', zip_path, extract_dir))
        end
    end)
    if not dl_ok then
        pcall(fs.remove_all, work_dir)
        return { success = false, error = "Download/extract failed: " .. tostring(dl_err) }
    end

    -- Replace plugin runtime files (keep plugin_dir path)
    local include = { "backend", "public", ".millennium", "plugin.json" }
    for _, name in ipairs(include) do
        local src = fs.join(extract_dir, name)
        local dst = fs.join(plugin_dir, name)
        if fs.exists(src) then
            if fs.exists(dst) then
                pcall(fs.remove_all, dst)
            end
            local cp_cmd
            if is_windows then
                if name == "plugin.json" then
                    m_utils.exec(string.format('copy /Y "%s" "%s"', src, dst))
                else
                    m_utils.exec(string.format('xcopy "%s" "%s" /E /I /Y /Q', src, dst))
                end
            else
                m_utils.exec(string.format('cp -a "%s" "%s"', src, dst))
            end
        end
    end

    _restore_data(plugin_dir, preserved)
    pcall(fs.remove_all, work_dir)

    local msg = "Rewired updated to " .. info.latest_version .. ". Please restart Steam."
    logger.log("auto_update: " .. msg)
    return { success = true, message = msg, latest_version = info.latest_version }
end

function auto_update.maybe_check_on_boot()
    local cfg_path = paths.backend_path(config.UPDATE_CONFIG_FILE)
    local cfg = utils.read_json(cfg_path) or {}
    local gh = cfg.github or {}
    if (gh.owner or "") == "" or (gh.repo or "") == "" then return end

    local stamp_file = paths.backend_path("data/last_update_check.json")
    local interval = tonumber(config.UPDATE_CHECK_INTERVAL_SECONDS) or 7200
    local now = os.time()
    local last = 0
    if fs.exists(stamp_file) then
        local ok, data = pcall(utils.read_json, stamp_file)
        if ok and type(data) == "table" then last = tonumber(data.last_check) or 0 end
    end
    if now - last < interval then return end

    pcall(function()
        local dir = fs.join(paths.get_plugin_dir(), "backend", "data")
        if not fs.exists(dir) then fs.create_directories(dir) end
        utils.write_json(stamp_file, { last_check = now })
    end)

    local ok, res = pcall(auto_update.check_for_updates_now)
    if ok and type(res) == "table" and res.success and res.message and res.message:find("updated", 1, true) then
        require("api_manifest").store_last_message(res.message)
    end
end

function auto_update.restart_steam()
    local platform = require("platform")
    if platform.is_windows() then
        local script_path = paths.backend_path("restart_steam.cmd")
        if fs.exists(script_path) then
            m_utils.exec('start /b cmd /C "' .. script_path .. '"')
            return true
        end
        return false
    end
    platform.kill_steam()
    pcall(function()
        if type(m_utils.sleep) == "function" then m_utils.sleep(1000) end
    end)
    return platform.launch_steam()
end

function auto_update.apply_pending_update_if_any()
    return ""
end

return auto_update
