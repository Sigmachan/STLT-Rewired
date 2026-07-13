-- lua_tools.lua — Per-.lua script tooling.
--
-- Faithful Lua port of the steamtools.py functions:
--   get_steamtools_ids / toggle_lua_script / validate_lua_syntax /
--   clean_lua_content / extract_lua_keys / detect_depot_conflicts /
--   audit_lua_content / batch_health_scan
-- All regex is translated to Lua patterns (equivalent for these inputs).
-- app-info lookups hit api.steamcmd.net via http_client (cached per process).

local cjson   = require("json")
local m_utils = require("utils")
local fs      = require("fs")
local logger  = require("plugin_logger")
local st      = require("st_util")

local C = {}

-- ── shared helpers ───────────────────────────────────────────────────────────

-- Read <appid>.lua (or .lua.disabled). Returns (content, path) or (nil, err).
local function read_lua_file(appid)
    local stplug = st.stplug_dir()
    if stplug == "" then return nil, "Steam path not found" end
    for _, ext in ipairs({ ".lua", ".lua.disabled" }) do
        local p = fs.join(stplug, tostring(appid) .. ext)
        if fs.is_file(p) then
            local content = m_utils.read_file(p)
            if content then return content, p end
            return nil, "read failed"
        end
    end
    return nil, "Lua file not found"
end

-- Depot IDs that carry a decryption key: addappid(id, N, "hex").
local function get_depot_ids_from_lua(content)
    local seen, out = {}, {}
    for line in (tostring(content) .. "\n"):gmatch("([^\n]*)\n") do
        local did = line:match('addappid%s*%(%s*(%d+)%s*,%s*%d+%s*,%s*"%x+"')
        if did and not seen[did] then seen[did] = true; table.insert(out, did) end
    end
    table.sort(out, function(a, b) return tonumber(a) < tonumber(b) end)
    return out
end

local function get_manifest_id(depots_data, depot_id)
    if type(depots_data) ~= "table" then return nil end
    local d = depots_data[depot_id]
    if type(d) ~= "table" then return nil end
    local m = d.manifests
    if type(m) ~= "table" then return nil end
    local pub = m.public
    if type(pub) == "table" then return tostring(pub.gid or "") end
    if type(pub) == "string" and st.trim(pub) ~= "" then return st.trim(pub) end
    return nil
end

-- Manifest present in either depotcache location, non-empty.
local function find_manifest_file(base, depot_id, manifest_id)
    local fname = depot_id .. "_" .. manifest_id .. ".manifest"
    for _, subdir in ipairs({ "depotcache", fs.join("config", "depotcache") }) do
        local fp = fs.join(base, subdir, fname)
        if fs.is_file(fp) then
            local sz = fs.file_size(fp)
            if sz and sz > 0 then return fp end
        end
    end
    return nil
end

-- Steam manifest magic bytes 0x27 0x44 0x56 0x01 (cheap 4-byte read via io).
local function verify_manifest_magic(path)
    local f = io.open(path, "rb")
    if not f then return false end
    local magic = f:read(4)
    f:close()
    return magic == "\39\68\86\1"
end

-- steamcmd.net app info, cached per process (no lock needed; Lua is single-threaded).
local APP_INFO_CACHE = {}

local function fetch_app_info(appid)
    if APP_INFO_CACHE[appid] ~= nil then return APP_INFO_CACHE[appid] end
    local http_client = require("http_client")
    local ok, resp = pcall(function()
        if type(http_client.get) ~= "function" then error("no http") end
        return http_client.get("https://api.steamcmd.net/v1/info/" .. tostring(appid), { timeout = 10 })
    end)
    if ok and resp and resp.status == 200 and resp.body then
        local ok2, parsed = pcall(cjson.decode, resp.body)
        if ok2 and type(parsed) == "table" then
            local data = parsed.data
            if type(data) == "table" then
                local root = data[tostring(appid)]
                if type(root) == "table" then
                    local depots = type(root.depots) == "table" and root.depots or {}
                    local extended = type(root.extended) == "table" and root.extended or {}
                    local common = type(root.common) == "table" and root.common or {}
                    local out = {
                        workshop_depot = depots.workshopdepot or 0,
                        dlc_list = extended.listofdlc or "",
                        depots = depots,
                        name = common.name or "",
                    }
                    APP_INFO_CACHE[appid] = out
                    return out
                end
            end
        end
    else
        logger.warn("lua_tools: fetch_app_info failed for " .. tostring(appid))
    end
    APP_INFO_CACHE[appid] = {}
    return {}
end

-- ── 1. collection sync ───────────────────────────────────────────────────────

function C.get_steamtools_ids(include_disabled)
    if type(include_disabled) == "table" then include_disabled = include_disabled.showDisabled end
    local stplug = st.stplug_dir()
    if stplug == "" or not fs.is_directory(stplug) then
        return { success = true, ids = st.A({}), csv = "", count = 0 }
    end
    local ids = {}
    for _, e in ipairs(fs.list(stplug) or {}) do
        local n = e.name or ""
        local is_lua = n:match("%.lua$") ~= nil
        local is_disabled = n:match("%.lua%.disabled$") ~= nil
        if (is_lua or is_disabled) and (include_disabled or not is_disabled) then
            local aid = n:match("^(%d+)%.lua")
            if aid then table.insert(ids, tonumber(aid)) end
        end
    end
    table.sort(ids)
    local strs = {}
    for _, id in ipairs(ids) do table.insert(strs, tostring(id)) end
    return { success = true, ids = st.A(ids), csv = table.concat(strs, ","), count = #ids }
end

-- ── toggle enable/disable ────────────────────────────────────────────────────

function C.toggle_lua_script(appid, enable)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "Invalid appid" } end
    if enable == nil then enable = true end
    local ok, unlock_paths = pcall(require, "unlock_paths")
    if not ok or type(unlock_paths) ~= "table" or type(unlock_paths.lua_script_dir) ~= "function" then
        return { success = false, error = "unlock_paths unavailable" }
    end
    local dir = unlock_paths.lua_script_dir()
    if dir == "" or not fs.is_directory(dir) then
        return { success = false, error = "Lua script directory not found" }
    end
    local lp = fs.join(dir, appid .. ".lua")
    local dp = lp .. ".disabled"
    if enable then
        if fs.is_file(dp) then
            fs.rename(dp, lp)
            return { success = true, state = "enabled" }
        elseif fs.is_file(lp) then
            return { success = true, state = "already_enabled" }
        end
        return { success = false, error = "Lua file not found" }
    else
        if fs.is_file(lp) then
            fs.rename(lp, dp)
            return { success = true, state = "disabled" }
        elseif fs.is_file(dp) then
            return { success = true, state = "already_disabled" }
        end
        return { success = false, error = "Lua file not found" }
    end
end

-- ── syntax validator (port of cleanluas.ps1 line checker) ────────────────────

local function is_valid_lua_line(line)
    local trimmed = st.trim(line)
    if trimmed == "" or trimmed:sub(1, 1) == "-" then return true, "" end
    local low = trimmed:lower()
    if low:match("^addtoken") then return true, "" end

    local func_name
    if low:match("^addappid") then func_name = "addappid"
    elseif low:match("^setmanifestid") then func_name = "setManifestid" end
    if not func_name then
        return false, "Unrecognized statement: " .. trimmed:sub(1, 60)
    end

    -- After the name, optional whitespace, then a "(" (mirrors \s*(\(.*)).
    local after_name = trimmed:sub(#func_name + 1)
    local lead = after_name:match("^(%s*)")
    local paren_start = after_name:find("(", 1, true)
    if not paren_start or paren_start ~= (#lead + 1) then
        return false, "Unrecognized statement: " .. trimmed:sub(1, 60)
    end

    local rest = after_name:sub(paren_start)
    local before_comment = rest
    local dd = rest:find("--", 1, true)
    if dd then before_comment = rest:sub(1, dd - 1) end

    local depth, close_pos = 0, -1
    for i = 1, #before_comment do
        local ch = before_comment:sub(i, i)
        if ch == "(" then
            depth = depth + 1
        elseif ch == ")" then
            depth = depth - 1
            if depth == 0 then close_pos = i; break end
        end
    end
    if close_pos < 0 then return false, "Unmatched parenthesis in " .. func_name .. "()" end

    local after = st.trim(before_comment:sub(close_pos + 1))
    if after ~= "" and after:sub(1, 2) ~= "--" then
        return false, "Content after " .. func_name .. "() closing paren"
    end

    local paren_content = before_comment:sub(2, close_pos - 1)
    local without_quotes = paren_content:gsub('"[^"]*"', "")
    for hexrun in without_quotes:gmatch("%x+") do
        if #hexrun >= 40 then return false, "Unquoted hex hash in " .. func_name .. "()" end
    end
    return true, ""
end

function C.validate_lua_syntax(appid)
    if type(appid) == "table" then appid = appid.appid end
    appid = tonumber(appid) or 0
    local stplug = st.stplug_dir()
    if stplug == "" or not fs.is_directory(stplug) then
        return { success = false, error = "stplug-in not found" }
    end

    local targets = {}
    local listing = fs.list(stplug) or {}
    if appid ~= 0 then
        for _, ext in ipairs({ ".lua", ".lua.disabled" }) do
            local p = fs.join(stplug, appid .. ext)
            if fs.is_file(p) then table.insert(targets, p); break end
        end
        if #targets == 0 then return { success = false, error = "Lua not found for " .. appid } end
    else
        for _, e in ipairs(listing) do
            local n = e.name or ""
            if n:match("%.lua$") or n:match("%.lua%.disabled$") then table.insert(targets, e.path) end
        end
    end

    local non_lua = {}
    for _, e in ipairs(listing) do
        local n = e.name or ""
        if e.is_file and not (n:match("%.lua$") or n:match("%.lua%.disabled$")) then
            table.insert(non_lua, n)
        end
    end

    table.sort(targets)
    local results = {}
    local total_bad = 0
    for _, fp in ipairs(targets) do
        local fn = fs.filename(fp)
        local content = m_utils.read_file(fp)
        if not content then
            table.insert(results, { filename = fn, valid = false, error = "read failed", badLines = st.A({}) })
            total_bad = total_bad + 1
        else
            local bad = {}
            local lines = st.split_lines(content)
            for i, l in ipairs(lines) do
                local ok, reason = is_valid_lua_line(l)
                if not ok then
                    table.insert(bad, { line = i, content = st.rtrim(l):sub(1, 120), reason = reason })
                end
            end
            if #bad > 0 then total_bad = total_bad + 1 end
            table.insert(results, {
                filename = fn, valid = #bad == 0, lineCount = #lines, badLines = st.A(bad),
            })
        end
    end
    return {
        success = true, filesChecked = #results, filesWithErrors = total_bad,
        nonLuaFiles = st.A(non_lua), results = st.A(results),
    }
end

-- ── strip branding/credit comments ───────────────────────────────────────────

-- Comment patterns to strip (Lua-pattern equivalents of _REMOVE_PATTERNS, run on
-- a lower-cased, already-trimmed comment line). Alternation split into variants.
local REMOVE_PATTERNS = {
    "%-%-%s*manifest%s*&%s*lua%s*provided%s*by",
    "%-%-%s*manifest%s*and%s*lua%s*provided%s*by",
    "%-%-%s*via%s+manilua",
    "%-%-%s*https?://",
    "%-%-%s*provided%s+by",
    "%-%-%s*source:",
    "^%-%-%s*dlc%s*$",
    "^%-%-%s*===+",
    "%-%-%s*credits:",
    "%-%-%s*discord:",
    "%-%-%s*website:",
    "%-%-%s*k3rn",
    "%-%-%s*kernelos",
}

function C.clean_lua_content(appid)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "Invalid appid" } end
    local content, err = read_lua_file(appid)
    if content == nil then return { success = false, error = err } end

    local normalized = content:gsub("\r\n", "\n"):gsub("\r", "\n")
    local cleaned = {}
    local removed_count = 0
    for _, line in ipairs(st.split_lines(normalized)) do
        local stripped = st.trim(line)
        if stripped ~= "" then
            local skip = false
            if stripped:sub(1, 2) == "--" then
                local low = stripped:lower()
                for _, pat in ipairs(REMOVE_PATTERNS) do
                    if low:find(pat) then skip = true; removed_count = removed_count + 1; break end
                end
            end
            if not skip then table.insert(cleaned, line) end
        end
    end

    if removed_count == 0 then
        return { success = true, removedLines = 0, message = "Already clean" }
    end

    local stplug = st.stplug_dir()
    for _, ext in ipairs({ ".lua", ".lua.disabled" }) do
        local p = fs.join(stplug, appid .. ext)
        if fs.is_file(p) then
            local result = st.rtrim(table.concat(cleaned, "\n"))
            local ok = m_utils.write_file(p, result ~= "" and (result .. "\n") or "")
            if ok == false then return { success = false, error = "write failed" } end
            return { success = true, removedLines = removed_count, path = p }
        end
    end
    return { success = false, error = "File not found for write-back" }
end

-- ── extract depot keys / manifest ids / tokens ───────────────────────────────

function C.extract_lua_keys(appid)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "Invalid appid" } end
    local content, err = read_lua_file(appid)
    if content == nil then return { success = false, error = err } end

    local keys, manifests, tokens = {}, {}, {}
    local nk, nm, nt = 0, 0, 0

    for id, key in content:gmatch('addappid%s*%(%s*(%d+)%s*,%s*%d+%s*,%s*"([^"]+)"%s*%)') do
        if keys[id] == nil then nk = nk + 1 end
        keys[id] = st.trim(key)
    end
    for id, mid in content:gmatch('setManifestid%s*%(%s*(%d+)%s*,%s*"([^"]+)"%s*%)') do
        if manifests[id] == nil then nm = nm + 1 end
        manifests[id] = st.trim(mid)
    end
    for id, tok in content:gmatch('addtoken%s*%(%s*(%d+)%s*,%s*"([^"]+)"%s*%)') do
        if tokens[id] == nil then nt = nt + 1 end
        tokens[id] = st.trim(tok)
    end

    local all_ids, seen = {}, {}
    for id in content:gmatch('addappid%s*%(%s*(%d+)') do
        if id ~= tostring(appid) and not seen[id] then
            seen[id] = true
            table.insert(all_ids, id)
        end
    end

    return {
        success = true, appid = appid,
        depotKeys = keys,
        manifestIds = manifests,
        tokens = tokens,
        referencedAppIds = st.A(all_ids),
        summary = {
            totalDepots = nk, totalManifests = nm,
            totalTokens = nt, totalReferenced = #all_ids,
        },
    }
end

-- ── content audit (workshop + DLC completeness) ──────────────────────────────

function C.audit_lua_content(appid)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "Invalid appid" } end
    local content, lua_path = read_lua_file(appid)
    if content == nil then return { success = false, error = lua_path } end

    local depot_ids, depot_lines, seen = {}, {}, {}
    for line in (content .. "\n"):gmatch("([^\n]*)\n") do
        if not line:match("^%s*%-%-") then
            local did = line:match("addappid%s*%(%s*(%d+)")
            if did then
                table.insert(depot_ids, tonumber(did))
                depot_lines[did] = line
                seen[did] = true
            end
        end
    end

    local info = fetch_app_info(appid)
    local ws_depot = tostring(info.workshop_depot or 0)
    local ws_status, ws_label
    if ws_depot == "0" or ws_depot == "" then
        ws_status, ws_label = "no_workshop", "No workshop for this game"
    else
        local line_nospace = depot_lines[ws_depot] and depot_lines[ws_depot]:gsub(" ", "") or nil
        if line_nospace and line_nospace:match(',%d+,["\']') then
            ws_status, ws_label = "included", "Workshop included"
        elseif seen[ws_depot] then
            ws_status, ws_label = "partial", "Workshop depot present but no key"
        else
            ws_status, ws_label = "missing", "Workshop missing"
        end
    end

    local dlc_inc, dlc_miss = {}, {}
    local raw_dlc = st.trim(tostring(info.dlc_list or ""))
    if raw_dlc ~= "" then
        for piece in raw_dlc:gmatch("[^,]+") do
            local p = st.trim(piece)
            if p:match("^%d+$") then
                if seen[p] then table.insert(dlc_inc, tonumber(p)) else table.insert(dlc_miss, tonumber(p)) end
            end
        end
    end

    return {
        success = true, appid = appid,
        workshop = { status = ws_status, label = ws_label },
        dlc = { included = st.A(dlc_inc), missing = st.A(dlc_miss), total = #dlc_inc + #dlc_miss },
        depotCount = #depot_ids,
    }
end

-- ── detect depot conflicts across all lua files ──────────────────────────────

function C.detect_depot_conflicts()
    local stplug = st.stplug_dir()
    if stplug == "" or not fs.is_directory(stplug) then
        return { success = false, error = "stplug-in not found" }
    end

    local depot_map = {}
    local order = {}
    local file_count = 0
    for _, e in ipairs(fs.list(stplug) or {}) do
        local n = e.name or ""
        if (n:match("%.lua$") or n:match("%.lua%.disabled$")) then
            local aid = n:match("^(%d+)%.lua")
            if aid then
                local appid = tonumber(aid)
                file_count = file_count + 1
                local content = m_utils.read_file(e.path) or ""
                for line in (content .. "\n"):gmatch("([^\n]*)\n") do
                    if not line:match("^%s*%-%-") then
                        local did = line:match('addappid%s*%(%s*(%d+)%s*,%s*%d+%s*,%s*"')
                        if did and did ~= tostring(appid) then
                            if not depot_map[did] then depot_map[did] = {}; table.insert(order, did) end
                            table.insert(depot_map[did], appid)
                        end
                    end
                end
            end
        end
    end

    table.sort(order, function(a, b) return tonumber(a) < tonumber(b) end)
    local conflicts = {}
    for _, did in ipairs(order) do
        local owners = depot_map[did]
        if #owners > 1 then
            local uniq, seen2 = {}, {}
            for _, o in ipairs(owners) do
                if not seen2[o] then seen2[o] = true; table.insert(uniq, o) end
            end
            table.sort(uniq)
            table.insert(conflicts, { depotId = did, referencedBy = st.A(uniq) })
        end
    end

    return {
        success = true, filesScanned = file_count,
        conflictsFound = #conflicts, conflicts = st.A(conflicts),
    }
end

-- ── one-click batch health scan ──────────────────────────────────────────────

function C.batch_health_scan()
    local stplug = st.stplug_dir()
    if stplug == "" or not fs.is_directory(stplug) then
        return { success = false, error = "stplug-in not found" }
    end
    local base = st.steam_path()

    local appids = {}
    for _, e in ipairs(fs.list(stplug) or {}) do
        local aid = (e.name or ""):match("^(%d+)%.lua")
        if aid then table.insert(appids, tonumber(aid)) end
    end
    table.sort(appids)

    -- batch syntax pass
    local syntax_map = {}
    local sr = C.validate_lua_syntax(0)
    if sr.success then
        for _, r in ipairs(sr.results or {}) do
            local a = (r.filename or ""):match("^(%d+)%.lua")
            if a then syntax_map[tonumber(a)] = r end
        end
    end

    local results = {}
    local totals = { total = #appids, healthy = 0, warnings = 0, errors = 0 }

    for _, appid in ipairs(appids) do
        local entry = { appid = appid, status = "healthy", issues = {} }

        local syn = syntax_map[appid]
        if syn and syn.valid == false then
            local bad_count = syn.badLines and #syn.badLines or 0
            table.insert(entry.issues, "Syntax errors: " .. bad_count .. " bad line(s)")
            entry.status = "error"
        end

        local ok, ar = pcall(C.audit_lua_content, appid)
        if ok and type(ar) == "table" and ar.success then
            local ws = ar.workshop or {}
            local dlc = ar.dlc or {}
            entry.depotCount = ar.depotCount or 0
            entry.gameName = (APP_INFO_CACHE[appid] or {}).name or ""
            if ws.status == "missing" then
                table.insert(entry.issues, "Workshop depot missing")
                if entry.status == "healthy" then entry.status = "warning" end
            end
            local missing_dlc = dlc.missing and #dlc.missing or 0
            if missing_dlc > 0 then
                table.insert(entry.issues, missing_dlc .. " DLC missing")
                if entry.status == "healthy" then entry.status = "warning" end
            end
        end

        if base ~= "" then
            local content = read_lua_file(appid)
            if content then
                local dids = get_depot_ids_from_lua(content)
                local info = fetch_app_info(appid)
                local dd = type(info.depots) == "table" and info.depots or {}
                local manifest_missing, manifest_corrupt = 0, 0
                for _, did in ipairs(dids) do
                    local mid = get_manifest_id(dd, did)
                    if mid and mid ~= "" then
                        local fp = find_manifest_file(base, tostring(did), tostring(mid))
                        if not fp then
                            manifest_missing = manifest_missing + 1
                        elseif not verify_manifest_magic(fp) then
                            manifest_corrupt = manifest_corrupt + 1
                        end
                    end
                end
                if manifest_missing > 0 then
                    table.insert(entry.issues, manifest_missing .. " manifest(s) missing")
                    if entry.status == "healthy" then entry.status = "warning" end
                end
                if manifest_corrupt > 0 then
                    table.insert(entry.issues, manifest_corrupt .. " manifest(s) corrupt (bad magic bytes)")
                    entry.status = "error"
                end
            end
        end

        if entry.status == "healthy" then
            totals.healthy = totals.healthy + 1
        elseif entry.status == "warning" then
            totals.warnings = totals.warnings + 1
        else
            totals.errors = totals.errors + 1
        end

        entry.issues = st.A(entry.issues)
        table.insert(results, entry)
    end

    return { success = true, results = st.A(results), totals = totals }
end

return C
