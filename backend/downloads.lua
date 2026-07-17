local m_utils = require("utils")
local fs = require("fs")
local http_client = require("http_client")
local config = require("config")
local logger = require("plugin_logger")
local paths = require("paths")
local steam_utils = require("steam_utils")
local utils = require("plugin_utils")
local api_manifest = require("api_manifest")
local settings_manager = require("settings.manager")
local unlock_paths = require("unlock_paths")
local cjson = require("json")

local downloads = {}
local DOWNLOAD_STATE = {}
local _history_mod = nil

-- The Ryuu session cookie (data/secrets.local.json) authenticates the generator.ryuu.lol hub —
-- and ONLY that host (the cookie is domain-scoped; never send it cross-domain). Returns the Cookie
-- value for a generator.ryuu.lol request, or nil for any other source.
local RYUU_HOST = "generator.ryuu.lol"
local function _ryuu_cookie(url, apiName)
    if not (url and string.find(tostring(url), RYUU_HOST, 1, true)) then return nil end
    local ok, sess = pcall(settings_manager.get_ryuu_session)
    if ok and type(sess) == "string" and sess ~= "" then return sess end
    return nil
end

local function _set_download_state(appid, update)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not DOWNLOAD_STATE[appid] then DOWNLOAD_STATE[appid] = {} end
    for k, v in pairs(update) do
        DOWNLOAD_STATE[appid][k] = v
    end
end

local function _get_download_state(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    local state = DOWNLOAD_STATE[appid] or {}
    local copy = {}
    for k, v in pairs(state) do copy[k] = v end
    return copy
end

local function _history()
    if _history_mod == false then return nil end
    if not _history_mod then
        local ok, mod = pcall(require, "history")
        _history_mod = ok and mod or false
    end
    return _history_mod or nil
end

local function _history_start(appid, source)
    local h = _history()
    if not h or not h.record_start then return nil end
    local ok, row_id = pcall(h.record_start, appid, source or "", "")
    if ok then return row_id end
    return nil
end

local function _history_complete(appid)
    local state = _get_download_state(appid)
    local row_id = state.historyId
    if not row_id then return end
    local h = _history()
    if h and h.record_complete then pcall(h.record_complete, row_id, "", state.totalBytes or 0, "") end
end

local function _history_fail(appid, err)
    local state = _get_download_state(appid)
    local row_id = state.historyId
    if not row_id then return end
    local h = _history()
    if h and h.record_failure then pcall(h.record_failure, row_id, err or "failed") end
end

function downloads.get_add_status(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    
    local dest_root = utils.ensure_temp_download_dir()
    local state_file = fs.join(dest_root, tostring(appid) .. "_state.json")
    
    if fs.exists(state_file) then
        local content = m_utils.read_file(state_file)
        if content and content ~= "" then
            local success, data = pcall(cjson.decode, content)
            if success and type(data) == "table" and data.status then
                _set_download_state(appid, { status = data.status, error = data.error })
                
                if data.status == "extracted" then
                    -- Background script finished! Complete the installation synchronously.
                    local dest_path = fs.join(dest_root, tostring(appid) .. ".zip")
                    local extract_dir = fs.join(dest_root, "extracted_" .. tostring(appid))
                    local apiName = _get_download_state(appid).currentApi or "Unknown"
                    
                    local ok, res = pcall(downloads._finalize_install_lua, appid, extract_dir, dest_path, apiName)
                    if not ok then
                        _set_download_state(appid, { status = "failed", error = tostring(res) })
                        _history_fail(appid, tostring(res))
                    end
                    
                    -- Cleanup background script files
                    pcall(fs.remove, state_file)
                    pcall(fs.remove, fs.join(dest_root, tostring(appid) .. "_dl.ps1"))
                    pcall(fs.remove, fs.join(dest_root, tostring(appid) .. "_dl.sh"))
                elseif data.status == "failed" then
                    _history_fail(appid, data.error or "download failed")
                    pcall(fs.remove, state_file)
                end
            end
        end
    end

    return { success = true, state = _get_download_state(appid) }
end

function downloads._finalize_install_lua(appid, extract_dir, dest_path, api_name)
    _set_download_state(appid, { status = "processing" })
    local ok_dir, target_dir = unlock_paths.ensure_lua_script_dir()
    if not ok_dir then
        _set_download_state(appid, { status = "failed", error = target_dir or "lua script dir unavailable" })
        _history_fail(appid, target_dir or "lua script dir unavailable")
        return { success = false, error = target_dir }
    end

    local base_path = steam_utils.detect_steam_install_path()
    local depot_cache = unlock_paths.depotcache_dir()
    if depot_cache == "" then depot_cache = fs.join(base_path, "depotcache") end
    if not fs.exists(depot_cache) then fs.create_directories(depot_cache) end
    
    local target_lua = fs.join(target_dir, tostring(appid) .. ".lua")
    local extracted_lua_path = nil
    
    local success_list, files = pcall(fs.list_recursive, extract_dir)
    if success_list and files then
        for _, entry in ipairs(files) do
            if not entry.is_directory then
                if entry.name:match("%.manifest$") then
                    local dest_man = fs.join(depot_cache, entry.name)
                    local content = m_utils.read_file(entry.path)
                    if content then m_utils.write_file(dest_man, content) end
                end
                if entry.name == tostring(appid) .. ".lua" then
                    extracted_lua_path = entry.path
                elseif not extracted_lua_path and entry.name:match("^%d+%.lua$") then
                    extracted_lua_path = entry.path
                end
            end
        end
    end
    
    if extracted_lua_path and fs.exists(extracted_lua_path) then
        local text = m_utils.read_file(extracted_lua_path)
        if text then
            local new_lines = {}
            for line in text:gmatch("([^\n]*)\n?") do
                if line:match("^%s*setManifestid%(") then
                    line = line:gsub("^(%s*)(setManifestid)", "%1-- %2")
                end
                table.insert(new_lines, line)
            end
            if new_lines[#new_lines] == "" then table.remove(new_lines) end
            text = table.concat(new_lines, "\n")
            m_utils.write_file(target_lua, text)
            _set_download_state(appid, { installedPath = target_lua })
        end
    end
    
    pcall(fs.remove_all, extract_dir)
    pcall(fs.remove, dest_path)
    _set_download_state(appid, { status = "done", success = true, api = api_name })
    _history_complete(appid)

    pcall(function()
        require("manifest_auto_updater").update_app(appid, "after_add")
    end)
end

local function _ps_quote(value)
    return "'" .. tostring(value or ""):gsub("'", "''") .. "'"
end

-- Write a PowerShell downloader script. The old cmd.exe /C string embedded
-- JSON status echoes inside double quotes, which truncated the command at the
-- first quote and left downloads stuck on "downloading".
local function _write_windows_download_script(script_path, state_file, url, dest_path, extract_dir, cookie)
    local lines = {
        "$ErrorActionPreference = 'Stop'",
        "$ProgressPreference = 'Continue'",
        "$stateFile = " .. _ps_quote(state_file),
        "$url = " .. _ps_quote(url),
        "$zip = " .. _ps_quote(dest_path),
        "$extract = " .. _ps_quote(extract_dir),
        "$cookie = " .. _ps_quote(cookie or ""),
        "$tarExe = Join-Path $env:WINDIR 'System32\\tar.exe'",
        "$curlExe = Join-Path $env:WINDIR 'System32\\curl.exe'",
        "if (-not (Test-Path -LiteralPath $tarExe)) { $tarExe = 'tar.exe' }",
        "if (-not (Test-Path -LiteralPath $curlExe)) { $curlExe = 'curl.exe' }",
        "function Write-State([string]$status, [string]$errorMessage = '') {",
        "  $obj = @{ status = $status }",
        "  if ($errorMessage -ne '') { $obj.error = $errorMessage }",
        "  $obj | ConvertTo-Json -Compress | Set-Content -LiteralPath $stateFile -Encoding ASCII",
        "}",
        "try {",
        "  Write-Host 'LuaTools is downloading the requested files...'",
        "  Write-Host 'Please keep this window open until it closes automatically.'",
        "  Write-State 'downloading'",
        "  if (-not (Test-Path -LiteralPath $extract)) { New-Item -ItemType Directory -Path $extract -Force | Out-Null }",
        "  $curlArgs = @('-L', '-A', 'discord(dot)gg/luatools', $url, '-o', $zip)",
        "  if ($cookie -ne '') { $curlArgs = @('-H', ('Cookie: ' + $cookie)) + $curlArgs }",
        "  & $curlExe @curlArgs",
        "  if ($LASTEXITCODE -ne 0) { throw \"curl.exe failed with exit code $LASTEXITCODE\" }",
        "  if (-not (Test-Path -LiteralPath $zip)) { throw 'Downloaded archive was not created' }",
        "  Write-State 'extracting'",
        "  Write-Host 'Extracting files...'",
        "  & $tarExe -xf $zip -C $extract",
        "  if ($LASTEXITCODE -ne 0) { throw \"tar.exe failed with exit code $LASTEXITCODE\" }",
        "  Write-State 'extracted'",
        "}",
        "catch {",
        "  Write-State 'failed' ($_.Exception.Message)",
        "  Write-Host ('ERROR: ' + $_.Exception.Message)",
        "  Start-Sleep -Seconds 5",
        "  exit 1",
        "}",
    }
    m_utils.write_file(script_path, table.concat(lines, "\n"))
end

local function _launch_async_download(appid, url, dest_path, extract_dir, cookie)
    local platform = require("platform")
    local dest_root = utils.ensure_temp_download_dir()
    local state_file = fs.join(dest_root, tostring(appid) .. "_state.json")

    m_utils.write_file(state_file, '{"status": "downloading"}')
    if not fs.exists(extract_dir) then fs.create_directories(extract_dir) end

    if platform.is_windows() then
        local script_file = fs.join(dest_root, tostring(appid) .. "_download.ps1")
        pcall(fs.remove, script_file)
        _write_windows_download_script(script_file, state_file, url, dest_path, extract_dir, cookie)
        local cmd = string.format(
            'cmd.exe /C start "LuaTools Downloader" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%s"',
            script_file
        )
        m_utils.exec(cmd)
    else
        local sh_path = fs.join(paths.get_plugin_dir(), "backend", "scripts", "downloader.sh")
        m_utils.exec('chmod +x "' .. sh_path .. '"')
        local cookie_arg = cookie and cookie ~= "" and cookie or ""
        local cmd = string.format(
            'nohup bash %s %s %s %s %s %s > /dev/null 2>&1 &',
            platform.shell_quote(sh_path),
            platform.shell_quote(url),
            platform.shell_quote(dest_path),
            platform.shell_quote(extract_dir),
            platform.shell_quote(state_file),
            platform.shell_quote(cookie_arg)
        )
        m_utils.exec(cmd)
    end
end

function downloads.start_add_via_luatools_from_url(appid, url, apiName)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { success = false, error = "Invalid appid" } end

    logger.log("LuaTools: StartAddViaLuaToolsFromUrl appid=" .. tostring(appid) .. " api=" .. tostring(apiName))
    local history_id = _history_start(appid, apiName)
    _set_download_state(appid, { status = "downloading", currentApi = apiName, bytesRead = 0, totalBytes = 0, historyId = history_id })

    local ok, res = pcall(function()
        if not url or url == "" then error("Invalid URL provided") end
        local dest_root = utils.ensure_temp_download_dir()
        local dest_path = fs.join(dest_root, tostring(appid) .. ".zip")
        local extract_dir = fs.join(dest_root, "extracted_" .. tostring(appid))
        _launch_async_download(appid, url, dest_path, extract_dir, _ryuu_cookie(url, apiName))
    end)

    if not ok then
        logger.warn("LuaTools: Async Download crashed - " .. tostring(res))
        _set_download_state(appid, { status = "failed", error = tostring(res) })
        _history_fail(appid, tostring(res))
        return { success = false, error = tostring(res) }
    end

    return { success = true }
end

function downloads.start_add_via_luatools(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { success = false, error = "Invalid appid" } end

    logger.log("LuaTools: StartAddViaLuaTools appid=" .. tostring(appid))
    _set_download_state(appid, { status = "queued", bytesRead = 0, totalBytes = 0 })

    local apis = api_manifest.load_api_manifest()
    if not apis or #apis == 0 then
        _set_download_state(appid, { status = "failed", error = "No APIs available" })
        _history_fail(appid, "No APIs available")
        return { success = true }
    end

    local dest_root = utils.ensure_temp_download_dir()
    local dest_path = fs.join(dest_root, tostring(appid) .. ".zip")
    local extract_dir = fs.join(dest_root, "extracted_" .. tostring(appid))
    local morrenus_api_key = settings_manager.get_morrenus_api_key()

    local ok, res = pcall(function()
        -- Note: For auto-add we only try the FIRST valid URL without verifying it via a synchronous HTTP request,
        -- because verifying it synchronously would defeat the purpose of async downloads.
        -- We assume CheckApisForApp already verified availability before user clicked this!
        local target_url = nil
        local target_name = nil
        for _, api in ipairs(apis) do
            local name = api.name or "Unknown"
            local template = api.url or ""
            local success_code = tonumber(api.success_code) or 200
            local usable = true

            if string.find(template, "<moapikey>") then
                if not morrenus_api_key or morrenus_api_key == "" then
                    usable = false
                else
                    template = template:gsub("<moapikey>", morrenus_api_key)
                end
            end
            if usable and string.find(template, "<apikey>") then
                if not api.api_key or api.api_key == "" then
                    usable = false
                else
                    template = template:gsub("<apikey>", api.api_key)
                end
            end

            if usable then
                local url = template:gsub("<appid>", tostring(appid))

                local success = false
                if _is_manifesthub_source(name) then
                    local status_url = "https://hubcapmanifest.com/api/v1/status/" .. tostring(appid) .. "?api_key=" .. tostring(morrenus_api_key)
                    local s_resp = http_client.get(status_url, { headers = { ["User-Agent"] = config.USER_AGENT }, timeout = 5 })
                    if s_resp and s_resp.status == success_code then
                        success = true
                    end
                else
                    local headers = { ["User-Agent"] = config.USER_AGENT }
                    local ck = _ryuu_cookie(url, name)
                    if ck then headers["Cookie"] = ck end
                    local resp = http_client.head(url, { headers = headers, timeout = 5 })
                    if resp and resp.status == success_code then
                        success = true
                    else
                        local get_resp = http_client.get(url, { headers = headers, timeout = 5 })
                        if get_resp and get_resp.status == success_code then
                            success = true
                        end
                    end
                end

                if success then
                    target_url = url
                    target_name = name
                    break
                end
            end
        end
        if not target_url then error("Not available on any API") end
        
        _set_download_state(appid, { status = "downloading", currentApi = target_name, historyId = _history_start(appid, target_name) })
        _launch_async_download(appid, target_url, dest_path, extract_dir, _ryuu_cookie(target_url, target_name))
    end)

    if not ok then
        logger.warn("LuaTools: start_add_via_luatools crashed - " .. tostring(res))
        _set_download_state(appid, { status = "failed", error = tostring(res) })
        _history_fail(appid, tostring(res))
        return { success = false, error = tostring(res) }
    end

    return { success = true }
end

local function _is_manifesthub_source(name)
    local n = string.lower(tostring(name or ""))
    return n == "morrenus" or n == "manifesthub"
end

local function _fast_download_enabled()
    local ok, values = pcall(function()
        return settings_manager._get_values_locked()
    end)
    if not ok or type(values) ~= "table" then return true end
    local general = values.general or {}
    if general.fastDownload == false then return false end
    return true
end

local function _manifesthub_stats_string(api_key)
    if not api_key or api_key == "" then return nil end
    local endpoint = "https://hubcapmanifest.com/api/v1/user/stats?api_key=" .. api_key
    local resp = http_client.get(endpoint, { headers = { ["User-Agent"] = config.USER_AGENT }, timeout = 5 })
    if not (resp and resp.status == 200 and resp.body and resp.body ~= "") then return nil end
    local ok, data = pcall(cjson.decode, resp.body)
    if not ok or type(data) ~= "table" then return nil end
    local used = data.daily_downloads or data.downloads_today or data.used or data.downloads_used
    local limit = data.daily_limit or data.limit or data.downloads_limit
    if used ~= nil and limit ~= nil then
        return tostring(used) .. "/" .. tostring(limit)
    end
    return nil
end

local function _build_picker_sources(appid, check_results, manifesthub_stats)
    local sources = {}
    for _, r in ipairs(check_results or {}) do
        local entry = {
            name = r.name,
            displayName = r.displayName or r.name,
            available = r.available == true,
            needsKey = r.needsKey == true,
            locked = r.locked == true,
            canDownload = r.canDownload == true,
            url = r.url,
            downloading = false,
            progress = 0,
            stats = nil,
        }
        if _is_manifesthub_source(entry.name) and manifesthub_stats then
            entry.stats = manifesthub_stats
        end
        table.insert(sources, entry)
    end
    return sources
end

function downloads.check_apis_for_app(appid, stop_on_first)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { success = false, error = "Invalid appid" } end
    if stop_on_first == nil then
        stop_on_first = _fast_download_enabled()
    end

    local apis = api_manifest.load_api_manifest()
    if not apis or #apis == 0 then
        return { success = true, results = {} }
    end

    local results = {}
    local morrenus_api_key = settings_manager.get_morrenus_api_key()

    for _, api in ipairs(apis) do
        local name = api.name or "Unknown"
        local template = api.url or ""
        local success_code = tonumber(api.success_code) or 200
        local needs_mo_key = string.find(template, "<moapikey>") ~= nil
        local needs_api_key = string.find(template, "<apikey>") ~= nil
        local usable = true

        if needs_mo_key then
            if not morrenus_api_key or morrenus_api_key == "" then
                usable = false
            else
                template = template:gsub("<moapikey>", morrenus_api_key)
            end
        end
        if usable and needs_api_key then
            if not api.api_key or api.api_key == "" then
                usable = false
            else
                template = template:gsub("<apikey>", api.api_key)
            end
        end

        if not usable then
            if needs_mo_key or needs_api_key then
                table.insert(results, {
                    name = name,
                    displayName = name,
                    available = false,
                    needsKey = true,
                    locked = true,
                    canDownload = false,
                    url = nil,
                })
            end
        else
            local url = template:gsub("<appid>", tostring(appid))
            local available = false

            if _is_manifesthub_source(name) then
                local status_url = "https://hubcapmanifest.com/api/v1/status/" .. tostring(appid) .. "?api_key=" .. tostring(morrenus_api_key)
                local resp = http_client.get(status_url, { headers = { ["User-Agent"] = config.USER_AGENT }, timeout = 5 })
                if resp and resp.status == success_code then
                    available = true
                end
            else
                local success = false
                local headers = { ["User-Agent"] = config.USER_AGENT }
                local ck = _ryuu_cookie(url, name)
                if ck then headers["Cookie"] = ck end
                local resp = http_client.head(url, { headers = headers, timeout = 5 })
                if resp and resp.status == success_code then
                    success = true
                else
                    local get_resp = http_client.get(url, { headers = headers, timeout = 5 })
                    if get_resp and get_resp.status == success_code then
                        success = true
                    end
                end

                if success then
                    available = true
                end
            end

            table.insert(results, {
                name = name,
                displayName = name,
                available = available,
                needsKey = false,
                locked = false,
                canDownload = available,
                url = available and url or nil,
            })

            -- Priority order already applied; stop once the first source has the game.
            if available and stop_on_first then
                break
            end
        end
    end

    return { success = true, results = results }
end

function downloads.begin_add_with_picker(appid, game_name)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { success = false, error = "Invalid appid" } end

    local existing = DOWNLOAD_STATE[appid]
    if existing and (existing.status == "downloading" or existing.status == "processing" or existing.status == "installing") then
        return { success = false, error = "already_in_progress" }
    end

    logger.log("LuaTools: StartLuaToolsAdd appid=" .. tostring(appid) .. " name=" .. tostring(game_name or ""))
    _set_download_state(appid, {
        status = "checking",
        mode = "picker",
        gameName = tostring(game_name or ""),
        sources = nil,
        sourcesLoaded = false,
        checking = true,
        pickedSource = nil,
        error = nil,
        bytesRead = 0,
        totalBytes = 0,
    })
    return { success = true }
end

function downloads._maybe_run_source_check(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    local state = DOWNLOAD_STATE[appid]
    if not state or state.mode ~= "picker" or state.sourcesLoaded then return end

    local check = downloads.check_apis_for_app(appid)
    if not check or check.success ~= true then
        _set_download_state(appid, {
            checking = false,
            sourcesLoaded = true,
            sources = {},
            status = "failed",
            error = (check and check.error) or "Source check failed",
        })
        return
    end

    local manifesthub_key = settings_manager.get_morrenus_api_key()
    local manifesthub_stats = _manifesthub_stats_string(manifesthub_key)
    local sources = _build_picker_sources(appid, check.results, manifesthub_stats)
    local has_downloadable = false
    for _, s in ipairs(sources) do
        if s.canDownload then has_downloadable = true break end
    end

    _set_download_state(appid, {
        sources = sources,
        sourcesLoaded = true,
        checking = false,
        status = has_downloadable and "picking" or "failed",
        error = has_downloadable and nil or "Not available on any API",
    })
end

function downloads.pick_add_source(appid, source_name)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { success = false, error = "Invalid appid" } end
    source_name = tostring(source_name or "")

    downloads._maybe_run_source_check(appid)
    local state = _get_download_state(appid)
    if not state.sources then
        return { success = false, error = "Sources not ready" }
    end

    for _, s in ipairs(state.sources) do
        if s.name == source_name and s.canDownload and s.url then
            _set_download_state(appid, { pickedSource = source_name, status = "downloading", currentApi = source_name })
            return downloads.start_add_via_luatools_from_url(appid, s.url, source_name)
        end
    end
    return { success = false, error = "Source not available: " .. source_name }
end

function downloads.get_lua_tools_add_status(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    if not appid then return { error = "Invalid appid" } end

    downloads.get_add_status(appid)
    downloads._maybe_run_source_check(appid)

    local state = _get_download_state(appid)
    if not state or state.mode ~= "picker" then
        local legacy = _get_download_state(appid)
        return {
            checking = legacy.status == "checking",
            sourcesLoaded = legacy.status ~= "checking",
            sources = {},
            error = legacy.status == "failed" and (legacy.error or "Failed") or nil,
            installed = legacy.status == "done",
            installStatus = legacy.status == "done" and "The game has been added successfully." or nil,
            fastFetch = false,
        }
    end

    local sources = {}
    for _, s in ipairs(state.sources or {}) do
        local copy = {}
        for k, v in pairs(s) do copy[k] = v end
        if state.currentApi and copy.name == state.currentApi and (state.status == "downloading" or state.status == "processing" or state.status == "installing") then
            copy.downloading = true
            local total = tonumber(state.totalBytes) or 0
            local read = tonumber(state.bytesRead) or 0
            if total > 0 then
                copy.progress = math.max(0, math.min(100, math.floor((read / total) * 100)))
            else
                copy.indeterminate = true
            end
        end
        table.insert(sources, copy)
    end

    local response = {
        checking = state.checking == true,
        sourcesLoaded = state.sourcesLoaded == true,
        sources = sources,
        error = state.error,
        installed = state.status == "done",
        installStatus = state.status == "done" and "The game has been added successfully." or nil,
        fastFetch = false,
        gameName = state.gameName,
    }

    if state.status == "failed" and not response.error then
        response.error = "Failed"
    end

    return response
end

return downloads
