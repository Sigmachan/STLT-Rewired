local m_utils = require("utils")
local fs = require("fs")
local http_client = require("http_client")
local logger = require("plugin_logger")
local utils = require("plugin_utils")
local paths = require("paths")
local cjson = require("json")
local steam_utils = require("steam_utils")
local st = require("st_util")

local fixes = {}

local function ps_quote(value)
    return "'" .. tostring(value or ""):gsub("'", "''") .. "'"
end

local function write_windows_fix_script(script_path, state_file, download_url, dest_zip, install_path, appid, fix_type, game_name)
    local log_path = fs.join(install_path, "luatools-fix-log-" .. tostring(appid) .. ".log")
    local content = table.concat({
        "$ErrorActionPreference = 'Stop'",
        "$ProgressPreference = 'Continue'",
        "$stateFile = " .. ps_quote(state_file),
        "$url = " .. ps_quote(download_url),
        "$zip = " .. ps_quote(dest_zip),
        "$install = " .. ps_quote(install_path),
        "$log = " .. ps_quote(log_path),
        "$fixType = " .. ps_quote(fix_type),
        "$gameName = " .. ps_quote(game_name),
        "$appid = " .. ps_quote(appid),
        "$tarExe = Join-Path $env:WINDIR 'System32\\tar.exe'",
        "$curlExe = Join-Path $env:WINDIR 'System32\\curl.exe'",
        "if (-not (Test-Path -LiteralPath $tarExe)) { $tarExe = 'tar.exe' }",
        "if (-not (Test-Path -LiteralPath $curlExe)) { $curlExe = 'curl.exe' }",
        "function Test-SafeArchiveEntry([string]$entry) {",
        "  if ([string]::IsNullOrWhiteSpace($entry)) { return $false }",
        "  $normalized = $entry.Replace('\\', '/')",
        "  if ($normalized.StartsWith('/') -or $normalized.StartsWith('\\')) { return $false }",
        "  if ($normalized -match '^[A-Za-z]:') { return $false }",
        "  if ($normalized.Contains(':')) { return $false }",
        "  foreach ($part in $normalized.Split('/')) {",
        "    if ($part -eq '..') { return $false }",
        "  }",
        "  return $true",
        "}",
        "function Write-State([string]$status, [string]$errorMessage = '') {",
        "  $obj = @{ status = $status }",
        "  if ($errorMessage -ne '') { $obj.error = $errorMessage }",
        "  $obj | ConvertTo-Json -Compress | Set-Content -LiteralPath $stateFile -Encoding ASCII",
        "}",
        "try {",
        "  Write-State 'downloading'",
        "  & $curlExe -L -A 'discord(dot)gg/luatools' $url -o $zip",
        "  if ($LASTEXITCODE -ne 0) { throw \"curl.exe failed with exit code $LASTEXITCODE\" }",
        "  if (-not (Test-Path -LiteralPath $zip)) { throw 'Downloaded archive was not created' }",
        "  Write-State 'extracting'",
        "  $entries = @(& $tarExe -tf $zip 2>$null | Where-Object { $_ -and -not $_.EndsWith('/') } | ForEach-Object { $_.Replace('\\', '/') })",
        "  foreach ($entry in $entries) { if (-not (Test-SafeArchiveEntry $entry)) { throw ('Unsafe archive entry: ' + $entry) } }",
        "  & $tarExe -xf $zip -C $install",
        "  if ($LASTEXITCODE -ne 0) { throw \"tar.exe failed with exit code $LASTEXITCODE\" }",
        "  $stamp = (Get-Date).ToString('o')",
        "  $lines = New-Object System.Collections.Generic.List[string]",
        "  $lines.Add('[FIX]')",
        "  $lines.Add('Date: ' + $stamp)",
        "  $lines.Add('Game: ' + $gameName)",
        "  $lines.Add('Fix Type: ' + $fixType)",
        "  $lines.Add('Download URL: ' + $url)",
        "  $lines.Add('Files:')",
        "  foreach ($entry in $entries) { $lines.Add($entry) }",
        "  $lines.Add('[/FIX]')",
        "  Add-Content -LiteralPath $log -Value ($lines -join [Environment]::NewLine) -Encoding UTF8",
        "  Write-State 'extracted'",
        "}",
        "catch {",
        "  Write-State 'failed' ($_.Exception.Message)",
        "  Write-Host ('ERROR: ' + $_.Exception.Message)",
        "  Start-Sleep -Seconds 5",
        "  exit 1",
        "}",
    }, "\n")
    m_utils.write_file(script_path, content)
end

local function add_ryuu_fixes(result, appid)
    local headers = { ["User-Agent"] = "STLT-Rewired" }
    pcall(function()
        local sess = require("settings.manager").get_ryuu_session() or ""
        if sess ~= "" then headers["Cookie"] = sess end
    end)

    local ok, resp = pcall(http_client.get, "https://generator.ryuu.lol/fixes", { headers = headers, timeout = 12 })
    if not ok or not resp or resp.status ~= 200 or not resp.body then return end

    local appid_s = tostring(appid)
    local marker = 'data%-appid="' .. appid_s .. '" data%-name="'
    local block_start = resp.body:find(marker)
    if not block_start then return end
    local block_end = resp.body:find('<div class="game%-card"', block_start + 1) or (#resp.body + 1)
    local block = resp.body:sub(block_start, block_end - 1)

    for href, name in block:gmatch('<a%s+href="([^"]+)"%s+class="fix%-item%-click">.-<div class="fix%-name">%s*([^<]-)%s*</div>') do
        local url = href:gsub(" ", "%%20")
        local lower_name = name:lower()
        local is_online = block:find('data%-badge%-key="online"', 1, false) ~= nil or lower_name:find("online", 1, true) ~= nil
        local target = is_online and result.onlineFix or result.genericFix
        target.status = 200
        target.available = true
        target.url = url
        target.source = "Ryuu Premium"
        target.name = name
        break
    end
end

function fixes.check_for_fixes(appid)
    if type(appid) == "string" then appid = tonumber(appid) end
    local result = {
        success = true,
        appid = appid,
        gameName = "Unknown Game (" .. tostring(appid) .. ")",
        genericFix = { status = 0, available = false },
        onlineFix = { status = 0, available = false }
    }
    
    local FIXES_INDEX_URL = "https://index.luatools.work/fixes-index.json"
    local ok_http, resp = pcall(http_client.get, FIXES_INDEX_URL, { timeout = 10 })
    if not ok_http then
        logger.warn("LuaTools: fixes index request failed: " .. tostring(resp))
        result.error = "Failed to fetch fixes index"
        return result
    end
    if resp and resp.status == 200 and resp.body then
        local data = utils.decode_json(resp.body)
        if type(data) == "table" then
            local generic_url = "https://files.luatools.work/GameBypasses/" .. tostring(appid) .. ".zip"
            local online_url = "https://files.luatools.work/OnlineFix1/" .. tostring(appid) .. ".zip"
            
            local has_generic = false
            for _, v in ipairs(data.genericFixes or {}) do if tonumber(v) == appid then has_generic = true break end end
            if has_generic then
                result.genericFix.status = 200
                result.genericFix.available = true
                result.genericFix.url = generic_url
            else
                result.genericFix.status = 404
            end
            
            local has_online = false
            for _, v in ipairs(data.onlineFixes or {}) do if tonumber(v) == appid then has_online = true break end end
            if has_online then
                result.onlineFix.status = 200
                result.onlineFix.available = true
                result.onlineFix.url = online_url
            else
                result.onlineFix.status = 404
            end
        end
    elseif resp and resp.status == 429 then
        result.rateLimited = true
        result.error = "Fixes index rate limited"
    elseif resp and resp.status then
        logger.warn("LuaTools: fixes index returned HTTP " .. tostring(resp.status))
        result.error = "Fixes index HTTP " .. tostring(resp.status)
    else
        result.error = "Fixes index unavailable"
    end
    pcall(add_ryuu_fixes, result, appid)
    
    return result
end

function fixes.apply_game_fix(appid, download_url, install_path, fix_type, game_name)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "Invalid appid" } end
    if not download_url or download_url == "" then return { success = false, error = "Invalid fix download URL" } end
    if not install_path or install_path == "" or not fs.is_directory(install_path) then
        return { success = false, error = "Game install path not found" }
    end

    local dest_root = utils.ensure_temp_download_dir()
    local dest_zip = fs.join(dest_root, "fix_" .. tostring(appid) .. ".zip")
    local state_file = fs.join(dest_root, "fix_" .. tostring(appid) .. "_state.json")
    local script_file = fs.join(dest_root, "fix_" .. tostring(appid) .. "_apply.ps1")
    
    logger.log("LuaTools: Applying fix to " .. tostring(install_path))
    pcall(fs.remove, dest_zip)
    pcall(fs.remove, script_file)
    m_utils.write_file(state_file, '{"status": "downloading"}')
    
    local platform = require("platform")
    local is_windows = platform.is_windows()
    if is_windows then
        write_windows_fix_script(script_file, state_file, download_url, dest_zip, install_path, appid, fix_type, game_name)
        local cmd = string.format(
            'cmd.exe /C start "LuaTools Fix Downloader" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%s"',
            script_file
        )
        m_utils.exec(cmd)
    else
        local sh_path = fs.join(paths.get_plugin_dir(), "backend", "scripts", "downloader.sh")
        m_utils.exec('chmod +x "' .. sh_path .. '"')
        local cmd = string.format(
            'nohup bash %s %s %s %s %s > /dev/null 2>&1 &',
            platform.shell_quote(sh_path),
            platform.shell_quote(download_url),
            platform.shell_quote(dest_zip),
            platform.shell_quote(install_path),
            platform.shell_quote(state_file)
        )
        m_utils.exec(cmd)
    end
    
    return { success = true }
end

function fixes.get_apply_status(appid)
    local dest_root = utils.ensure_temp_download_dir()
    local state_file = fs.join(dest_root, "fix_" .. tostring(appid) .. "_state.json")
    local dest_zip = fs.join(dest_root, "fix_" .. tostring(appid) .. ".zip")
    
    if not fs.exists(state_file) then
        return { success = true, state = { status = "done" } }
    end
    
    local content = m_utils.read_file(state_file)
    if content and content ~= "" then
        local success, data = pcall(cjson.decode, content)
        if success and type(data) == "table" and data.status then
            if data.status == "extracted" then
                data.status = "done"
                pcall(fs.remove, state_file)
                pcall(fs.remove, dest_zip)
                pcall(fs.remove, fs.join(dest_root, "fix_" .. tostring(appid) .. "_apply.ps1"))
            elseif data.status == "failed" then
                pcall(fs.remove, state_file)
                pcall(fs.remove, dest_zip)
                pcall(fs.remove, fs.join(dest_root, "fix_" .. tostring(appid) .. "_apply.ps1"))
            end
            return { success = true, state = data }
        end
    end
    
    return { success = true, state = { status = "downloading" } }
end

-- ── Un-fix / installed-fix scanning (luatools-fix-log-<appid>.log) ────────────
-- Faithful port of fixes.py get_installed_fixes / unfix_game. The log records
-- each applied fix as a [FIX] block: Date/Game/Fix Type/Download URL + a Files:
-- list (paths relative to the game install dir).

local UNFIX_STATE = {}

local function set_unfix_state(appid, update)
    local s = UNFIX_STATE[appid] or {}
    for k, v in pairs(update) do s[k] = v end
    UNFIX_STATE[appid] = s
end

-- Split a string on a literal separator.
local function split_str(s, sep)
    local out, start = {}, 1
    while true do
        local a, b = s:find(sep, start, true)
        if not a then table.insert(out, s:sub(start)); break end
        table.insert(out, s:sub(start, a - 1))
        start = b + 1
    end
    return out
end

-- Parse a single fix block into a fix_data table.
local function parse_fix_block(block, appid, game_name, install_path)
    local fd = {
        appid = appid, gameName = game_name, installPath = install_path,
        date = "", fixType = "", downloadUrl = "", filesCount = 0, files = {},
    }
    local in_files = false
    for _, line in ipairs(st.split_lines(block)) do
        local ls = st.trim(line)
        if ls == "[/FIX]" or ls == "---" then break end
        if ls:sub(1, 5) == "Date:" then
            fd.date = st.trim(ls:sub(6))
        elseif ls:sub(1, 5) == "Game:" then
            local g = st.trim(ls:sub(6))
            if g ~= "" and g ~= ("Unknown Game (" .. tostring(appid) .. ")") then fd.gameName = g end
        elseif ls:sub(1, 9) == "Fix Type:" then
            fd.fixType = st.trim(ls:sub(10))
        elseif ls:sub(1, 13) == "Download URL:" then
            fd.downloadUrl = st.trim(ls:sub(14))
        elseif ls == "Files:" then
            in_files = true
        elseif in_files and ls ~= "" then
            table.insert(fd.files, ls)
        end
    end
    fd.filesCount = #fd.files
    fd.files = st.A(fd.files)
    return fd
end

local function parse_installed_fixes(log_content, appid, game_name, install_path)
    local out = {}
    if log_content:find("[FIX]", 1, true) then
        for _, block in ipairs(split_str(log_content, "[FIX]")) do
            if st.trim(block) ~= "" then
                local fd = parse_fix_block(block, appid, game_name, install_path)
                if fd.date ~= "" then table.insert(out, fd) end
            end
        end
    else
        local fd = parse_fix_block(log_content, appid, game_name, install_path)
        if fd.date ~= "" then table.insert(out, fd) end
    end
    return out
end

-- Collect files to delete + fix blocks to keep (when removing one dated fix).
local function collect_unfix(log_content, fix_date)
    local files_set, files, remaining = {}, {}, {}
    local function add_file(f)
        if not files_set[f] then files_set[f] = true; table.insert(files, f) end
    end
    if log_content:find("[FIX]", 1, true) then
        for _, block in ipairs(split_str(log_content, "[FIX]")) do
            if st.trim(block) ~= "" then
                local in_files, block_date, block_lines = false, nil, {}
                for _, line in ipairs(st.split_lines(block)) do
                    local ls = st.trim(line)
                    if ls == "[/FIX]" or ls == "---" then break end
                    if ls:sub(1, 5) == "Date:" then block_date = st.trim(ls:sub(6)) end
                    table.insert(block_lines, line)
                    if ls == "Files:" then
                        in_files = true
                    elseif in_files and ls ~= "" then
                        if fix_date == nil or (block_date and block_date == fix_date) then add_file(ls) end
                    end
                end
                if fix_date ~= nil and block_date and block_date ~= fix_date then
                    table.insert(remaining, "[FIX]\n" .. table.concat(block_lines, "\n") .. "\n[/FIX]")
                end
            end
        end
    else
        local in_files = false
        for _, line in ipairs(st.split_lines(log_content)) do
            local ls = st.trim(line)
            if ls == "Files:" then in_files = true
            elseif in_files and ls ~= "" then add_file(ls) end
        end
    end
    return files, remaining
end

function fixes.unfix_game(appid, install_path, fix_date)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "Invalid appid" } end

    local resolved = install_path
    if not resolved or resolved == "" then
        local r = steam_utils.get_game_install_path_response(appid)
        if not r.success or not r.installPath then
            return { success = false, error = "Could not find game install path" }
        end
        resolved = r.installPath
    end
    if not fs.exists(resolved) then return { success = false, error = "Install path does not exist" } end

    local log_path = fs.join(resolved, "luatools-fix-log-" .. appid .. ".log")
    if not fs.is_file(log_path) then
        set_unfix_state(appid, { status = "failed", error = "No fix log found. Cannot un-fix." })
        return { success = false, error = "No fix log found. Cannot un-fix." }
    end

    local content = m_utils.read_file(log_path) or ""
    local fd = (fix_date ~= nil and fix_date ~= "") and fix_date or nil
    local files, remaining = collect_unfix(content, fd)

    local deleted = 0
    for _, rel in ipairs(files) do
        local full = fs.join(resolved, rel)
        if fs.exists(full) and pcall(fs.remove, full) then deleted = deleted + 1 end
    end

    if #remaining > 0 then
        m_utils.write_file(log_path, table.concat(remaining, "\n\n---\n\n"))
    else
        pcall(fs.remove, log_path)
    end

    set_unfix_state(appid, { status = "done", success = true, filesRemoved = deleted })
    return { success = true }
end

function fixes.get_unfix_status(appid)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "Invalid appid" } end
    return { success = true, state = UNFIX_STATE[appid] or { status = "done" } }
end

function fixes.get_installed_fixes()
    local base = steam_utils.detect_steam_install_path()
    if not base or base == "" then
        return { success = false, error = "Could not find Steam installation path" }
    end
    local lib_vdf = fs.join(base, "config", "libraryfolders.vdf")
    if not fs.is_file(lib_vdf) then
        return { success = false, error = "Could not find libraryfolders.vdf" }
    end
    local vdf = m_utils.read_file(lib_vdf) or ""
    local lib_paths = {}
    for p in vdf:gmatch('"path"%s+"([^"]+)"') do
        table.insert(lib_paths, (p:gsub('\\\\', '\\')))
    end

    local installed = {}
    for _, lib in ipairs(lib_paths) do
        local sa = fs.join(lib, "steamapps")
        if fs.is_directory(sa) then
            for _, e in ipairs(fs.list(sa) or {}) do
                local n = e.name or ""
                if n:match("^appmanifest_") and n:match("%.acf$") then
                    local aid = tonumber(n:match("appmanifest_(%d+)%.acf"))
                    if aid then
                        local mc = m_utils.read_file(e.path)
                        if mc then
                            local install_dir = mc:match('"installdir"%s+"([^"]+)"')
                            local game_name = mc:match('"name"%s+"([^"]+)"') or ("Unknown Game (" .. aid .. ")")
                            if install_dir then
                                local full = fs.join(lib, "steamapps", "common", install_dir)
                                if fs.is_directory(full) then
                                    local log_path = fs.join(full, "luatools-fix-log-" .. aid .. ".log")
                                    if fs.is_file(log_path) then
                                        local lc = m_utils.read_file(log_path) or ""
                                        for _, fx in ipairs(parse_installed_fixes(lc, aid, game_name, full)) do
                                            table.insert(installed, fx)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return { success = true, fixes = st.A(installed) }
end

local FIXES_INDEX_URL = "https://index.luatools.work/fixes-index.json"
local FIXES_INDEX_CACHE = nil
local FIXES_INDEX_CACHE_AT = 0
local FIXES_INDEX_TTL_SEC = 3600

local function fixes_index_now()
    if m_utils.time then return m_utils.time() end
    return os.time()
end

local function appid_lookup(list)
    local out = {}
    for _, v in ipairs(list or {}) do
        local n = tonumber(v)
        if n and n > 0 then out[n] = true end
    end
    return out
end

--- Cached LuaTools fixes index (generic + online AppID sets).
function fixes.get_fixes_index()
    local now = fixes_index_now()
    if FIXES_INDEX_CACHE and (now - FIXES_INDEX_CACHE_AT) < FIXES_INDEX_TTL_SEC then
        return FIXES_INDEX_CACHE
    end

    local payload = {
        success = false,
        generic = {},
        online = {},
        rateLimited = false,
        error = nil,
        fetchedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }

    local ok_http, resp = pcall(http_client.get, FIXES_INDEX_URL, { timeout = 12 })
    if not ok_http then
        payload.error = "Failed to fetch fixes index"
        FIXES_INDEX_CACHE = payload
        FIXES_INDEX_CACHE_AT = now
        return payload
    end
    if resp and resp.status == 429 then
        payload.rateLimited = true
        payload.error = "Fixes index rate limited"
        FIXES_INDEX_CACHE = payload
        FIXES_INDEX_CACHE_AT = now
        return payload
    end
    if not resp or resp.status ~= 200 or not resp.body then
        payload.error = resp and ("Fixes index HTTP " .. tostring(resp.status)) or "Fixes index unavailable"
        FIXES_INDEX_CACHE = payload
        FIXES_INDEX_CACHE_AT = now
        return payload
    end

    local data = utils.decode_json(resp.body)
    if type(data) ~= "table" then
        payload.error = "Invalid fixes index JSON"
        FIXES_INDEX_CACHE = payload
        FIXES_INDEX_CACHE_AT = now
        return payload
    end

    payload.success = true
    payload.generic = appid_lookup(data.genericFixes or {})
    payload.online = appid_lookup(data.onlineFixes or {})
    FIXES_INDEX_CACHE = payload
    FIXES_INDEX_CACHE_AT = now
    return payload
end

local function collect_steam_library_games()
    local games = {}
    local seen = {}

    local function add_game(aid, game_name, install_path, library_path)
        aid = tonumber(aid)
        if not aid or seen[aid] then return end
        seen[aid] = true
        table.insert(games, {
            appid = aid,
            gameName = game_name or ("Unknown Game (" .. aid .. ")"),
            installPath = install_path or "",
            libraryPath = library_path or "",
            source = "steam",
        })
    end

    local base = steam_utils.detect_steam_install_path()
    if not base or base == "" then
        return games, "Could not find Steam installation path"
    end

    local lib_paths = { base }
    local lib_vdf = fs.join(base, "config", "libraryfolders.vdf")
    if fs.is_file(lib_vdf) then
        local vdf = m_utils.read_file(lib_vdf) or ""
        for p in vdf:gmatch('"path"%s+"([^"]+)"') do
            local norm = (p:gsub('\\\\', '\\'))
            local found = false
            for _, existing in ipairs(lib_paths) do
                if existing:lower() == norm:lower() then found = true break end
            end
            if not found and norm ~= "" then table.insert(lib_paths, norm) end
        end
    end

    for _, lib in ipairs(lib_paths) do
        local sa = fs.join(lib, "steamapps")
        if fs.is_directory(sa) then
            for _, e in ipairs(fs.list(sa) or {}) do
                local n = e.name or ""
                if n:match("^appmanifest_") and n:match("%.acf$") then
                    local aid = tonumber(n:match("appmanifest_(%d+)%.acf"))
                    if aid then
                        local mc = m_utils.read_file(e.path)
                        if mc then
                            local install_dir = mc:match('"installdir"%s+"([^"]+)"')
                            local game_name = mc:match('"name"%s+"([^"]+)"') or ("Unknown Game (" .. aid .. ")")
                            local full = install_dir and fs.join(lib, "steamapps", "common", install_dir) or ""
                            if install_dir and fs.is_directory(full) then
                                add_game(aid, game_name, full, lib)
                            else
                                add_game(aid, game_name, "", lib)
                            end
                        end
                    end
                end
            end
        end
    end

    return games, nil
end

local function collect_lua_script_games()
    local games = {}
    local ok_paths, unlock_paths = pcall(require, "unlock_paths")
    if not ok_paths or not unlock_paths then return games end
    local dir = unlock_paths.lua_script_dir()
    if not dir or dir == "" or not fs.is_directory(dir) then return games end
    for _, e in ipairs(fs.list(dir) or {}) do
        local name = e.name or ""
        local aid = name:match("^(%d+)%.lua") or name:match("^(%d+)%.luda") or name:match("^(%d+)%.lua%.disabled$")
        if aid then
            table.insert(games, {
                appid = tonumber(aid),
                gameName = "Unknown Game (" .. aid .. ")",
                installPath = "",
                libraryPath = "",
                source = "lua",
            })
        end
    end
    return games
end

--- SWA-style bulk match: installed Steam library (+ lua scripts) ↔ LuaTools fixes index.
function fixes.match_available_fixes_for_library()
    local index = fixes.get_fixes_index()
    if not index.success then
        return {
            success = false,
            error = index.error or "Fixes index unavailable",
            rateLimited = index.rateLimited == true,
            matches = st.A({}),
        }
    end

    local steam_games, steam_err = collect_steam_library_games()
    local lua_games = collect_lua_script_games()
    local by_appid = {}

    for _, g in ipairs(steam_games) do
        by_appid[g.appid] = g
    end
    for _, g in ipairs(lua_games) do
        if not by_appid[g.appid] then
            by_appid[g.appid] = g
        else
            by_appid[g.appid].hasLuaScript = true
        end
    end

    local matches = {}
    local scanned = 0
    for appid, game in pairs(by_appid) do
        scanned = scanned + 1
        local has_generic = index.generic[appid] == true
        local has_online = index.online[appid] == true
        if has_generic or has_online then
            local entry = {
                appid = appid,
                gameName = game.gameName,
                installPath = game.installPath or "",
                source = game.source or "steam",
                hasLuaScript = game.hasLuaScript == true or game.source == "lua",
                genericAvailable = has_generic,
                onlineAvailable = has_online,
                genericUrl = has_generic and ("https://files.luatools.work/GameBypasses/" .. appid .. ".zip") or "",
                onlineUrl = has_online and ("https://files.luatools.work/OnlineFix1/" .. appid .. ".zip") or "",
            }
            if entry.installPath ~= "" then
                local log_path = fs.join(entry.installPath, "luatools-fix-log-" .. appid .. ".log")
                entry.hasAppliedFix = fs.is_file(log_path)
            else
                entry.hasAppliedFix = false
            end
            table.insert(matches, entry)
        end
    end

    table.sort(matches, function(a, b)
        return tostring(a.gameName):lower() < tostring(b.gameName):lower()
    end)

    local cap = 200
    local truncated = #matches > cap
    if truncated then
        local trimmed = {}
        for i = 1, cap do trimmed[i] = matches[i] end
        matches = trimmed
    end

    logger.log("match_available_fixes_for_library: scanned=" .. scanned .. " matches=" .. tostring(#matches))
    return {
        success = true,
        scannedGames = scanned,
        matchCount = #matches,
        truncated = truncated,
        rateLimited = false,
        steamError = steam_err,
        matches = st.A(matches),
        indexFetchedAt = index.fetchedAt,
    }
end

return fixes
