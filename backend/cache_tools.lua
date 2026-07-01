-- cache_tools.lua — Smart cache clean, folder stats, quick dashboard, Steam
-- process info, and library scanner.
--
-- Faithful Lua port of the corresponding functions in steamtools.py:
--   get_cache_info / clean_cache / get_steam_folder_stats /
--   get_steam_process_info / get_quick_dashboard / scan_steam_libraries
-- Windows-native (tasklist for process info). All returns are Lua tables that
-- main.lua encodes to JSON, matching the Python json.dumps() shapes exactly.

local cjson   = require("json")
local m_utils = require("utils")
local fs      = require("fs")
local st      = require("st_util")

local C = {}

-- Cache category definitions (mirrors steamtools.py _CACHE_TARGETS, in order).
local CACHE_TARGETS = {
    { key = "htmlcache",
      paths = { { "steam", "htmlcache" }, { "localappdata", "htmlcache" } },
      label = "CEF / HTML Cache", description = "Browser cache" },
    { key = "shadercache",
      paths = { { "steam", fs.join("steamapps", "shadercache") }, { "localappdata", "shadercache" } },
      label = "Shader Pre-cache", description = "Vulkan / DX shader cache" },
    { key = "downloadcache",
      paths = { { "steam", fs.join("steamapps", "downloading") }, { "steam", fs.join("steamapps", "temp") } },
      label = "Download Staging", description = "Incomplete downloads and temp" },
    { key = "appcache",
      paths = { { "steam", "appcache" } },
      label = "App Cache", description = "Metadata cache (rebuilds on launch)",
      preserve = { "stats" } },
    { key = "depotcache",
      paths = { { "steam", "depotcache" } },
      label = "Depot Cache", description = "Manifest cache files" },
    { key = "logs",
      paths = { { "steam", "logs" } },
      label = "Steam Logs", description = "Client log files" },
    { key = "usercache",
      paths = { { "steam", "userdata" } },
      label = "User Config Cache", description = "Per-user config (preserves playtime)",
      preserve_files = { "localconfig.vdf" }, target_subdir = "config" },
}

local function target_by_key(key)
    for _, cfg in ipairs(CACHE_TARGETS) do
        if cfg.key == key then return cfg end
    end
    return nil
end

local function resolve_cache_path(root_type, rel)
    local base
    if root_type == "steam" then
        base = st.steam_path()
    elseif root_type == "localappdata" then
        base = st.localappdata_steam()
    else
        return ""
    end
    if not base or base == "" then return "" end
    return fs.join(base, rel)
end

local function set_lower(arr)
    local s = {}
    for _, v in ipairs(arr or {}) do s[tostring(v):lower()] = true end
    return s
end

-- Delete the contents of `path`, preserving named dirs/files. When target_subdir
-- is set, only that subdir under each immediate child (userdata/<id>/config) is
-- wiped, with preserve_files snapshotted and restored. Returns bytes freed.
local function safe_remove_contents(path, preserve_dirs, preserve_files, target_subdir)
    if not fs.is_directory(path) then return 0 end
    local pd = set_lower(preserve_dirs)
    local pf = set_lower(preserve_files)
    local before = st.dir_size(path)

    if target_subdir and target_subdir ~= "" then
        for _, ue in ipairs(fs.list(path) or {}) do
            if ue.is_directory then
                local sub = fs.join(ue.path, target_subdir)
                if fs.is_directory(sub) then
                    local saved = {}
                    for fn in pairs(pf) do
                        local fp = fs.join(sub, fn)
                        if fs.is_file(fp) then
                            local content = m_utils.read_file(fp)
                            if content then saved[fn] = content end
                        end
                    end
                    pcall(fs.remove_all, sub)
                    if next(saved) ~= nil then
                        pcall(fs.create_directories, sub)
                        for fn, data in pairs(saved) do
                            m_utils.write_file(fs.join(sub, fn), data)
                        end
                    end
                end
            end
        end
    else
        for _, item in ipairs(fs.list(path) or {}) do
            local il = (item.name or ""):lower()
            local skip = (pd[il] and item.is_directory) or (pf[il] and item.is_file)
            if not skip then
                if item.is_file or item.is_symlink then
                    pcall(fs.remove, item.path)
                elseif item.is_directory then
                    pcall(fs.remove_all, item.path)
                end
            end
        end
    end

    local freed = before - st.dir_size(path)
    if freed < 0 then freed = 0 end
    return freed
end

--- Size info for every cleanable cache category.
function C.get_cache_info()
    local result = {}
    local total = 0
    for _, cfg in ipairs(CACHE_TARGETS) do
        local cs = 0
        local resolved = {}
        for _, pr in ipairs(cfg.paths) do
            local p = resolve_cache_path(pr[1], pr[2])
            if p ~= "" and fs.is_directory(p) then
                cs = cs + st.dir_size(p)
                table.insert(resolved, p)
            end
        end
        result[cfg.key] = {
            label = cfg.label, description = cfg.description,
            sizeBytes = cs, sizeMB = st.mb(cs), paths = st.A(resolved),
        }
        total = total + cs
    end
    return { success = true, categories = result, totalBytes = total, totalMB = st.mb(total) }
end

--- Clean selected categories (comma-separated keys, empty = all).
function C.clean_cache(categories)
    if type(categories) == "table" then categories = categories.categories end
    local requested = {}
    for c in tostring(categories or ""):gmatch("[^,]+") do
        local key = st.trim(c)
        if key ~= "" then table.insert(requested, key) end
    end
    if #requested == 0 then
        for _, cfg in ipairs(CACHE_TARGETS) do table.insert(requested, cfg.key) end
    end

    local freed = 0
    local errors, cleaned, preserved_info = {}, {}, {}
    local had_err, had_preserve = false, false

    for _, key in ipairs(requested) do
        local cfg = target_by_key(key)
        if not cfg then
            errors[key] = "Unknown category"; had_err = true
        else
            local pd = cfg.preserve or {}
            local pf = cfg.preserve_files or {}
            local ts = cfg.target_subdir
            if #pd > 0 or #pf > 0 then
                local merged = {}
                for _, v in ipairs(pd) do table.insert(merged, v) end
                for _, v in ipairs(pf) do table.insert(merged, v) end
                preserved_info[key] = st.A(merged); had_preserve = true
            end
            local cf = 0
            for _, pr in ipairs(cfg.paths) do
                local p = resolve_cache_path(pr[1], pr[2])
                if p ~= "" and fs.is_directory(p) then
                    local ok, res = pcall(safe_remove_contents, p, pd, pf, ts)
                    if ok then cf = cf + res else errors[key] = tostring(res); had_err = true end
                end
            end
            cleaned[key] = cf
            freed = freed + cf
        end
    end

    return {
        success = true, freedBytes = freed, freedMB = st.mb(freed),
        cleaned = cleaned,
        preserved = had_preserve and preserved_info or st.null,
        errors = had_err and errors or st.null,
    }
end

--- Disk usage breakdown for the main Steam directories.
function C.get_steam_folder_stats()
    local base = st.steam_path()
    if base == "" then return { success = false, error = "Steam path not found" } end

    local order = { "steamapps", "config", "depotcache", "appcache", "htmlcache", "logs", "userdata" }
    local keys = {}
    local tgts = {}
    for _, k in ipairs(order) do tgts[k] = fs.join(base, k); table.insert(keys, k) end

    local la = st.localappdata_steam()
    if la ~= "" and fs.is_directory(la) then
        tgts["localappdata_steam"] = la
        table.insert(keys, "localappdata_steam")
    end

    local stats = {}
    local total = 0
    for _, k in ipairs(keys) do
        local p = tgts[k]
        if fs.is_directory(p) then
            local s = st.dir_size(p)
            stats[k] = { path = p, sizeBytes = s, sizeMB = st.mb(s), sizeGB = st.gb(s) }
            total = total + s
        else
            stats[k] = { path = p, sizeBytes = 0, sizeMB = 0, sizeGB = 0, exists = false }
        end
    end
    return { success = true, steamPath = base, folders = stats, totalBytes = total, totalGB = st.gb(total) }
end

-- Parse one CSV line from `tasklist /FO CSV /NH` into fields.
local function parse_csv_line(line)
    local trimmed = st.trim(line)
    if trimmed == "" then return {} end
    trimmed = trimmed:gsub('^"', ''):gsub('"$', '')
    local parts = {}
    for field in (trimmed .. '","'):gmatch('(.-)","') do table.insert(parts, field) end
    return parts
end

--- Whether Steam / SteamService is running, with PIDs and memory (Windows).
function C.get_steam_process_info()
    local result = { running = false, processes = st.A({}) }

    local procs = {}
    local ok, out = pcall(m_utils.exec, 'tasklist /FI "IMAGENAME eq steam.exe" /FO CSV /NH')
    if ok and out then
        for line in tostring(out):gmatch("([^\r\n]+)") do
            local parts = parse_csv_line(line)
            if #parts >= 5 and parts[1]:lower():find("steam") then
                local mem_str = st.trim(parts[5]:gsub('"', ''):gsub(" K", ""):gsub(",", ""))
                local mem_kb = tonumber(mem_str) or 0
                table.insert(procs, {
                    name = parts[1],
                    pid = tonumber(parts[2]) or 0,
                    memoryKB = mem_kb,
                    memoryMB = st.round(mem_kb / 1024, 1),
                })
            end
        end
    end
    result.processes = st.A(procs)
    result.running = #procs > 0
    local totmem = 0
    for _, p in ipairs(procs) do totmem = totmem + p.memoryMB end
    result.totalMemoryMB = st.round(totmem, 1)

    local ok2, out2 = pcall(m_utils.exec, 'tasklist /FI "IMAGENAME eq steamservice.exe" /FO CSV /NH')
    result.serviceRunning = (ok2 and out2 and tostring(out2):lower():find("steamservice")) and true or false

    result.success = true
    return result
end

--- Combined stats snapshot for the dashboard view.
function C.get_quick_dashboard()
    local base = st.steam_path()
    local stplug = st.stplug_dir()
    local stats = {
        luaFiles = 0, disabledFiles = 0,
        manifestFiles = 0, manifestSizeMB = 0,
        cacheSizeMB = 0, backupCount = 0,
        steamRunning = false, fixesAvailable = 0,
    }

    if stplug ~= "" and fs.is_directory(stplug) then
        for _, e in ipairs(fs.list(stplug) or {}) do
            local n = e.name or ""
            if n:match("%.lua%.disabled$") then
                stats.disabledFiles = stats.disabledFiles + 1
            elseif n:match("%.lua$") then
                stats.luaFiles = stats.luaFiles + 1
            end
        end
    end

    if base ~= "" then
        local dc = fs.join(base, "depotcache")
        if fs.is_directory(dc) then
            for _, e in ipairs(fs.list(dc) or {}) do
                if (e.name or ""):match("%.manifest$") then stats.manifestFiles = stats.manifestFiles + 1 end
            end
            stats.manifestSizeMB = st.round(st.dir_size(dc) / (1024 * 1024), 1)
        end
    end

    local cache_total = 0
    for _, key in ipairs({ "htmlcache", "shadercache", "appcache" }) do
        local cfg = target_by_key(key)
        if cfg then
            for _, pr in ipairs(cfg.paths) do
                local p = resolve_cache_path(pr[1], pr[2])
                if p ~= "" and fs.is_directory(p) then cache_total = cache_total + st.dir_size(p) end
            end
        end
    end
    stats.cacheSizeMB = st.round(cache_total / (1024 * 1024), 1)

    local bd = st.data_path("luatools_backups")
    if fs.is_directory(bd) then
        for _, e in ipairs(fs.list(bd) or {}) do
            if (e.name or ""):match("%.zip$") then stats.backupCount = stats.backupCount + 1 end
        end
    end

    stats.steamRunning = st.steam_is_running()

    -- fixesAvailable: best-effort (mirrors Python try/except -> 0 on any failure).
    local ok, fixes = pcall(require, "fixes")
    if ok and type(fixes) == "table" and type(fixes.get_fixes_index) == "function"
        and stplug ~= "" and fs.is_directory(stplug) then
        local ok2, index = pcall(fixes.get_fixes_index)
        if ok2 and type(index) == "table" then
            local lua_appids = {}
            for _, e in ipairs(fs.list(stplug) or {}) do
                local aid = (e.name or ""):match("^(%d+)%.lua")
                if aid then lua_appids[tonumber(aid)] = true end
            end
            local generic = index.generic or {}
            local online = index.online or {}
            local avail = 0
            for aid in pairs(lua_appids) do
                if generic[aid] or generic[tostring(aid)] or online[aid] or online[tostring(aid)] then
                    avail = avail + 1
                end
            end
            stats.fixesAvailable = avail
        end
    end

    stats.success = true
    return stats
end

-- Find all Steam library paths (base + libraryfolders.vdf entries).
local function scan_all_steam_libraries(base)
    local libs = { base }
    local seen = { [base:lower()] = true }
    local vdf_path = fs.join(base, "config", "libraryfolders.vdf")
    if fs.is_file(vdf_path) then
        local content = m_utils.read_file(vdf_path) or ""
        for raw in content:gmatch('"path"%s+"([^"]+)"') do
            local p = raw:gsub('\\\\', '\\')
            if p ~= "" and fs.is_directory(p) and not seen[p:lower()] then
                table.insert(libs, p)
                seen[p:lower()] = true
            end
        end
    end
    return libs
end

--- Scan all drives for Steam libraries: path, game count, size, first games.
function C.scan_steam_libraries()
    local base = st.steam_path()
    if base == "" then return { success = false, error = "Steam path not found" } end

    local libraries = {}
    for _, lib_path in ipairs(scan_all_steam_libraries(base)) do
        local sa = fs.join(lib_path, "steamapps")
        local entry = {
            path = lib_path,
            isPrimary = lib_path:lower() == base:lower(),
            exists = fs.is_directory(sa),
            gameCount = 0,
            sizeGB = 0,
            games = st.A({}),
        }
        if fs.is_directory(sa) then
            local acfs = {}
            for _, e in ipairs(fs.list(sa) or {}) do
                local n = e.name or ""
                if n:match("^appmanifest_") and n:match("%.acf$") then table.insert(acfs, n) end
            end
            entry.gameCount = #acfs

            local common = fs.join(sa, "common")
            if fs.is_directory(common) then
                local total = 0
                local rec = fs.list_recursive(common)
                if rec then
                    for _, e in ipairs(rec) do
                        if e.is_file and (e.depth == nil or e.depth < 3) then
                            local sz = fs.file_size(e.path)
                            if sz then total = total + sz end
                        end
                    end
                end
                entry.sizeGB = st.round(total / (1024 * 1024 * 1024), 1)
            end

            table.sort(acfs)
            local games = {}
            for i = 1, math.min(20, #acfs) do
                local c = m_utils.read_file(fs.join(sa, acfs[i]))
                if c then
                    table.insert(games, {
                        appid = tonumber(c:match('"appid"%s+"(%d+)"')) or 0,
                        name = c:match('"name"%s+"([^"]*)"') or "?",
                    })
                end
            end
            entry.games = st.A(games)
        end
        table.insert(libraries, entry)
    end

    return { success = true, libraryCount = #libraries, libraries = st.A(libraries) }
end

return C
