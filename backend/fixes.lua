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
    local resp = http_client.get(FIXES_INDEX_URL, { timeout = 10 })
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
    end
    
    return result
end

function fixes.apply_game_fix(appid, download_url, install_path, fix_type, game_name)
    local dest_root = utils.ensure_temp_download_dir()
    local dest_zip = fs.join(dest_root, "fix_" .. tostring(appid) .. ".zip")
    local state_file = fs.join(dest_root, "fix_" .. tostring(appid) .. "_state.json")
    
    logger.log("LuaTools: Applying fix to " .. tostring(install_path))
    m_utils.write_file(state_file, '{"status": "downloading"}')
    
    local is_windows = m_utils.getenv("OS") == "Windows_NT"
    if is_windows then
        local cmd = string.format(
            'cmd.exe /C start "LuaTools Downloader" cmd.exe /C "color 0B && echo LuaTools is downloading the requested files... && echo Please keep this window open until it closes automatically. && echo. && (echo {"status": "downloading"} > "%s" && curl.exe -# -L -A "discord(dot)gg/luatools" "%s" -o "%s" && echo {"status": "extracting"} > "%s" && echo. && echo Extracting files... && tar.exe -xf "%s" -C "%s" && echo {"status": "extracted"} > "%s") || (echo. && echo ERROR: Download or extraction failed! && echo {"status": "failed"} > "%s" && timeout /t 5)"',
            state_file, download_url, dest_zip, state_file, dest_zip, install_path, state_file, state_file
        )
        m_utils.exec(cmd)
    else
        local sh_path = fs.join(paths.get_plugin_dir(), "backend", "scripts", "downloader.sh")
        m_utils.exec('chmod +x "' .. sh_path .. '"')
        local cmd = string.format(
            'nohup bash "%s" "%s" "%s" "%s" "%s" > /dev/null 2>&1 &',
            sh_path, download_url, dest_zip, install_path, state_file
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
            elseif data.status == "failed" then
                pcall(fs.remove, state_file)
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

return fixes
