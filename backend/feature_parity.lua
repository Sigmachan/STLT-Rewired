-- feature_parity.lua — safe Gen2 LuaTools parity helpers for STLT-Rewired.
--
-- This module intentionally adopts the *workflow shape* discovered in the Gen2
-- portable app (source health, companion status, CloudRedirect/Steamless/unlocker
-- explicit flows, support bundle), without copying closed implementation details
-- and without silently patching Steam/SteamTools/CloudRedirect layers.

local fs          = require("fs")
local m_utils     = require("utils")
local http_client = require("http_client")
local paths       = require("paths")
local st          = require("st_util")
local utils       = require("plugin_utils")
local steam_utils = require("steam_utils")

local M = {}

local RYUU_HOST = "generator.ryuu.lol"

local function A(t) return st.A(t or {}) end

local function getenv(name)
    local ok, v = pcall(m_utils.getenv, name)
    if ok and v and v ~= "" then return tostring(v) end
    return ""
end

local function join_nonempty(a, b, c, d)
    if not a or a == "" then return "" end
    local p = fs.join(a, b)
    if c then p = fs.join(p, c) end
    if d then p = fs.join(p, d) end
    return p
end

local function safe_exists(path)
    if not path or path == "" then return false end
    local ok, yes = pcall(fs.exists, path)
    return ok and yes == true
end

local function safe_file(path)
    if not path or path == "" then return false end
    local ok, yes = pcall(fs.is_file, path)
    return ok and yes == true
end

local function redact_text(text)
    text = tostring(text or "")
    local patterns = {
        '([Cc]ookie%s*[:=]%s*)[^\r\n,}]+',
        '([Aa]uthorization%s*[:=]%s*)[^\r\n,}]+',
        '([Aa]pi[_-]?[Kk]ey%s*[:=]%s*)[^\r\n,}]+',
        '([Tt]oken%s*[:=]%s*)[^\r\n,}]+',
        '([Ss]ession%s*[:=]%s*)[^\r\n,}]+',
        '([Pp]assword%s*[:=]%s*)[^\r\n,}]+',
    }
    for _, pat in ipairs(patterns) do
        text = text:gsub(pat, "%1<redacted>")
    end
    text = text:gsub('("ryuuSession"%s*:%s*")[^"]+', '%1<redacted>')
    text = text:gsub('("morrenusApiKey"%s*:%s*")[^"]+', '%1<redacted>')
    text = text:gsub('("api_key"%s*:%s*")[^"]+', '%1<redacted>')
    text = text:gsub('(<moapikey>)', '<redacted-key>')
    return text
end

local function redacted_url(url)
    url = tostring(url or "")
    url = url:gsub("api_key=[^&]+", "api_key=<redacted>")
    url = url:gsub("key=[^&]+", "key=<redacted>")
    url = url:gsub("token=[^&]+", "token=<redacted>")
    url = url:gsub("<moapikey>", "<redacted-key>")
    return url
end

local function classify_source(api)
    local name = tostring(api.name or "")
    local url = tostring(api.url or "")
    local low = (name .. " " .. url):lower()
    if low:find("ryuu", 1, true) then return "ryuu" end
    if low:find("morrenus", 1, true) or low:find("hubcap", 1, true) or low:find("moapikey", 1, true) then return "hubcap" end
    if low:find("github", 1, true) then return "github" end
    if low:find("manifest", 1, true) then return "manifest" end
    return "custom"
end

local function probe_url(url, timeout, opts)
    opts = opts or {}
    if not url or url == "" then return { ok = false, status = 0, error = "empty URL" } end
    local probe = url:gsub("<appid>", "480"):gsub("{appid}", "480")
    if opts.morrenus_key and opts.morrenus_key ~= "" then
        probe = probe:gsub("<moapikey>", opts.morrenus_key)
    else
        probe = probe:gsub("<moapikey>", "")
    end
    if not (probe:sub(1, 7) == "http://" or probe:sub(1, 8) == "https://") then
        return { ok = false, status = 0, error = "not HTTP" }
    end
    local headers = { ["User-Agent"] = "STLT-Rewired/source-health" }
    if opts.ryuu_session and opts.ryuu_session ~= "" and probe:find(RYUU_HOST, 1, true) then
        headers["Cookie"] = opts.ryuu_session
    end
    local ok, resp = pcall(http_client.get, probe, { timeout = timeout or 7, headers = headers })
    if not ok then return { ok = false, status = 0, error = tostring(resp) } end
    local status = resp and tonumber(resp.status) or 0
    return { ok = status > 0 and status < 500, status = status, error = status == 0 and "no response" or nil }
end

function M.get_source_health()
    local items = {}
    local counts = { ok = 0, warn = 0, error = 0, skipped = 0 }

    local all_apis = {}
    pcall(function()
        local api_manifest = require("api_manifest")
        local res = api_manifest.get_all_apis()
        all_apis = res.apis or {}
    end)

    local sm = nil
    pcall(function() sm = require("settings.manager") end)
    local morrenus_key = ""
    local ryuu_session = ""
    if sm then
        pcall(function() morrenus_key = sm.get_morrenus_api_key() or "" end)
        pcall(function() ryuu_session = sm.get_ryuu_session() or "" end)
    end

    for _, api in ipairs(all_apis or {}) do
        local kind = classify_source(api)
        local enabled = api.enabled ~= false
        local status = "skipped"
        local message = enabled and "Not probed" or "Disabled"
        local http_status = 0

        if enabled then
            if kind == "hubcap" and morrenus_key == "" then
                status = "warn"
                message = "ManifestHub source needs an API key"
            elseif kind == "ryuu" and ryuu_session == "" then
                status = "warn"
                message = "Ryuu source needs a local session cookie"
            else
                local pr = probe_url(api.url, 6, { morrenus_key = morrenus_key, ryuu_session = ryuu_session })
                http_status = pr.status or 0
                if pr.status == 200 or pr.status == 204 or pr.status == tonumber(api.success_code or 200) then
                    status = "ok"; message = "Reachable"
                elseif pr.status == tonumber(api.unavailable_code or 404) or pr.status == 404 then
                    status = "ok"; message = "Reachable; test AppID unavailable"
                elseif pr.status == 401 or pr.status == 403 then
                    status = "warn"; message = "Auth rejected or missing"
                elseif pr.status == 429 then
                    status = "warn"; message = "Rate limited"
                elseif pr.status > 0 and pr.status < 500 then
                    status = "warn"; message = "HTTP " .. tostring(pr.status)
                else
                    status = "error"; message = pr.error or "No response"
                end
            end
        end

        counts[status] = (counts[status] or 0) + 1
        table.insert(items, {
            name = tostring(api.name or "Unknown"),
            kind = kind,
            enabled = enabled,
            url = redacted_url(api.url),
            status = status,
            httpStatus = http_status,
            message = message,
        })
    end

    local fixes = { name = "LuaTools fixes index", kind = "fixes", enabled = true, url = "https://index.luatools.work/fixes-index.json" }
    local pr = probe_url(fixes.url, 7)
    fixes.httpStatus = pr.status or 0
    if pr.status == 200 then fixes.status = "ok"; fixes.message = "Reachable"
    elseif pr.status == 429 then fixes.status = "warn"; fixes.message = "Rate limited"
    elseif pr.status > 0 then fixes.status = "warn"; fixes.message = "HTTP " .. tostring(pr.status)
    else fixes.status = "error"; fixes.message = pr.error or "No response" end
    counts[fixes.status] = (counts[fixes.status] or 0) + 1
    table.insert(items, fixes)

    local ryuu = { name = "Ryuu Generator session", kind = "ryuu", enabled = ryuu_session ~= "", url = "https://generator.ryuu.lol/api/check_session" }
    if ryuu_session == "" then
        ryuu.status = "warn"; ryuu.message = "No local Ryuu session configured"; ryuu.httpStatus = 0
    else
        local ok, resp = pcall(http_client.get, ryuu.url, { timeout = 10, headers = { ["Cookie"] = ryuu_session, ["User-Agent"] = "STLT-Rewired/source-health" } })
        ryuu.httpStatus = ok and resp and resp.status or 0
        if ryuu.httpStatus == 200 then ryuu.status = "ok"; ryuu.message = "Session accepted"
        elseif ryuu.httpStatus == 401 or ryuu.httpStatus == 403 then ryuu.status = "warn"; ryuu.message = "Session rejected"
        elseif ryuu.httpStatus > 0 then ryuu.status = "warn"; ryuu.message = "HTTP " .. tostring(ryuu.httpStatus)
        else ryuu.status = "error"; ryuu.message = "No response" end
    end
    counts[ryuu.status] = (counts[ryuu.status] or 0) + 1
    table.insert(items, ryuu)

    return {
        success = true,
        checkedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        counts = counts,
        sources = A(items),
    }
end

local function file_version(path)
    if not safe_file(path) then return "" end
    local ok, out = pcall(m_utils.exec, 'powershell.exe -NoProfile -Command "(Get-Item -LiteralPath ' .. string.format("'%s'", path:gsub("'", "''")) .. ').VersionInfo.FileVersion"')
    if ok and out then return st.trim(out) end
    return ""
end

function M.get_companion_status()
    local la = getenv("LOCALAPPDATA")
    local userprofile = getenv("USERPROFILE")
    local candidates = {
        join_nonempty(la, "LuaTools", "current", "LuaTools.exe"),
        "E:\\LuaTools-win-Portable\\LuaTools.exe",
        "E:\\LuaTools-win-Portable\\current\\LuaTools.exe",
        "F:\\Rewired-Manager\\RewiredManager.exe",
        "F:\\Rewired-Manager-Binaries\\RewiredManager.exe",
    }
    local found = {}
    for _, p in ipairs(candidates) do
        if p ~= "" and safe_file(p) then
            table.insert(found, { path = p, version = file_version(p) })
        end
    end

    local cloud_candidates = {
        join_nonempty(userprofile, "Downloads", "CloudRedirect.exe"),
        join_nonempty(userprofile, "Desktop", "CloudRedirect.exe"),
        "C:\\Program Files\\CloudRedirect\\CloudRedirect.exe",
        "C:\\Program Files (x86)\\CloudRedirect\\CloudRedirect.exe",
    }
    local cloud = {}
    for _, p in ipairs(cloud_candidates) do if p ~= "" and safe_file(p) then table.insert(cloud, p) end end

    local steam = steam_utils.detect_steam_install_path() or ""
    local live_plugin = steam ~= "" and fs.join(steam, "millennium", "plugins", "luatools") or ""

    return {
        success = true,
        officialLuaTools = A(found),
        officialLuaToolsDetected = #found > 0,
        cloudRedirect = A(cloud),
        cloudRedirectDetected = #cloud > 0,
        livePluginDir = live_plugin,
        livePluginPresent = live_plugin ~= "" and safe_exists(live_plugin),
        policy = "External CloudRedirect/Steamless/unlocker flows are explicit launch/guide only; STLT-Rewired does not silently patch them.",
    }
end

function M.open_path(path)
    path = tostring(path or "")
    if path == "" then return { success = false, error = "path required" } end
    if not safe_exists(path) then return { success = false, error = "path not found" } end
    local cmd = 'cmd.exe /C start "" "' .. path:gsub('"', '""') .. '"'
    local ok, err = pcall(m_utils.exec, cmd)
    return { success = ok == true, error = ok and nil or tostring(err) }
end

function M.get_cloudredirect_guide(appid)
    appid = tonumber(appid) or 0
    local status = M.get_companion_status()
    return {
        success = true,
        appid = appid,
        detected = status.cloudRedirectDetected,
        candidates = status.cloudRedirect,
        steps = A({
            "Close Steam before changing cloud-save/provider wiring.",
            "Back up userdata/<accountId>/<appid> and the game save folder first.",
            "Launch CloudRedirect explicitly; choose the game/appid and a provider folder such as OneDrive only if you want real cross-machine saves.",
            "Do not run SteamTools/STFixer/provider-login patches silently; verify the target game and account first.",
            "Restart Steam and check Steam/logs/cloud_log.txt for the exact appid before declaring the cloud issue fixed.",
        }),
        note = "For lua/added games, disabling Steam Cloud hides sync errors; CloudRedirect-style provider redirection is for real cloud saves.",
    }
end

local function append(lines, s) table.insert(lines, tostring(s or "")) end

local function summarize_settings()
    local out = {}
    local path = paths.backend_path("data/settings.json")
    local data = utils.read_json(path)
    local values = type(data.values) == "table" and data.values or {}
    for group, opts in pairs(values) do
        if type(opts) == "table" then
            local keys = {}
            for k, _ in pairs(opts) do
                local low = tostring(k):lower()
                if low:find("key", 1, true) or low:find("session", 1, true) or low:find("token", 1, true) or low:find("password", 1, true) then
                    table.insert(keys, tostring(k) .. "=<redacted/present>")
                else
                    table.insert(keys, tostring(k) .. "=" .. tostring(opts[k]))
                end
            end
            table.sort(keys)
            table.insert(out, tostring(group) .. ": " .. table.concat(keys, ", "))
        end
    end
    return out
end

local function tail_file(path, max_lines)
    if not safe_file(path) then return {} end
    local ok_read, text = pcall(m_utils.read_file, path)
    if not ok_read then return {} end
    text = text or ""
    text = redact_text(text)
    local lines = st.split_lines(text)
    local out = {}
    local start = math.max(1, #lines - (max_lines or 80) + 1)
    for i = start, #lines do table.insert(out, lines[i]) end
    return out
end

function M.export_support_bundle(appid)
    appid = tonumber(appid) or 0
    local lines = {}
    append(lines, "=== STLT-Rewired Redacted Support Bundle ===")
    append(lines, "Generated UTC: " .. os.date("!%Y-%m-%dT%H:%M:%SZ"))
    append(lines, "Plugin dir: " .. paths.get_plugin_dir())
    append(lines, "Plugin version: " .. utils.get_plugin_version())
    append(lines, "Steam path: " .. tostring(steam_utils.detect_steam_install_path() or ""))
    append(lines, "Steam running: " .. tostring(st.steam_is_running()))

    local okh, health = pcall(function() return require("health").get_millennium_health() end)
    append(lines, "")
    append(lines, "[Millennium]")
    if okh and health then
        append(lines, "version=" .. tostring(health.millenniumVersion) .. " target=" .. tostring(health.targetMillenniumVersion) .. " severity=" .. tostring(health.severity))
        append(lines, "hint=" .. tostring(health.hint))
    else
        append(lines, "health unavailable")
    end

    append(lines, "")
    append(lines, "[Settings shape — values redacted where sensitive]")
    for _, s in ipairs(summarize_settings()) do append(lines, s) end

    append(lines, "")
    append(lines, "[Source health]")
    local oks, sh = pcall(M.get_source_health)
    if oks and sh then
        append(lines, "counts ok=" .. tostring(sh.counts.ok or 0) .. " warn=" .. tostring(sh.counts.warn or 0) .. " error=" .. tostring(sh.counts.error or 0) .. " skipped=" .. tostring(sh.counts.skipped or 0))
        for _, src in ipairs(sh.sources or {}) do
            append(lines, "- " .. tostring(src.status) .. " " .. tostring(src.kind) .. " " .. tostring(src.name) .. " http=" .. tostring(src.httpStatus or 0) .. " :: " .. tostring(src.message or ""))
        end
    else
        append(lines, "source health unavailable")
    end

    local okc, comp = pcall(M.get_companion_status)
    append(lines, "")
    append(lines, "[Companion]")
    if okc and comp then
        append(lines, "officialLuaToolsDetected=" .. tostring(comp.officialLuaToolsDetected))
        for _, e in ipairs(comp.officialLuaTools or {}) do append(lines, "- " .. tostring(e.path) .. " version=" .. tostring(e.version or "")) end
        append(lines, "cloudRedirectDetected=" .. tostring(comp.cloudRedirectDetected))
        for _, p in ipairs(comp.cloudRedirect or {}) do append(lines, "- " .. tostring(p)) end
    end

    if appid > 0 then
        append(lines, "")
        append(lines, "[App diagnostic " .. appid .. "]")
        local okd, diag = pcall(function() return require("diagnostics").export_diagnostic_report(appid) end)
        if okd and diag and diag.text then append(lines, redact_text(diag.text)) else append(lines, "app diagnostic unavailable") end
    end

    append(lines, "")
    append(lines, "[Recent plugin log tail]")
    local log_path = paths.backend_path("debug.log")
    for _, l in ipairs(tail_file(log_path, 120)) do append(lines, l) end

    local dir = paths.backend_path("data/diagnostics")
    if not safe_exists(dir) then pcall(fs.create_directories, dir) end
    local out_path = fs.join(dir, "stlt-support-" .. st.stamp() .. (appid > 0 and ("-" .. appid) or "") .. ".txt")
    local body = table.concat(lines, "\n")
    local ok_write, write_err = pcall(m_utils.write_file, out_path, body)
    if not ok_write then
        return { success = false, error = "failed to write support bundle: " .. tostring(write_err) }
    end
    return { success = true, path = out_path, bytes = #body, redacted = true }
end

return M
