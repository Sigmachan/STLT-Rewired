-- crack_migrator.lua — detect + migrate cracked games onto LuaTools.
--
-- Faithful Lua port of crack_migrator.py. Scans every installed game for known
-- crack-file signatures, classifies by family + confidence, and (on confirm)
-- moves crack files to <game>/_luatools_migration_<ts>/ (reversible). Migration
-- is dry-run by default.

local m_utils     = require("utils")
local fs          = require("fs")
local logger      = require("plugin_logger")
local steam_utils = require("steam_utils")
local st          = require("st_util")

local M = {}

-- family name, signature filenames, score weight
local CRACK_FAMILIES = {
    { "Goldberg Emulator", { "steam_settings", "steam_interfaces.txt", "coldclientloader.ini",
        "ColdClientLoader.ini", "local_save.txt", "configs.user.ini" }, 30 },
    { "CODEX / CPY", { "codex.cfg", "codex64.dll", "codex.dll", "cpy.cfg", "cpy.ini" }, 30 },
    { "CreamAPI", { "cream_api.ini", "cream_api.dll", "cream_api64.dll" }, 30 },
    { "ALI213", { "ali213.ini", "ali213_api.dll", "ali213_api64.dll" }, 25 },
    { "UnSteam (3DM)", { "unsteam.dll", "unsteam.ini", "3dmgame.dll", "3dmgame.ini" }, 25 },
    { "RUNE / RELOADED", { "rune.dll", "rune.ini", "valve.ini", "hlm.ini" }, 20 },
    { "Generic Steam API loader", { "steamclient_loader.exe", "steam_api_o.dll", "steam_api64_o.dll",
        "steam_api.dll.bak", "steam_api64.dll.bak" }, 15 },
    { "DLL Proxy Hijack", { "winmm.dll", "xinput1_3.dll", "xinput1_4.dll", "xinput9_1_0.dll",
        "dinput8.dll", "winhttp.dll", "iphlpapi.dll", "dsound.dll" }, 10 },
}

-- lowercase filename -> family (later families win on duplicate, matching Python)
local FILE_TO_FAMILY = {}
for _, fam in ipairs(CRACK_FAMILIES) do
    for _, fn in ipairs(fam[2]) do FILE_TO_FAMILY[fn:lower()] = fam[1] end
end

local function weight_of(family)
    for _, fam in ipairs(CRACK_FAMILIES) do if fam[1] == family then return fam[3] end end
    return 0
end

local function relpath(path, root)
    local r = root:gsub("[/\\]+$", "")
    local p = path
    if p:sub(1, #r):lower() == r:lower() then p = p:sub(#r + 1) end
    return (p:gsub("^[/\\]+", ""))
end

-- ── installed-game enumeration ───────────────────────────────────────────────

local function parse_acf_install(acf_path)
    local text = m_utils.read_file(acf_path)
    if not text then return nil end
    local install_dir = text:match('"installdir"%s+"([^"]*)"')
    if not install_dir then return nil end
    return { name = text:match('"name"%s+"([^"]*)"') or "", installdir = install_dir }
end

local function all_installed_games()
    local base = steam_utils.detect_steam_install_path()
    if not base or base == "" then return {} end
    local libraries = { base }
    local lf = fs.join(base, "config", "libraryfolders.vdf")
    if fs.is_file(lf) then
        local text = m_utils.read_file(lf) or ""
        for p in text:gmatch('"path"%s+"([^"]+)"') do
            local pp = p:gsub('\\\\', '\\')
            if fs.is_directory(pp) then
                local dup = false
                for _, l in ipairs(libraries) do if l == pp then dup = true break end end
                if not dup then table.insert(libraries, pp) end
            end
        end
    end

    local games, seen = {}, {}
    for _, lib in ipairs(libraries) do
        local steamapps = fs.join(lib, "steamapps")
        if fs.is_directory(steamapps) then
            for _, e in ipairs(fs.list(steamapps) or {}) do
                local aid = (e.name or ""):match("^appmanifest_(%d+)%.acf$")
                if aid then
                    aid = tonumber(aid)
                    if not seen[aid] then
                        seen[aid] = true
                        local info = parse_acf_install(e.path)
                        if info then
                            local install_path = fs.join(steamapps, "common", info.installdir)
                            table.insert(games, {
                                appid = aid,
                                name = (info.name ~= "" and info.name) or info.installdir,
                                installPath = install_path,
                                libraryPath = lib,
                                installed = fs.is_directory(install_path),
                            })
                        end
                    end
                end
            end
        end
    end
    table.sort(games, function(a, b) return a.name:lower() < b.name:lower() end)
    return games
end

-- ── per-game scan (bounded-depth manual recursion) ───────────────────────────

local function scan_game_dir(install_path, max_depth)
    max_depth = max_depth or 4
    local found = {}
    if not install_path or install_path == "" or not fs.is_directory(install_path) then return found end
    local function add(family, rel) found[family] = found[family] or {}; table.insert(found[family], rel) end
    local function recurse(dir, depth)
        if depth > max_depth then return end
        local entries = fs.list(dir)
        if not entries then return end
        for _, e in ipairs(entries) do
            local family = FILE_TO_FAMILY[(e.name or ""):lower()]
            if e.is_directory then
                if family then add(family, relpath(e.path, install_path) .. "/") end
                recurse(e.path, depth + 1)
            elseif e.is_file then
                if family then add(family, relpath(e.path, install_path)) end
            end
        end
    end
    recurse(install_path, 0)
    return found
end

local function classify(found)
    if not next(found) then
        return { clean = true, topFamily = st.null, confidence = 0, families = st.A({}) }
    end
    local scored = {}
    for _, fam in ipairs(CRACK_FAMILIES) do
        local matched = found[fam[1]]
        if matched then
            table.insert(scored, { family = fam[1], score = fam[3] + #matched * 2, files = st.A(matched) })
        end
    end
    table.sort(scored, function(a, b) return a.score > b.score end)
    local top = scored[1]
    return {
        clean = false,
        topFamily = top and top.family or st.null,
        confidence = top and top.score or 0,
        families = st.A(scored),
    }
end

-- ── IPC ──────────────────────────────────────────────────────────────────────

function M.scan_all_games()
    local games = all_installed_games()
    if #games == 0 then return { success = false, error = "No installed games found" } end

    local stplug = st.lua_script_dir()
    local lua_appids = {}
    if stplug ~= "" and fs.is_directory(stplug) then
        for _, e in ipairs(fs.list(stplug) or {}) do
            local aid = (e.name or ""):match("^(%d+)%.lua")
            if aid then lua_appids[tonumber(aid)] = true end
        end
    end

    local results, cracked, clean = {}, 0, 0
    for _, game in ipairs(games) do
        if game.installed then
            local found = scan_game_dir(game.installPath)
            local cls = classify(found)
            local fcount = 0
            for _, v in pairs(found) do fcount = fcount + #v end
            local entry = {
                appid = game.appid, name = game.name, installPath = game.installPath,
                libraryPath = game.libraryPath, installed = game.installed,
                clean = cls.clean, topFamily = cls.topFamily,
                confidence = cls.confidence, families = cls.families,
                hasLuaTools = lua_appids[game.appid] == true,
                fileCount = fcount,
            }
            if cls.clean then clean = clean + 1 else cracked = cracked + 1 end
            table.insert(results, entry)
        end
    end

    return {
        success = true, totalGames = #results,
        crackedGames = cracked, cleanGames = clean, results = st.A(results),
    }
end

function M.migrate_game(appid, dry_run)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "invalid appid" } end
    if dry_run == nil then dry_run = true end

    local game = nil
    for _, g in ipairs(all_installed_games()) do if g.appid == appid then game = g; break end end
    if not game then return { success = false, error = "game " .. appid .. " not installed" } end
    if not game.installed then return { success = false, error = "install dir missing" } end

    local install_path = game.installPath
    local found = scan_game_dir(install_path)
    local cls = classify(found)
    if cls.clean then
        return { success = true, appid = appid, name = game.name, clean = true,
                 message = "No crack files detected -- nothing to migrate." }
    end

    local timestamp = st.stamp()
    local backup_dir = fs.join(install_path, "_luatools_migration_" .. timestamp)

    local plan = {}
    for family, paths in pairs(found) do
        for _, rel in ipairs(paths) do
            local bare = rel:gsub("/$", "")
            local src = fs.join(install_path, bare)
            table.insert(plan, {
                family = family, path = rel, src = src,
                dst = fs.join(backup_dir, bare),
                isDir = rel:sub(-1) == "/", exists = fs.exists(src),
            })
        end
    end

    if dry_run then
        return {
            success = true, dryRun = true, appid = appid, name = game.name,
            topFamily = cls.topFamily, confidence = cls.confidence,
            backupDir = backup_dir, plan = st.A(plan), filesToMove = #plan,
        }
    end

    pcall(fs.create_directories, backup_dir)
    if not fs.is_directory(backup_dir) then
        return { success = false, error = "cannot create backup dir" }
    end

    local moved, errors = {}, {}
    for _, item in ipairs(plan) do
        if item.exists then
            local parent = fs.parent_path(item.dst)
            pcall(fs.create_directories, parent)
            local ok = fs.rename(item.src, item.dst)
            if ok then
                table.insert(moved, { family = item.family, path = item.path })
            else
                table.insert(errors, item.path .. ": move failed")
            end
        end
    end

    logger.log("crack_migrator: " .. appid .. " (" .. game.name .. ") moved " ..
        #moved .. " item(s) to " .. backup_dir .. ", " .. #errors .. " error(s)")

    return {
        success = true, dryRun = false, appid = appid, name = game.name,
        topFamily = cls.topFamily, backupDir = backup_dir,
        movedCount = #moved, moved = st.A(moved), errors = st.A(errors),
        nextStep = "Crack files moved to backup. Now call StartAddViaLuaTools with appid=" ..
            appid .. " to install LuaTools activation. If anything breaks, the original files " ..
            "are at the backup path -- move them back.",
    }
end

function M.undo_migration(appid, backup_dir)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "invalid appid" } end

    local game = nil
    for _, g in ipairs(all_installed_games()) do if g.appid == appid then game = g; break end end
    if not game then return { success = false, error = "game " .. appid .. " not installed" } end
    local install_path = game.installPath

    if not backup_dir or backup_dir == "" then
        local candidates = {}
        for _, e in ipairs(fs.list(install_path) or {}) do
            if e.is_directory and (e.name or ""):find("^_luatools_migration_") then
                table.insert(candidates, { path = e.path, mtime = fs.last_write_time(e.path) or 0 })
            end
        end
        if #candidates == 0 then
            return { success = false, error = "No migration backup found for this game" }
        end
        table.sort(candidates, function(a, b) return a.mtime > b.mtime end)
        backup_dir = candidates[1].path
    end

    if not fs.is_directory(backup_dir) then
        return { success = false, error = "backup dir not found: " .. tostring(backup_dir) }
    end

    local restored, errors = {}, {}
    for _, e in ipairs(fs.list_recursive(backup_dir) or {}) do
        if e.is_file then
            local rel = relpath(e.path, backup_dir)
            local dst = fs.join(install_path, rel)
            pcall(fs.create_directories, fs.parent_path(dst))
            local ok = fs.rename(e.path, dst)
            if ok then table.insert(restored, rel) else table.insert(errors, rel .. ": restore failed") end
        end
    end
    pcall(fs.remove_all, backup_dir)

    logger.log("crack_migrator: undo " .. appid .. " restored " .. #restored .. " item(s)")
    return { success = true, appid = appid, restoredCount = #restored, errors = st.A(errors) }
end

function M.list_migrations()
    local out = {}
    for _, game in ipairs(all_installed_games()) do
        if game.installed then
            for _, e in ipairs(fs.list(game.installPath) or {}) do
                if e.is_directory and (e.name or ""):find("^_luatools_migration_") then
                    local file_count, size_bytes = 0, 0
                    for _, fe in ipairs(fs.list_recursive(e.path) or {}) do
                        if fe.is_file then
                            file_count = file_count + 1
                            size_bytes = size_bytes + (fs.file_size(fe.path) or 0)
                        end
                    end
                    table.insert(out, {
                        appid = game.appid, name = game.name, backupDir = e.path,
                        timestamp = (e.name or ""):gsub("^_luatools_migration_", ""),
                        fileCount = file_count, sizeMB = st.round(size_bytes / 1024 / 1024, 2),
                    })
                end
            end
        end
    end
    return { success = true, migrations = st.A(out) }
end

return M
