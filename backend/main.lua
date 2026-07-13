-- LuaTools backend main.lua
-- All exported functions return JSON-encoded strings, mirroring the Python backend's json.dumps() returns.
-- This is required because Millennium's Lua bridge does not deep-serialize nested Lua tables.

local cjson            = require("json")
local m_utils          = require("utils")
local logger           = require("plugin_logger")
local millennium       = require("millennium")
local fs               = require("fs")
local http_client      = require("http_client")
local paths            = require("paths")
local steam_utils      = require("steam_utils")
local utils            = require("plugin_utils")
local locales_mod      = require("locales.manager")

local api_manifest     = require("api_manifest")
local downloads        = require("downloads")
local fixes            = require("fixes")
local settings_manager = require("settings.manager")
local auto_update      = require("auto_update")
local cache_tools     = require("cache_tools")
local lua_tools       = require("lua_tools")
local custom_apis     = require("custom_apis")
local source_chain    = require("source_chain")
local history         = require("history")
local config_transfer = require("config_transfer")
local dlc             = require("dlc")
local events          = require("events")
local mods            = require("mods")
local profiles        = require("profiles")
local steam_version   = require("steam_version")
local acf_lock        = require("acf_lock")
local crack_migrator  = require("crack_migrator")
local manifests       = require("manifests")
local manifest_auto   = require("manifest_auto_updater")
local manifesthub     = require("manifesthub")
local cloud_fix       = require("cloud_fix")
local health          = require("health")
local diagnostics     = require("diagnostics")
local workshop        = require("workshop")
local batch           = require("batch")
local achievements    = require("achievements")
local backup          = require("backup")
local key_vault       = require("key_vault")
local ryuu            = require("ryuu")
local tokeer          = require("tokeer")
local sync            = require("sync")
local account         = require("account")
local sentinel        = require("sentinel")
local setup_assistant = require("setup_assistant")
local unlock_paths    = require("unlock_paths")
local st              = require("st_util")
local stlt_migration  = require("stlt_migration")

-- ── Helpers ──────────────────────────────────────────────────────────────────

--- Safely encode a Lua table to a JSON string (same as Python json.dumps).
local function json_ok(data)
    local ok, s = pcall(cjson.encode, data)
    if ok then return s end
    logger.warn("json_ok encode failed: " .. tostring(s))
    return '{"success":false,"error":"serialization error"}'
end

local function json_err(msg)
    return json_ok({ success = false, error = tostring(msg) })
end

-- ── Lifecycle ────────────────────────────────────────────────────────────────

local function on_load()
    logger.log("Bootstrapping LuaTools plugin, millennium " .. millennium.version())
    steam_utils.detect_steam_install_path()
    utils.ensure_temp_download_dir()

    local ok_s, err_s = pcall(settings_manager.init_settings)
    if not ok_s then logger.warn("settings init failed: " .. tostring(err_s)) end

    pcall(stlt_migration.run_once)

    pcall(setup_assistant.self_heal)

    pcall(function() auto_update.maybe_check_on_boot() end)

    local ok_u, upd_msg = pcall(auto_update.apply_pending_update_if_any)
    if ok_u and upd_msg and upd_msg ~= "" then
        api_manifest.store_last_message(upd_msg)
    end

    logger.log("LuaTools browser bootstrap is provided by .millennium/Dist/webkit.js")

    local res = api_manifest.init_apis()
    logger.log("InitApis (boot) result: " .. tostring(res.message or ""))

    millennium.ready()

    local keys = {}
    for k, v in pairs(millennium) do table.insert(keys, k .. ":" .. type(v)) end
    logger.log("MILLENNIUM KEYS: " .. table.concat(keys, ", "))
end

local function on_unload()
    logger.log("unloading LuaTools plugin")
end

local function on_frontend_loaded()
    logger.log("Frontend loaded")
end

-- ── Logger (called as "Logger.log" from JS) ──────────────────────────────────

Logger = {}

function Logger.log(message)
    local msg = type(message) == "table" and tostring(message.message or "") or tostring(message or "")
    logger.log("[Frontend] " .. msg)
    return json_ok({ success = true })
end

function Logger.warn(message)
    local msg = type(message) == "table" and tostring(message.message or "") or tostring(message or "")
    logger.warn("[Frontend] " .. msg)
    return json_ok({ success = true })
end

function Logger.error(message)
    local msg = type(message) == "table" and tostring(message.message or "") or tostring(message or "")
    logger.error("[Frontend] " .. msg)
    return json_ok({ success = true })
end

-- Millennium looks up "Logger.log" as a dotted global key
_G["Logger.log"]   = Logger.log
_G["Logger.warn"]  = Logger.warn
_G["Logger.error"] = Logger.error

-- ── Exported API Methods ─────────────────────────────────────────────────────
-- Every function returns a JSON string, matching the Python backend exactly.

function GetPluginDir()
    return paths.get_plugin_dir() -- plain string, matches Python
end

function InitApis()
    local ok, res = pcall(api_manifest.init_apis)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetInitApisMessage()
    local ok, res = pcall(api_manifest.get_init_apis_message)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function FetchFreeApisNow()
    local ok, res = pcall(api_manifest.fetch_free_apis_now)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function CheckForUpdatesNow()
    local ok, res = pcall(auto_update.check_for_updates_now)
    if not ok then
        logger.warn("CheckForUpdatesNow failed: " .. tostring(res))
        return json_err(res)
    end
    return json_ok(res)
end

function GetUpdateStatus()
    local ok, res = pcall(auto_update.get_update_status)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function RestartSteam()
    local ok, success = pcall(auto_update.restart_steam)
    if ok and success then
        return json_ok({ success = true })
    end
    return json_ok({ success = false, error = "Failed to restart Steam" })
end

function HasLuaToolsForApp(appid)
    if type(appid) == "table" then appid = appid.appid end
    local ok, exists = pcall(steam_utils.has_lua_for_app, tonumber(appid))
    if not ok then return json_err(exists) end
    return json_ok({ success = true, exists = exists == true })
end

function GetUnlockBackendStatus()
    local ok, res = pcall(unlock_paths.get_unlock_status)
    if not ok then return json_err(res) end
    return json_ok({ success = true, status = res })
end

function StartAddViaLuaTools(appid)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(downloads.start_add_via_luatools, tonumber(appid))
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- Upstream-compatible add flow: check sources, let the user pick, then download.
function StartLuaToolsAdd(appid, contentScriptQuery, name)
    if type(appid) == "table" then
        name = appid.name
        appid = appid.appid
    end
    local ok, res = pcall(downloads.begin_add_with_picker, tonumber(appid), tostring(name or ""))
    if not ok then return json_err(res) end
    return json_ok(res)
end

function PickLuaToolsAddSource(appid, contentScriptQuery, source)
    if type(appid) == "table" then
        source = appid.source
        appid = appid.appid
    end
    local ok, res = pcall(downloads.pick_add_source, tonumber(appid), tostring(source or ""))
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetLuaToolsAddStatus(appid)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(downloads.get_lua_tools_add_status, tonumber(appid))
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetAddViaLuaToolsStatus(appid)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(downloads.get_add_status, tonumber(appid))
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetApiList()
    local ok, res = pcall(api_manifest.get_api_list)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function AddCustomApi(api_key, contentScriptQuery, name, url)
    -- JS passes: { api_key, contentScriptQuery, name, url }
    -- Reconstruct the payload object for api_manifest
    local payload = {
        name = tostring(name or ""),
        url = tostring(url or ""),
        api_key = tostring(api_key or "")
    }
    local ok, res = pcall(api_manifest.add_custom_api, payload)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetAllApis()
    local ok, res = pcall(api_manifest.get_all_apis)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ToggleApi(params, contentScriptQuery)
    local apiName = params
    if type(params) == "table" then apiName = params.apiName or params.name end
    local ok, res = pcall(api_manifest.toggle_api, tostring(apiName or ""))
    if not ok then return json_err(res) end
    return json_ok(res)
end

function RemoveApi(params, contentScriptQuery)
    local apiName = params
    if type(params) == "table" then apiName = params.apiName or params.name end
    local ok, res = pcall(api_manifest.remove_api, tostring(apiName or ""))
    if not ok then return json_err(res) end
    return json_ok(res)
end

function RenameApi(params, contentScriptQuery)
    local old_name, new_name
    if type(params) == "table" then
        new_name = params.new_name
        old_name = params.old_name or params.apiName or params.name
    else
        -- If somehow positional
        old_name = params
    end
    local ok, res = pcall(api_manifest.rename_api, tostring(old_name or ""), tostring(new_name or ""))
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ReorderApis(params, contentScriptQuery)
    local names = params
    if type(params) == "table" and params.apiNames then
        names = params.apiNames
    end
    -- Millennium's Lua bridge doesn't deep-deserialize nested JSON arrays/objects
    if type(names) == "string" then
        local ok, parsed = pcall(cjson.decode, names)
        if ok and type(parsed) == "table" then
            names = parsed
        end
    end
    if type(names) ~= "table" then
        return json_ok({ success = false, error = "Invalid argument, got type: " .. type(names) })
    end
    local ok, res = pcall(api_manifest.set_api_order, names)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function CancelAddViaLuaTools(appid)
    -- No-op cancel stub; download is synchronous in Lua
    return json_ok({ success = true })
end

function CheckApisForApp(appid)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(downloads.check_apis_for_app, tonumber(appid))
    if not ok then return json_err(res) end

    -- Ensure empty arrays encode as [] and not {}
    if res and type(res.results) == "table" and #res.results == 0 then
        -- Serialize manually or inject cjson.empty_array
        local success_json = res.success and "true" or "false"
        return '{"success":' .. success_json .. ',"results":[]}'
    end

    return json_ok(res)
end

function GetMorrenusStats(api_key, force_refresh)
    return GetManifestHubStats(api_key, force_refresh)
end

function GetManifestHubStats(api_key, force_refresh)
    if type(api_key) == "table" then
        force_refresh = api_key.force_refresh
        api_key = api_key.api_key
    end
    api_key = tostring(api_key or "")
    if api_key == "" then return json_err("api_key required") end
    local endpoint = "https://hubcapmanifest.com/api/v1/user/stats?api_key=" .. api_key
    local ok, resp = pcall(http_client.get, endpoint, { timeout = 10 })
    if ok and resp and resp.status == 200 then
        return resp.body -- already JSON string
    end
    return json_err("request failed")
end

function ValidateMorrenusKey(apiKey, contentScriptQuery)
    return ValidateManifestHubKey(apiKey, contentScriptQuery)
end

function ValidateManifestHubKey(apiKey, contentScriptQuery)
    if type(apiKey) == "table" then
        apiKey = apiKey.apiKey or apiKey.api_key
    end
    local ok, res = pcall(manifesthub.validate_key, apiKey)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- Live status of the Ryuu Generator session cookie (generator.ryuu.lol/api/check_session), so the
-- UI can tell the user whether the cookie is still valid instead of finding out on a failed add.
function GetRyuuSession(contentScriptQuery)
    local ok, res = pcall(function()
        local sess = ""
        pcall(function() sess = require("settings.manager").get_ryuu_session() or "" end)
        if sess == "" then return { success = true, configured = false } end
        local resp = http_client.get("https://generator.ryuu.lol/api/check_session",
            { headers = { ["Cookie"] = sess, ["User-Agent"] = "STLT-Rewired" }, timeout = 12 })
        if resp and resp.status == 200 and resp.body then
            local ok2, data = pcall(cjson.decode, resp.body)
            if ok2 and type(data) == "table" and data.username then
                return {
                    success = true, configured = true, valid = true,
                    username = tostring(data.username), premium = data.premium == true,
                    userId = tostring(data.user_id or ""),
                }
            end
        end
        return { success = true, configured = true, valid = false, status = (resp and resp.status) or 0 }
    end)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function SearchRyuuCatalog(contentScriptQuery, limit, query)
    if type(contentScriptQuery) == "table" then
        local p = contentScriptQuery
        query = p.query
        limit = p.limit
    end
    local ok, res = pcall(ryuu.search_catalog, query, limit)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function WarmRyuuCatalogCache(contentScriptQuery, forceRefresh)
    if type(contentScriptQuery) == "table" then
        forceRefresh = contentScriptQuery.forceRefresh
    end
    local ok, res = pcall(ryuu.warm_catalog_cache, forceRefresh == true)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function StartAddViaLuaToolsFromUrl(apiName, appid, contentScriptQuery, url)
    -- Millennium's IPC bridge sorts JS object keys alphabetically and passes their values as positional arguments.
    -- The JS passes: { apiName: ..., appid: ..., contentScriptQuery: "", url: ... }
    -- So the Lua signature MUST be (apiName, appid, contentScriptQuery, url)

    logger.log("StartAddViaLuaToolsFromUrl CALLED: appid=" ..
    tostring(appid) .. ", url=" .. tostring(url) .. ", apiName=" .. tostring(apiName))

    local ok, res = pcall(downloads.start_add_via_luatools_from_url, appid, url, apiName)
    if not ok then
        logger.warn("StartAddViaLuaToolsFromUrl CRASHED inside pcall: " .. tostring(res))
        return json_err(res)
    end

    return json_ok(res)
end

function GetIconDataUrl()
    -- Python read an icon file from the public dir and base64-encoded it
    local icon_path = fs.join(paths.get_plugin_dir(), "public", "luatools-icon.png")
    if fs.exists(icon_path) then
        local content = m_utils.read_file(icon_path)
        if content then
            return json_ok({ success = true, dataUrl = "data:image/png;base64," ..
            (m_utils.base64_encode and m_utils.base64_encode(content) or "") })
        end
    end
    return json_ok({ success = false, error = "icon not found" })
end

function GetGamesDatabase()
    local ok, res = pcall(function()
        local db_path = paths.backend_path("data/applist.json")
        if fs.exists(db_path) then
            local data = utils.read_json(db_path)
            return { success = true, apps = data.apps or data or {} }
        end
        return { success = true, apps = {} }
    end)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ReadLoadedApps()
    local ok, res = pcall(function()
        local log_path = paths.backend_path("loadedappids.txt")
        local apps = {}
        if fs.exists(log_path) then
            local text = utils.read_text(log_path)
            for line in (text .. "\n"):gmatch("([^\n]*)\n") do
                local appid = tonumber(line:match("^%s*(%d+)%s*$"))
                if appid then table.insert(apps, appid) end
            end
        end
        return { success = true, apps = apps }
    end)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function DismissLoadedApps()
    local ok, err = pcall(function()
        local log_path = paths.backend_path("loadedappids.txt")
        if fs.exists(log_path) then
            m_utils.write_file(log_path, "")
        end
    end)
    if not ok then return json_err(err) end
    return json_ok({ success = true })
end

function DeleteLuaToolsForApp(appid)
    if type(appid) == "table" then appid = appid.appid end
    local base = steam_utils.detect_steam_install_path()
    local target_dir = fs.join(base, "config", "stplug-in")
    local candidates = {
        fs.join(target_dir, tostring(appid) .. ".lua"),
        fs.join(target_dir, tostring(appid) .. ".lua.disabled"),
    }
    local deleted = {}
    for _, p in ipairs(candidates) do
        if fs.exists(p) then
            pcall(fs.remove, p)
            table.insert(deleted, p)
        end
    end
    return json_ok({ success = true, deleted = deleted, count = #deleted })
end

function CheckForFixes(appid)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(fixes.check_for_fixes, tonumber(appid))
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ApplyGameFix(appid, contentScriptQuery, downloadUrl, fixType, gameName, installPath)
    if type(appid) == "table" then
        local p = appid
        appid = p.appid
        downloadUrl = p.downloadUrl
        installPath = p.installPath
        fixType = p.fixType
        gameName = p.gameName
    end

    local ok, res = pcall(fixes.apply_game_fix,
        tonumber(appid), tostring(downloadUrl or ""),
        tostring(installPath or ""), tostring(fixType or ""), tostring(gameName or ""))
    if not ok then
        logger.warn("ApplyGameFix CRASHED: " .. tostring(res))
        return json_err(res)
    end
    return json_ok(res)
end

function GetApplyFixStatus(appid)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(fixes.get_apply_status, tonumber(appid))
    if not ok then return json_err(res) end
    return json_ok(res)
end

function CancelApplyFix(appid)
    return json_ok({ success = true })
end

function UninstallFix(appid)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(fixes.uninstall_fix, tonumber(appid))
    if not ok then return json_err(res) end
    return json_ok(res)
end

function UnFixGame(appid, contentScriptQuery, fixDate, installPath)
    if type(appid) == "table" then
        installPath = appid.installPath; fixDate = appid.fixDate; appid = appid.appid
    end
    local ok, res = pcall(fixes.unfix_game, appid, installPath, fixDate)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetUnfixStatus(appid)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(fixes.get_unfix_status, appid)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetInstalledFixes()
    local ok, res = pcall(fixes.get_installed_fixes)
    if not ok then return json_err(res) end
    return json_ok(res)
end

local _settings_inventory_scan_in_flight = false

local function list_installed_lua_scripts()
    local target_dir = unlock_paths.lua_script_dir()
    if not target_dir or target_dir == "" then
        logger.warn("GetInstalledLuaScripts: Steam install path not found")
        return { success = false, error = "Steam install path not found", scripts = st.A({}) }
    end

    local ok2, files = pcall(fs.list, target_dir)
    if not ok2 then
        logger.warn("GetInstalledLuaScripts: cannot list " .. tostring(target_dir) .. " — " .. tostring(files))
        return { success = false, error = "stplug-in not readable", scripts = st.A({}) }
    end

    local scripts = {}
    if files then
        for _, entry in ipairs(files) do
            local name = entry.name or ""
            if name:match("%.lua$") or name:match("%.lua%.disabled$") then
                local aid = name:match("^(%d+)%.")
                if aid then
                    table.insert(scripts, {
                        appid      = tonumber(aid),
                        gameName   = "Unknown Game (" .. aid .. ")",
                        filename   = name,
                        isDisabled = name:match("%.disabled$") ~= nil,
                        path       = entry.path or ""
                    })
                end
            end
        end
    end
    logger.log("GetInstalledLuaScripts: " .. tostring(#scripts) .. " script(s) in " .. tostring(target_dir))
    return { success = true, scripts = st.A(scripts), scannedPath = target_dir }
end

function GetInstalledLuaScripts()
    local ok, res = pcall(list_installed_lua_scripts)
    if not ok then return json_err(res) end
    return json_ok(res)
end

--- Single Settings scan: library fix walk + lua script listing in one native RPC return.
function GetSettingsInstalledInventory()
    if _settings_inventory_scan_in_flight then
        logger.warn("GetSettingsInstalledInventory: rejected re-entrant scan")
        return json_ok({ success = false, error = "Settings inventory scan already in progress", busy = true })
    end
    _settings_inventory_scan_in_flight = true
    local ok, res = pcall(function()
        local fixes_ok, fixes_res = pcall(fixes.get_installed_fixes)
        local lua_ok, lua_res = pcall(list_installed_lua_scripts)
        local payload = {
            success = true,
            fixes = st.A({}),
            scripts = st.A({}),
            scannedPath = "",
        }
        if fixes_ok and type(fixes_res) == "table" then
            payload.fixes = fixes_res.fixes or st.A({})
        else
            payload.fixesError = tostring(fixes_res)
            logger.warn("GetSettingsInstalledInventory: fixes scan failed — " .. payload.fixesError)
        end
        if lua_ok and type(lua_res) == "table" then
            payload.scripts = lua_res.scripts or st.A({})
            payload.scannedPath = lua_res.scannedPath or ""
        else
            payload.scriptsError = tostring(lua_res)
            logger.warn("GetSettingsInstalledInventory: lua scan failed — " .. payload.scriptsError)
        end
        if not fixes_ok and not lua_ok then
            payload.success = false
            payload.error = "Failed to scan installed fixes and lua scripts"
        end
        logger.log("GetSettingsInstalledInventory: " .. tostring(#payload.fixes) .. " fix(es), "
            .. tostring(#payload.scripts) .. " lua script(s)")
        return payload
    end)
    _settings_inventory_scan_in_flight = false
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetGameInstallPath(appid)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(steam_utils.get_game_install_path_response, tonumber(appid))
    if not ok then return json_err(res) end
    return json_ok(res)
end

function OpenGameFolder(path)
    if type(path) == "table" then path = path.path end
    local ok, success = pcall(steam_utils.open_game_folder, tostring(path or ""))
    if ok and success then
        return json_ok({ success = true })
    end
    return json_ok({ success = false, error = "Failed to open path" })
end

function OpenExternalUrl(url)
    if type(url) == "table" then url = url.url end
    url = tostring(url or "")
    if not (url:sub(1, 7) == "http://" or url:sub(1, 8) == "https://") then
        return json_err("Invalid URL")
    end
    local is_win = (m_utils.getenv("OS") or ""):find("Windows") ~= nil
    if is_win then
        pcall(m_utils.exec, 'start "" "' .. url .. '"')
    else
        pcall(m_utils.exec, 'xdg-open "' .. url .. '"')
    end
    return json_ok({ success = true })
end

function GetSettingsConfig()
    local ok, payload = pcall(settings_manager.get_settings_payload)
    if not ok then
        logger.warn("GetSettingsConfig failed: " .. tostring(payload))
        return json_err(payload)
    end
    return json_ok({
        success       = true,
        schemaVersion = payload.version,
        schema        = payload.schema or {},
        values        = payload.values or {},
        language      = payload.language,
        locales       = payload.locales or {},
        translations  = payload.translations or {}
    })
end

function GetThemes()
    local themes_json_path = fs.join(paths.get_plugin_dir(), "public", "themes", "themes.json")
    local themes_array = {}

    if fs.exists(themes_json_path) then
        local success, data = pcall(cjson.decode, utils.read_text(themes_json_path))
        if success and type(data) == "table" then
            themes_array = data
        else
            logger.warn("GetThemes failed to decode themes.json")
        end
    else
        logger.warn("GetThemes: themes.json not found")
    end

    return json_ok({ success = true, themes = themes_array })
end

function ApplySettingsChanges(changes)
    -- Millennium may pass the argument as a JSON string rather than a decoded table.
    -- Mirror the Python version's parsing logic exactly.
    local payload = nil

    if type(changes) == "string" and changes ~= "" then
        -- Try to decode the JSON string
        local ok, decoded = pcall(cjson.decode, changes)
        if not ok then
            logger.warn("ApplySettingsChanges: failed to parse changes string")
            return json_err("Invalid JSON payload")
        end
        -- Unwrap nested wrappers the JS bridge sometimes adds
        if type(decoded) == "table" and decoded.changes then
            payload = decoded.changes
        elseif type(decoded) == "table" and type(decoded.changesJson) == "string" then
            local ok2, inner = pcall(cjson.decode, decoded.changesJson)
            if ok2 then payload = inner else return json_err("Invalid JSON payload") end
        else
            payload = decoded
        end
    elseif type(changes) == "table" then
        -- Already a decoded table – handle wrapper keys
        if changes.changes then
            payload = changes.changes
        elseif type(changes.changesJson) == "string" then
            local ok2, inner = pcall(cjson.decode, changes.changesJson)
            if ok2 then payload = inner else return json_err("Invalid JSON payload") end
        else
            payload = changes
        end
    else
        payload = {}
    end

    if payload == nil then payload = {} end

    if type(payload) ~= "table" then
        logger.warn("ApplySettingsChanges: payload is not a table: " .. tostring(payload))
        return json_err("Invalid payload format")
    end

    logger.log("ApplySettingsChanges payload: " .. (pcall(cjson.encode, payload) and cjson.encode(payload) or "?"))

    local ok, res = pcall(settings_manager.apply_settings_changes, payload)
    if not ok then
        logger.warn("ApplySettingsChanges failed: " .. tostring(res))
        return json_err(res)
    end
    return json_ok(res)
end

function GetAvailableLocales()
    local ok, locs = pcall(settings_manager.get_available_locales)
    if not ok then return json_err(locs) end
    return json_ok({ success = true, locales = locs })
end

function GetTranslations(language)
    -- Handle both {language="en"} table and plain string argument
    if type(language) == "table" then
        language = language.language or language.lang
    end
    language = tostring(language or locales_mod.DEFAULT_LOCALE)

    local ok, strings = pcall(function()
        return locales_mod.get_locale_manager():get_locale_strings(language)
    end)
    if not ok then
        logger.warn("GetTranslations failed: " .. tostring(strings))
        return json_err(strings)
    end

    -- Frontend expects: { success, strings:{...}, language, locales:[...] }
    local ok2, locs = pcall(settings_manager.get_available_locales)
    return json_ok({
        success  = true,
        strings  = strings or {},
        language = language,
        locales  = ok2 and locs or {}
    })
end

-- ── Cache & disk tools (ported from steamtools.py) ───────────────────────────

function GetCacheInfo()
    local ok, res = pcall(cache_tools.get_cache_info)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function CleanSteamCache(categories)
    local ok, res = pcall(cache_tools.clean_cache, categories)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetSteamFolderStats()
    local ok, res = pcall(cache_tools.get_steam_folder_stats)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetSteamProcessInfo()
    local ok, res = pcall(cache_tools.get_steam_process_info)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetQuickDashboard()
    local ok, res = pcall(cache_tools.get_quick_dashboard)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ScanSteamLibraries()
    local ok, res = pcall(cache_tools.scan_steam_libraries)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Lua script tools (ported from steamtools.py) ─────────────────────────────

function GetSteamToolsIds(contentScriptQuery, showDisabled)
    local ok, res = pcall(lua_tools.get_steamtools_ids, showDisabled)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ToggleLuaScript(appid, contentScriptQuery, enable)
    if type(appid) == "table" then
        enable = appid.enable
        appid = appid.appid
    end
    local ok, res = pcall(lua_tools.toggle_lua_script, tonumber(appid), enable)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ValidateLuaSyntax(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(lua_tools.validate_lua_syntax, appid)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function CleanLuaContent(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(lua_tools.clean_lua_content, tonumber(appid))
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ExtractLuaKeys(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(lua_tools.extract_lua_keys, tonumber(appid))
    if not ok then return json_err(res) end
    return json_ok(res)
end

function AuditLuaContent(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(lua_tools.audit_lua_content, tonumber(appid))
    if not ok then return json_err(res) end
    return json_ok(res)
end

function DetectDepotConflicts()
    local ok, res = pcall(lua_tools.detect_depot_conflicts)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function BatchHealthScan()
    local ok, res = pcall(lua_tools.batch_health_scan)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Custom APIs & source chain (custom_apis.py / source_chain.py) ─────────────

function GetCustomApis()
    local ok, res = pcall(custom_apis.get_custom_apis)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function SaveCustomApis(apis_json, contentScriptQuery)
    local ok, res = pcall(custom_apis.save_custom_apis, apis_json)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetSourceChain()
    local ok, res = pcall(source_chain.get_source_chain_json)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function SaveSourceChain(chain_json, contentScriptQuery)
    local ok, res = pcall(source_chain.save_source_chain_json, chain_json)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Download history & config transfer (history.py / config_transfer.py) ──────

function GetDownloadHistory(appid, contentScriptQuery, limit, source, status)
    local ok, res = pcall(history.get_download_history_json, appid, limit, status, source)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetDownloadStats()
    local ok, res = pcall(history.get_download_stats_json)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function PruneHistory(contentScriptQuery, days)
    local ok, res = pcall(history.prune_history_json, days)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ExportConfig()
    local ok, res = pcall(config_transfer.export_config)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ImportConfig(config_json, contentScriptQuery)
    local ok, res = pcall(config_transfer.import_config, config_json)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── DLC config & overview (steamtools.py) ────────────────────────────────────

function GenerateDlcConfig(appid, contentScriptQuery, format)
    if type(appid) == "table" then
        format = appid.format
        appid = appid.appid
    end
    local ok, res = pcall(dlc.generate_dlc_config, appid, format)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetDlcOverview(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(dlc.get_dlc_overview, appid)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function UnlockAllDlc(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(dlc.unlock_all_dlc, appid)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Hooks (events.py) ────────────────────────────────────────────────────────

function GetHooksConfig()
    local ok, res = pcall(events.get_hooks_config)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function SaveHooksConfig(config_json, contentScriptQuery)
    if type(config_json) == "table" and config_json.config_json ~= nil then config_json = config_json.config_json end
    local ok, res = pcall(events.save_hooks_config_json, config_json)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Mods (mod_system.py) ─────────────────────────────────────────────────────

function GetModList()
    local ok, res = pcall(mods.get_mod_list)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetModFile(contentScriptQuery, filename, mod_id)
    if type(contentScriptQuery) == "table" then
        filename = contentScriptQuery.filename
        mod_id = contentScriptQuery.mod_id
    end
    -- returns raw file content (matches Python), not JSON-wrapped
    local ok, res = pcall(mods.get_mod_file, mod_id, filename)
    if not ok then return "" end
    return res
end

function ToggleMod(contentScriptQuery, enabled, mod_id)
    if type(contentScriptQuery) == "table" then
        enabled = contentScriptQuery.enabled
        mod_id = contentScriptQuery.mod_id
    end
    local ok, res = pcall(mods.toggle_mod, mod_id, enabled)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetModLoaderInfo()
    local ok, res = pcall(mods.get_mod_loader_info)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function InstallModFromUrl(contentScriptQuery, url)
    if type(contentScriptQuery) == "table" then url = contentScriptQuery.url end
    local ok, res = pcall(mods.install_mod_from_url, url)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function UninstallMod(contentScriptQuery, mod_id)
    if type(contentScriptQuery) == "table" then mod_id = contentScriptQuery.mod_id end
    local ok, res = pcall(mods.uninstall_mod, mod_id)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Profiles (profiles.py) ───────────────────────────────────────────────────

function ListProfilesFor(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(profiles.list_profiles_for, appid)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function SaveProfile(accountId32, appid, contentScriptQuery, description, name)
    if type(accountId32) == "table" then
        local t = accountId32
        appid = t.appid; name = t.name; description = t.description; accountId32 = t.accountId32
    end
    local ok, res = pcall(profiles.save_profile, appid, name, description, accountId32)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ActivateProfile(accountId32, appid, applyLaunchOptions, contentScriptQuery, slug)
    if type(accountId32) == "table" then
        local t = accountId32
        appid = t.appid; slug = t.slug
        applyLaunchOptions = t.applyLaunchOptions; accountId32 = t.accountId32
    end
    local ok, res = pcall(profiles.activate_profile, appid, slug, applyLaunchOptions, accountId32)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function DeleteProfile(appid, contentScriptQuery, slug)
    if type(appid) == "table" then slug = appid.slug; appid = appid.appid end
    local ok, res = pcall(profiles.delete_profile, appid, slug)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ListAllProfiles()
    local ok, res = pcall(profiles.list_all_profiles)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Steam version & per-game update lock (steam_version.py / acf_writer.py) ───

function GetSteamVersionInfo()
    local ok, res = pcall(steam_version.get_steam_version_info)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function SetSteamUpdateBlock(contentScriptQuery, enabled)
    if type(contentScriptQuery) == "table" then enabled = contentScriptQuery.enabled end
    local ok, res = pcall(steam_version.set_steam_update_block, enabled)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ListSteamCfgBackups()
    local ok, res = pcall(steam_version.list_steam_cfg_backups)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function SetGameUpdatesDisabled(appid, contentScriptQuery, disabled)
    if type(appid) == "table" then disabled = appid.disabled; appid = appid.appid end
    local ok, res = pcall(acf_lock.set_game_update_lock, appid, disabled)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetGameUpdateLockStatus(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(acf_lock.get_game_update_lock_status, appid)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Crack migrator (crack_migrator.py) ───────────────────────────────────────

function ScanCrackedGames()
    local ok, res = pcall(crack_migrator.scan_all_games)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function MigrateGame(appid, contentScriptQuery, dryRun)
    if type(appid) == "table" then dryRun = appid.dryRun; appid = appid.appid end
    local ok, res = pcall(crack_migrator.migrate_game, appid, dryRun)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function UndoMigration(appid, backupDir, contentScriptQuery)
    if type(appid) == "table" then backupDir = appid.backupDir; appid = appid.appid end
    local ok, res = pcall(crack_migrator.undo_migration, appid, backupDir)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ListMigrations()
    local ok, res = pcall(crack_migrator.list_migrations)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Manifests & depot (steamtools.py) ────────────────────────────────────────

function UpdateManifests(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(manifests.update_manifests, appid)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function CheckManifestStaleness(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(manifests.check_manifest_staleness, appid)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function SyncDepotcache(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(manifests.sync_depotcache, appid)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function RunManifestAutoUpdate(contentScriptQuery, force)
    if type(contentScriptQuery) == "table" then
        force = contentScriptQuery.force
    end
    local ok, res = pcall(manifest_auto.run_scheduled, force == true)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function UpdateManifestsForApp(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(manifest_auto.update_app, appid, "manual")
    if not ok then return json_err(res) end
    return json_ok(res)
end

function RepairDepotCache(appid, contentScriptQuery, dry_run, fix_lua, orphan_age_days, remove_orphans)
    -- Inventory report only; never mutates (see manifests.repair_depotcache), so dry_run/
    -- remove_orphans are accepted for the frontend contract but do not change behavior.
    local fix = fix_lua == true or fix_lua == "true" or fix_lua == 1 or fix_lua == "1"
    local ok, res = pcall(manifests.repair_depotcache, dry_run, fix, orphan_age_days, remove_orphans)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Diagnostics: cloud fix + millennium health (cloud_fix.py / health.py) ─────

function DiagnoseCloudFix()
    local ok, res = pcall(cloud_fix.diagnose_cloud_fix)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function RemoveStellaFallback()
    local ok, res = pcall(cloud_fix.remove_stella_fallback)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetMillenniumHealth()
    local ok, res = pcall(health.get_millennium_health)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Diagnostics: per-app report (steamtools.py) ──────────────────────────────

function DiagnoseApp(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(diagnostics.diagnose_app, appid)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ExportDiagnosticReport(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(diagnostics.export_diagnostic_report, appid)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Workshop (workshop_manager.py) ───────────────────────────────────────────

function ListWorkshopSubscribed(accountId32, appid, contentScriptQuery)
    if type(accountId32) == "table" then
        appid = accountId32.appid; accountId32 = accountId32.accountId32
    end
    local ok, res = pcall(workshop.list_subscribed, appid, accountId32)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ListLocalWorkshopItems(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(workshop.list_local_items, appid)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function DownloadWorkshopItem(appid, contentScriptQuery, workshopId)
    if type(appid) == "table" then workshopId = appid.workshopId; appid = appid.appid end
    local ok, res = pcall(workshop.download_item, appid, workshopId)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function DeleteWorkshopItem(appid, contentScriptQuery, workshopId)
    if type(appid) == "table" then workshopId = appid.workshopId; appid = appid.appid end
    local ok, res = pcall(workshop.delete_item, appid, workshopId)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Batch download pipeline (batch.py) ───────────────────────────────────────

local function decode_id_array(v)
    if type(v) == "table" then return v end
    if type(v) == "string" and v ~= "" then
        local ok, parsed = pcall(cjson.decode, v)
        if ok and type(parsed) == "table" then return parsed end
    end
    return {}
end

function StartBatchDownload(appids_json, contentScriptQuery, delay, force, max_retries, parallel, priority_json, skip_installed)
    local appids = decode_id_array(appids_json)
    local prio = decode_id_array(priority_json)
    local ok, res = pcall(batch.start_batch, appids, parallel, max_retries, delay, prio, skip_installed, force)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetBatchStatus()
    local ok, res = pcall(batch.get_batch_status)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function CancelBatch()
    local ok, res = pcall(batch.cancel_batch)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function PauseBatch()
    local ok, res = pcall(batch.pause_batch)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function UnpauseBatch()
    local ok, res = pcall(batch.unpause_batch)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function SkipBatchItem(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(batch.skip_batch_item, appid)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ResumeBatch()
    local ok, res = pcall(batch.resume_batch)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Achievements (achievement_watch.py / steamtools.py) ──────────────────────

function GetAchievementInfo(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(achievements.get_achievement_info, appid)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function SeedAchievementFiles(accountId32, appid, contentScriptQuery)
    if type(accountId32) == "table" then appid = accountId32.appid; accountId32 = accountId32.accountId32 end
    local ok, res = pcall(achievements.seed_achievement_files, appid, accountId32)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetActiveAccounts()
    local ok, res = pcall(achievements.get_active_accounts)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetAchievementProgress(accountId32, appid, contentScriptQuery)
    if type(accountId32) == "table" then appid = accountId32.appid; accountId32 = accountId32.accountId32 end
    local ok, res = pcall(achievements.get_achievement_progress, appid, accountId32)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ListAchievementWatchlist(accountId32, contentScriptQuery)
    if type(accountId32) == "table" then accountId32 = accountId32.accountId32 end
    local ok, res = pcall(achievements.list_watchlist, accountId32)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetRecentAchievementUnlocks(accountId32, contentScriptQuery, limit)
    if type(accountId32) == "table" then limit = accountId32.limit; accountId32 = accountId32.accountId32 end
    local ok, res = pcall(achievements.get_recent_unlocks, accountId32, limit)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Backup / restore (steamtools.py) ─────────────────────────────────────────

function CreateBackup(contentScriptQuery, label)
    if type(contentScriptQuery) == "table" then label = contentScriptQuery.label end
    local ok, res = pcall(backup.create_backup, label)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ListBackups()
    local ok, res = pcall(backup.list_backups)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function RestoreBackup(contentScriptQuery, filename)
    if type(filename) == "table" then filename = filename.filename end
    local ok, res = pcall(backup.restore_backup, filename)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function DeleteBackup(contentScriptQuery, filename)
    if type(filename) == "table" then filename = filename.filename end
    local ok, res = pcall(backup.delete_backup, filename)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Key vault (key_vault.py) ─────────────────────────────────────────────────

function ListKeyProfiles()
    local ok, res = pcall(key_vault.list_profiles)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function SaveKeyProfile(contentScriptQuery, name)
    if type(contentScriptQuery) == "table" then name = contentScriptQuery.name end
    local ok, res = pcall(key_vault.save_profile, name)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function LoadKeyProfile(contentScriptQuery, name)
    if type(contentScriptQuery) == "table" then name = contentScriptQuery.name end
    local ok, res = pcall(key_vault.load_profile, name)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function DeleteKeyProfile(contentScriptQuery, name)
    if type(contentScriptQuery) == "table" then name = contentScriptQuery.name end
    local ok, res = pcall(key_vault.delete_profile, name)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ExportKeyProfile(contentScriptQuery, name)
    if type(contentScriptQuery) == "table" then name = contentScriptQuery.name end
    local ok, res = pcall(key_vault.export_profile, name)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ImportKeyProfile(activate, blob, contentScriptQuery, nameOverride)
    if type(activate) == "table" then
        local t = activate
        blob = t.blob
        nameOverride = t.nameOverride
        activate = t.activate
        contentScriptQuery = t.contentScriptQuery
    end
    local ok, res = pcall(key_vault.import_profile, blob, nameOverride, activate)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Tokeer / Denuvo launch options (tokeer_launcher.py) ──────────────────────

function ListTokeerGames()
    local ok, res = pcall(tokeer.list_tokeer_games)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function CheckTokeerStatus(accountId32, appid, contentScriptQuery)
    if type(accountId32) == "table" then appid = accountId32.appid; accountId32 = accountId32.accountId32 end
    local ok, res = pcall(tokeer.check_tokeer_status, appid, accountId32)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ConfigureTokeerLaunch(accountId32, appid, contentScriptQuery)
    if type(accountId32) == "table" then appid = accountId32.appid; accountId32 = accountId32.accountId32 end
    local ok, res = pcall(tokeer.configure_tokeer_launch, appid, accountId32)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function RemoveTokeerLaunch(accountId32, appid, contentScriptQuery)
    if type(accountId32) == "table" then appid = accountId32.appid; accountId32 = accountId32.accountId32 end
    local ok, res = pcall(tokeer.remove_tokeer_launch, appid, accountId32)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Sync (sync_engine.py) ────────────────────────────────────────────────────

function GetSyncConfig()
    local ok, res = pcall(sync.get_sync_config)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function SetSyncConfig(contentScriptQuery, updates)
    if type(contentScriptQuery) == "table" then updates = contentScriptQuery.updates or contentScriptQuery end
    local ok, res = pcall(sync.set_sync_config, updates)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function SyncPush()
    local ok, res = pcall(sync.sync_push)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function SyncPull(contentScriptQuery, dryRun)
    if type(contentScriptQuery) == "table" then dryRun = contentScriptQuery.dryRun end
    local ok, res = pcall(sync.sync_pull, dryRun)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function SyncStatus()
    local ok, res = pcall(sync.sync_status)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function SyncTestConnection()
    local ok, res = pcall(sync.sync_test_connection)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Account switch / transfer (account_switch.py / account_transfer.py) ──────

function ExtractLoginTokens()
    local ok, res = pcall(account.extract_login_tokens)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function SwitchToAccount(accountName, contentScriptQuery)
    if type(accountName) == "table" then accountName = accountName.accountName end
    local ok, res = pcall(account.switch_to_account, accountName)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ListUserdataAccounts()
    local ok, res = pcall(account.list_accounts)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function InspectGameUserdata(accountId32, appid, contentScriptQuery)
    if type(accountId32) == "table" then appid = accountId32.appid; accountId32 = accountId32.accountId32 end
    local ok, res = pcall(account.inspect_game_data, accountId32, appid)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function TransferGameUserdata(a1, a2, a3, a4, a5, a6)
    local from, to, appid, overwrite, backup
    if type(a1) == "table" then
        from = a1.fromAccountId32; to = a1.toAccountId32; appid = a1.appid
        overwrite = a1.overwrite; backup = a1.backup
    else
        -- positional alphabetical: appid, backup, contentScriptQuery, fromAccountId32, overwrite, toAccountId32
        appid = a1; backup = a2; from = a4; overwrite = a5; to = a6
    end
    local ok, res = pcall(account.transfer_game_data, from, to, appid, overwrite, backup)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function RestoreGameUserdataBackup(accountId32, appid, backupPath, contentScriptQuery)
    if type(accountId32) == "table" then
        appid = accountId32.appid; backupPath = accountId32.backupPath; accountId32 = accountId32.accountId32
    end
    local ok, res = pcall(account.restore_transfer_backup, accountId32, appid, backupPath)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ListUserdataBackups()
    local ok, res = pcall(account.list_game_data_backups)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Sentinel (sentinel.py) - config functional; daemon/service unavailable ───

function GetSentinelStatus()
    local ok, res = pcall(sentinel.get_status)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function SetSentinelConfig(config_json, contentScriptQuery)
    local ok, res = pcall(sentinel.set_config, config_json)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function IgnoreGameNotifications(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(sentinel.ignore_game, appid)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function UnignoreGameNotifications(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(sentinel.unignore_game, appid)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function StartSentinel()
    return json_ok(sentinel.start())
end

function StopSentinel()
    return json_ok(sentinel.stop())
end

function GetSentinelService()
    return json_ok(sentinel.get_service())
end

function InstallSentinelService()
    return json_ok(sentinel.install_service())
end

function UninstallSentinelService()
    return json_ok(sentinel.uninstall_service())
end

function StartSentinelServiceNow()
    return json_ok(sentinel.start_service_now())
end

-- ── LuaTools Gen2 parity / safe companion workflows ─────────────────────────

function GetSourceHealth()
    local ok, res = pcall(feature_parity.get_source_health)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetCompanionStatus()
    local ok, res = pcall(feature_parity.get_companion_status)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function OpenCompanionPath(contentScriptQuery, path)
    if type(contentScriptQuery) == "table" then
        path = contentScriptQuery.path
    elseif (not path or path == "") and type(contentScriptQuery) == "string" and contentScriptQuery ~= "" then
        path = contentScriptQuery
    end
    local ok, res = pcall(feature_parity.open_path, path)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function GetCloudRedirectGuide(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(feature_parity.get_cloudredirect_guide, appid)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function ExportSupportBundle(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(feature_parity.export_support_bundle, appid)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Frontend log passthrough ────────────────────────────────────────────────

function LogFrontend(message)
    if type(message) == "table" then message = message.message end
    pcall(logger.log, "[frontend] " .. tostring(message or ""))
    return json_ok({ success = true })
end

-- ── Windows platform: compat tools / Linux preflight are not applicable ──────
-- STLT's frontend gates these behind a platform check; we report "windows" so
-- the Linux Proton / SLSsteam paths stay hidden, and give honest errors if hit.

function GetCompatToolStatus()
    return json_ok({ success = true, platform = "windows" })
end

function FixCompatToolsForActivated(contentScriptQuery, force, tool)
    return json_ok({ success = false, platform = "windows",
        error = "Proton compat tools are Linux-only; Windows uses native Steam." })
end

function GetLinuxHealthReport(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    local ok, res = pcall(health.run_health_check, tonumber(appid), false)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function EnsureStpluginDir()
    local ok, res = pcall(health.ensure_lua_script_dir)
    if not ok then return json_err(res) end
    return json_ok({ success = res == true })
end

function EnsureLuaScriptDir()
    local ok, res = pcall(health.ensure_lua_script_dir)
    if not ok then return json_err(res) end
    return json_ok({ success = res == true })
end

function InstallOpenSteamTool()
    local ok, ost = pcall(require, "opensteamtool_install")
    if not ok or not ost then return json_err(ost) end
    local ok2, res = pcall(ost.install_latest)
    if not ok2 then return json_err(res) end
    return json_ok(res)
end

function GetUnlockStatus()
    local ok, unlock_paths = pcall(require, "unlock_paths")
    if not ok or not unlock_paths then return json_err(unlock_paths) end
    local ok2, res = pcall(unlock_paths.get_unlock_status)
    if not ok2 then return json_err(res) end
    return json_ok({ success = true, status = res })
end

function GetSetupState()
    local ok, res = pcall(setup_assistant.get_setup_state)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function RunSetup()
    local ok, res = pcall(setup_assistant.run_setup)
    if not ok then return json_err(res) end
    return json_ok(res)
end

function MarkSetupSeen()
    local ok, res = pcall(setup_assistant.mark_setup_seen)
    if not ok then return json_err(res) end
    return json_ok({ success = res == true })
end

function SelfHeal()
    local ok, res = pcall(setup_assistant.self_heal)
    if not ok then return json_err(res) end
    return json_ok(res)
end

-- ── Live activation flow (Windows: hand steam://install to the OS) ───────────

function AutoFinalizeActivation(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    appid = tonumber(appid)
    if not appid then return json_err("Invalid appid") end
    -- Match upstream ltsteamplugin behavior: after the .lua is written, kick off
    -- steam://install on the running client so the user does not need a full restart.
    local ok = pcall(m_utils.exec, 'start "" "steam://install/' .. appid .. '"')
    return json_ok({
        success = ok == true,
        appid = appid,
        skipped = false,
        downloadTriggered = ok == true,
        autoFixed = st.A({}),
        message = ok and ("Triggered download for AppID " .. appid .. " on the running Steam client.")
                     or "Game files were added, but steam://install could not be launched.",
    })
end

function StartDownloadNoRestart(appid, contentScriptQuery)
    if type(appid) == "table" then appid = appid.appid end
    appid = tonumber(appid)
    if not appid then return json_err("Invalid appid") end
    local ok = pcall(m_utils.exec, 'start "" "steam://install/' .. appid .. '"')
    return json_ok({ success = ok == true, appid = appid,
        message = ok and ("Triggered download for " .. appid .. " on the running Steam.")
                     or "Failed to trigger steam://install." })
end

function SmartRestartSteam(clearBeta, contentScriptQuery)
    local ok, success = pcall(auto_update.restart_steam)
    if ok and success then
        return json_ok({ success = true, message = "Steam restarted." })
    end
    return json_ok({ success = false, error = "Failed to restart Steam." })
end

-- ── Return lifecycle table ────────────────────────────────────────────────────

return {
    on_load            = on_load,
    on_unload          = on_unload,
    on_frontend_loaded = on_frontend_loaded,
}
