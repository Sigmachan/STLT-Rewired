-- manifests.lua — depot manifest updater / staleness check / depotcache sync.
--
-- Faithful Lua port of steamtools.py update_manifests / check_manifest_staleness /
-- sync_depotcache. Manifest bytes are fetched from the GitHub mirror, then ManifestHub
-- (hubcapmanifest.com generate API + manifesthub.filegear-sg.me depot API; same key).
-- Steamcmd (api.steamcmd.net) provides the authoritative public manifest gids.

local cjson       = require("json")
local m_utils     = require("utils")
local fs          = require("fs")
local http_client = require("http_client")
local logger      = require("plugin_logger")
local st          = require("st_util")

local M = {}

local USER_AGENT = "STLT-Rewired/1.0"
local MH_BACKUP_URL = "https://raw.githubusercontent.com/qwe213312/k25FCdfEOoEJ42S6/main"
local MANIFESTHUB_GENERATE_URL = "https://hubcapmanifest.com/api/v1/generate/manifest"
local MANIFESTHUB_DEPOT_URL = "https://api.manifesthub1.filegear-sg.me/manifest"

-- steamcmd app info, cached per process (single-threaded; no lock needed).
local APP_INFO_CACHE = {}
local function fetch_app_info(appid)
    if APP_INFO_CACHE[appid] ~= nil then return APP_INFO_CACHE[appid] end
    local ok, resp = pcall(http_client.get, "https://api.steamcmd.net/v1/info/" .. tostring(appid), { timeout = 10 })
    if ok and resp and resp.status == 200 and resp.body then
        local ok2, parsed = pcall(cjson.decode, resp.body)
        if ok2 and type(parsed) == "table" and type(parsed.data) == "table" then
            local root = parsed.data[tostring(appid)]
            if type(root) == "table" then
                local out = { depots = type(root.depots) == "table" and root.depots or {} }
                APP_INFO_CACHE[appid] = out
                return out
            end
        end
    end
    APP_INFO_CACHE[appid] = { depots = {} }
    return APP_INFO_CACHE[appid]
end

-- Best-effort ManifestHub API-key lookup from settings.manager (skipped if unsupported).
local function get_manifesthub_key()
    local ok, sm = pcall(require, "settings.manager")
    if ok and type(sm) == "table" and type(sm.get_manifesthub_api_key) == "function" then
        local ok2, k = pcall(sm.get_manifesthub_api_key)
        if ok2 and type(k) == "string" then return k end
    end
    return ""
end

local function try_fetch(url)
    local ok, resp = pcall(http_client.get, url, { timeout = 30, headers = { ["User-Agent"] = USER_AGENT } })
    if ok and resp and resp.status == 200 and resp.body and #resp.body > 0 then
        return resp.body
    end
    return nil
end

local function fetch_manifest_bytes(depot_id, manifest_id, api_key)
    local data = try_fetch(MH_BACKUP_URL .. "/" .. depot_id .. "_" .. manifest_id .. ".manifest")
    if not data and api_key ~= "" then
        data = try_fetch(MANIFESTHUB_GENERATE_URL .. "?depot_id=" .. depot_id .. "&manifest_id=" .. manifest_id .. "&api_key=" .. api_key)
    end
    if not data and api_key ~= "" then
        data = try_fetch(MANIFESTHUB_DEPOT_URL .. "?apikey=" .. api_key .. "&depotid=" .. depot_id .. "&manifestid=" .. manifest_id)
    end
    return data
end

local function write_manifest_to_cache(base, depot_id, manifest_id, data)
    if not data or data == "" then return false end
    local cache_dirs = {
        fs.join(base, "depotcache"),
        fs.join(base, "config", "depotcache"),
    }
    local fname = depot_id .. "_" .. manifest_id .. ".manifest"
    local wrote = false
    for _, cd in ipairs(cache_dirs) do
        pcall(fs.create_directories, cd)
        local dest = fs.join(cd, fname)
        local f = io.open(dest, "wb")
        if f then
            f:write(data)
            f:close()
            wrote = true
        end
    end
    return wrote
end

local function remove_stale_depot_manifests(base, depot_id, keep_mid)
    keep_mid = tostring(keep_mid or "")
    depot_id = tostring(depot_id or "")
    for _, subdir in ipairs({ "depotcache", fs.join("config", "depotcache") }) do
        local cd = fs.join(base, subdir)
        if fs.is_directory(cd) then
            for _, e in ipairs(fs.list(cd) or {}) do
                local name = e.name or ""
                local d, m = name:match("^(%d+)_(%d+)%.manifest$")
                if d == depot_id and m ~= keep_mid then
                    pcall(fs.remove, e.path or fs.join(cd, name))
                end
            end
        end
    end
end

local function depot_has_stale_manifest(base, depot_id, keep_mid)
    keep_mid = tostring(keep_mid or "")
    depot_id = tostring(depot_id or "")
    for _, subdir in ipairs({ "depotcache", fs.join("config", "depotcache") }) do
        local cd = fs.join(base, subdir)
        if fs.is_directory(cd) then
            for _, e in ipairs(fs.list(cd) or {}) do
                local name = e.name or ""
                local d, m = name:match("^(%d+)_(%d+)%.manifest$")
                if d == depot_id and m ~= keep_mid then
                    return true
                end
            end
        end
    end
    return false
end

-- Extract (depot, second-addappid-arg) pairs. NOTE: mirrors the Python quirk of
-- treating addappid's 2nd argument as the "local manifest" for staleness/sync.
local function addappid_pairs(content)
    local out = {}
    for depot, num in tostring(content):gmatch("addappid%s*%(%s*(%d+)%s*,%s*(%d+)%s*,") do
        out[#out + 1] = { depot, num }
    end
    return out
end

function M.update_manifests(appid)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "Invalid appid" } end
    local content, err = st.read_lua_file(appid)
    if content == nil then return { success = false, error = err } end
    local depot_ids = st.get_depot_ids_from_lua(content)
    if #depot_ids == 0 then return { success = false, error = "No depot IDs in lua" } end

    local info = fetch_app_info(appid)
    local depots_data = info.depots or {}
    if not next(depots_data) then return { success = false, error = "No depot info from steamcmd" } end

    local base = st.steam_path()
    local dc = fs.join(base, "depotcache")
    pcall(fs.create_directories, dc)

    local api_key = get_manifesthub_key()

    local dl, sk, rf, fl = {}, {}, {}, {}
    for _, did in ipairs(depot_ids) do
        local mid = st.get_manifest_id(depots_data, did)
        if not mid or mid == "" then
            table.insert(fl, { depotId = did, reason = "No public manifest" })
        elseif st.find_manifest_file(base, did, mid) then
            table.insert(sk, { depotId = did, manifestId = mid })
        else
            local was_stale = depot_has_stale_manifest(base, did, mid)
            if was_stale then
                remove_stale_depot_manifests(base, did, mid)
            end
            local data = fetch_manifest_bytes(did, mid, api_key)
            if data and write_manifest_to_cache(base, did, mid, data) then
                local rec = { depotId = did, manifestId = mid, sizeBytes = #data }
                if was_stale then rec.refreshed = true end
                if was_stale then
                    table.insert(rf, rec)
                else
                    table.insert(dl, rec)
                end
            else
                table.insert(fl, { depotId = did, manifestId = mid,
                    reason = "All sources failed (GitHub mirror / ManifestHub API)" })
            end
        end
    end

    return {
        success = true, appid = appid,
        downloaded = st.A(dl), refreshed = st.A(rf), skipped = st.A(sk), failed = st.A(fl),
        summary = {
            total = #depot_ids,
            downloaded = #dl,
            refreshed = #rf,
            skipped = #sk,
            failed = #fl,
        },
    }
end

function M.check_manifest_staleness(appid)
    appid = tonumber(appid) or 0
    local stplug = st.stplug_dir()
    if stplug == "" or not fs.is_directory(stplug) then
        return { success = false, error = "stplug-in not found" }
    end

    local targets = {}
    if appid ~= 0 then
        targets = { appid }
    else
        for _, e in ipairs(fs.list(stplug) or {}) do
            local aid = (e.name or ""):match("^(%d+)%.lua$")
            if aid then table.insert(targets, tonumber(aid)) end
        end
    end

    local results = {}
    for i = 1, math.min(#targets, 50) do
        local aid = targets[i]
        local content = st.read_lua_file(aid)
        if content then
            local local_depots = addappid_pairs(content)
            if #local_depots > 0 then
                local info = fetch_app_info(aid)
                local remote_depots = info.depots or {}
                local app_stale = false
                local depot_checks = {}
                for _, pair in ipairs(local_depots) do
                    local depot_id, local_manifest = pair[1], pair[2]
                    local remote_gid = st.get_manifest_id(remote_depots, depot_id) or ""
                    local is_stale = remote_gid ~= "" and tostring(remote_gid) ~= tostring(local_manifest)
                    if is_stale then app_stale = true end
                    table.insert(depot_checks, {
                        depot_id = depot_id, ["local"] = local_manifest,
                        remote = remote_gid ~= "" and remote_gid or "?", stale = is_stale,
                    })
                end
                local stale_count = 0
                for _, d in ipairs(depot_checks) do if d.stale then stale_count = stale_count + 1 end end
                table.insert(results, {
                    appid = aid, stale = app_stale, depots = st.A(depot_checks),
                    total_depots = #depot_checks, stale_count = stale_count,
                })
                m_utils.sleep(250)
            end
        end
    end

    local total_stale = 0
    for _, r in ipairs(results) do if r.stale then total_stale = total_stale + 1 end end
    return { success = true, results = st.A(results), total_checked = #results, total_stale = total_stale }
end

function M.sync_depotcache(appid)
    appid = tonumber(appid) or 0
    local base = st.steam_path()
    if base == "" then return { success = false, error = "Steam path not found" } end
    local stplug = st.stplug_dir()

    local targets = {}
    if appid ~= 0 then
        targets = { appid }
    elseif fs.is_directory(stplug) then
        for _, e in ipairs(fs.list(stplug) or {}) do
            local aid = (e.name or ""):match("^(%d+)%.lua$")
            if aid then table.insert(targets, tonumber(aid)) end
        end
    end

    local cache_dirs = { fs.join(base, "depotcache"), fs.join(base, "config", "depotcache") }
    for _, d in ipairs(cache_dirs) do pcall(fs.create_directories, d) end

    local existing = {}
    for _, cd in ipairs(cache_dirs) do
        if fs.is_directory(cd) then
            for _, e in ipairs(fs.list(cd) or {}) do
                if (e.name or ""):match("%.manifest$") then existing[e.name] = true end
            end
        end
    end

    local missing, present = {}, {}
    for _, aid in ipairs(targets) do
        local content = st.read_lua_file(aid)
        if content then
            for _, pair in ipairs(addappid_pairs(content)) do
                local fname = pair[1] .. "_" .. pair[2] .. ".manifest"
                local rec = { appid = aid, depot = pair[1], manifest = pair[2] }
                if existing[fname] then table.insert(present, rec) else table.insert(missing, rec) end
            end
        end
    end

    local fetched, failed = 0, 0
    local api_key = get_manifesthub_key()
    if #missing > 0 then
        for i = 1, math.min(#missing, 100) do
            local item = missing[i]
            local data = fetch_manifest_bytes(item.depot, item.manifest, api_key)
            if data and write_manifest_to_cache(base, item.depot, item.manifest, data) then
                fetched = fetched + 1
            else
                failed = failed + 1
            end
            m_utils.sleep(500)
        end
    end

    return {
        success = true,
        total_depots = #present + #missing,
        present = #present,
        missing_before = #missing,
        fetched = fetched,
        failed = failed,
        still_missing = #missing - fetched,
        manifesthub_available = api_key ~= "",
    }
end

-- Depot-cache inventory report. SAFE BY DESIGN — never deletes or moves anything. On a real
-- machine the manifests whose depot is not named by any lua are overwhelmingly legit Steam-owned
-- games (Steam manages/re-fetches them), so removal is neither useful nor safe. The genuinely
-- useful repair (fetching missing pinned manifests for lua games) is SyncDepotcache's job; this
-- reports the inventory and points there. NOTE on the lua format: addappid's args are
-- (depot, flag, decryptionKey) — NOT (depot, manifestId); the manifest id lives in
-- setManifestid(depot, "manifestId"). A manifest belongs to a lua game iff its depot is named by
-- any lua, so classification is depot-based, not manifest-id-based.
function M.repair_depotcache(dry_run, fix_lua, orphan_age_days, remove_orphans)
    local base = st.steam_path()
    if base == "" then return { success = false, error = "Steam path not found" } end
    local stplug = st.stplug_dir()

    -- Referenced depots (1st arg of non-commented addappid/setManifestid) and pinned manifest files.
    local ref_depots, ref_depot_count = {}, 0
    local pinned, pinned_count = {}, 0
    if fs.is_directory(stplug) then
        for _, e in ipairs(fs.list(stplug) or {}) do
            local aid = (e.name or ""):match("^(%d+)%.lua$")
            if aid then
                local content = st.read_lua_file(tonumber(aid))
                if content then
                    for line in (content .. "\n"):gmatch("([^\n]*)\n") do
                        local s = line:gsub("^%s+", "")
                        if s:sub(1, 2) ~= "--" then
                            local d1 = s:match("addappid%s*%(%s*(%d+)")
                            if d1 and not ref_depots[d1] then ref_depots[d1] = true; ref_depot_count = ref_depot_count + 1 end
                            local dm, mid = s:match("setManifestid%s*%(%s*(%d+)%s*,%s*\"?(%d+)")
                            if dm then
                                if not ref_depots[dm] then ref_depots[dm] = true; ref_depot_count = ref_depot_count + 1 end
                                local fn = dm .. "_" .. mid .. ".manifest"
                                if not pinned[fn] then pinned[fn] = true; pinned_count = pinned_count + 1 end
                            end
                        end
                    end
                end
            end
        end
    end

    -- On-disk manifests; classify by whether their depot is referenced by a lua game.
    local cache_dirs = { fs.join(base, "depotcache"), fs.join(base, "config", "depotcache") }
    local on_disk, present = 0, {}
    local unref_count, unref_bytes = 0, 0
    for _, cd in ipairs(cache_dirs) do
        if fs.is_directory(cd) then
            for _, e in ipairs(fs.list(cd) or {}) do
                local name = e.name or ""
                if name:match("%.manifest$") then
                    on_disk = on_disk + 1
                    present[name] = true
                    local depot = name:match("^(%d+)_")
                    if depot and not ref_depots[depot] then
                        unref_count = unref_count + 1
                        unref_bytes = unref_bytes + (fs.file_size(e.path or fs.join(cd, name)) or 0)
                    end
                end
            end
        end
    end

    -- Pinned (setManifestid) manifests for lua games missing on disk → SyncDepotcache fetches these.
    local missing_pinned = 0
    for fn in pairs(pinned) do if not present[fn] then missing_pinned = missing_pinned + 1 end end

    local unref_mb = math.floor(unref_bytes / (1024 * 1024) * 10 + 0.5) / 10

    return {
        success = true,
        totals = {
            manifests_scanned = on_disk,
            manifests_downloaded = 0,
            manifests_removed = 0,
            junk_files_removed = 0,
            lua_lines_fixed = 0,
        },
        phases = {
            scan = {
                on_disk = on_disk, lua_referenced_depots = ref_depot_count,
                pinned_manifests = pinned_count,
                unreferenced_by_lua = unref_count, unreferenced_size_mb = unref_mb,
            },
            download = {
                downloaded = 0, missing_pinned = missing_pinned,
                note = missing_pinned > 0 and "run Sync Depot Cache to fetch missing pinned manifests"
                    or "no pinned manifests missing",
            },
            cleanup = {
                removed = 0,
                note = "report only: unreferenced manifests are mostly legit Steam-owned games; nothing deleted",
            },
            lua_fix = { enabled = fix_lua and true or false, files_fixed = 0, lines_commented_out = 0 },
        },
    }
end

return M
