-- history.lua — persistent download-history log.
--
-- Behavioral port of history.py. The Python backend used SQLite; Millennium's
-- Lua sandbox has no sqlite binding, so this uses a JSON store
-- (backend/data/download_history.json) with the SAME record fields, query
-- filters, aggregate stats, and IPC return shapes. Recording hooks
-- (record_start/complete/failure) are provided for the download pipeline.

local cjson   = require("json")
local m_utils = require("utils")
local fs      = require("fs")
local st      = require("st_util")

local M = {}

local FILE = "download_history.json"
local function store_path() return st.data_path(FILE) end

local function load_store()
    local fp = store_path()
    if fs.is_file(fp) then
        local content = m_utils.read_file(fp)
        if content then
            local ok, data = pcall(cjson.decode, content)
            if ok and type(data) == "table" and type(data.records) == "table" then
                data.seq = tonumber(data.seq) or 0
                return data
            end
        end
    end
    return { records = {}, seq = 0 }
end

local function save_store(store)
    st.write_file(store_path(), cjson.encode({ records = st.A(store.records), seq = store.seq or 0 }))
end

local function now() return m_utils.time() end

-- ── recording (for the download pipeline) ────────────────────────────────────

function M.record_start(appid, source, game_name)
    local store = load_store()
    store.seq = (store.seq or 0) + 1
    table.insert(store.records, {
        id = store.seq, appid = tonumber(appid) or 0, game_name = game_name or "",
        source = source or "", status = "downloading", sha256 = "",
        bytes_total = 0, duration_ms = 0, error_msg = "",
        created_at = now(), finished_at = 0, manifest_version = "", metadata = "{}",
    })
    save_store(store)
    return store.seq
end

local function update_record(row_id, fn)
    row_id = tonumber(row_id)
    local store = load_store()
    for _, r in ipairs(store.records) do
        if r.id == row_id then fn(r); break end
    end
    save_store(store)
end

function M.record_complete(row_id, sha256, bytes_total, manifest_version)
    update_record(row_id, function(r)
        local t = now()
        r.status = "complete"
        r.sha256 = sha256 or ""
        r.bytes_total = tonumber(bytes_total) or 0
        r.finished_at = t
        r.duration_ms = math.floor((t - (r.created_at or t)) * 1000)
        r.manifest_version = manifest_version or ""
    end)
end

function M.record_failure(row_id, error_msg)
    update_record(row_id, function(r)
        local t = now()
        r.status = "failed"
        r.error_msg = tostring(error_msg or ""):sub(1, 500)
        r.finished_at = t
        r.duration_ms = math.floor((t - (r.created_at or t)) * 1000)
    end)
end

-- ── queries ──────────────────────────────────────────────────────────────────

function M.get_history(appid, limit, offset, status, source, date_from, date_to)
    appid = tonumber(appid) or 0
    limit = tonumber(limit) or 50
    offset = tonumber(offset) or 0
    status = status or ""
    source = tostring(source or "")
    date_from = tonumber(date_from) or 0
    date_to = tonumber(date_to) or 0

    local store = load_store()
    local matched = {}
    for _, r in ipairs(store.records) do
        local ok = true
        if appid ~= 0 and r.appid ~= appid then ok = false end
        if ok and status ~= "" and r.status ~= status then ok = false end
        if ok and source ~= "" and not tostring(r.source or ""):lower():find(source:lower(), 1, true) then ok = false end
        if ok and date_from ~= 0 and (r.created_at or 0) < date_from then ok = false end
        if ok and date_to ~= 0 and (r.created_at or 0) > date_to then ok = false end
        if ok then table.insert(matched, r) end
    end
    -- newest first (stable by id as tiebreaker)
    table.sort(matched, function(a, b)
        local ca, cb = a.created_at or 0, b.created_at or 0
        if ca == cb then return (a.id or 0) > (b.id or 0) end
        return ca > cb
    end)

    local out = {}
    for i = offset + 1, math.min(#matched, offset + limit) do
        table.insert(out, matched[i])
    end
    return out
end

function M.get_stats()
    local store = load_store()
    local by_status, by_source, unique = {}, {}, {}
    local total_bytes, dur_sum, dur_count = 0, 0, 0
    for _, r in ipairs(store.records) do
        local sstat = r.status or ""
        by_status[sstat] = (by_status[sstat] or 0) + 1
        if sstat == "complete" then
            local src = r.source or ""
            by_source[src] = (by_source[src] or 0) + 1
            total_bytes = total_bytes + (r.bytes_total or 0)
            if (r.duration_ms or 0) > 0 then dur_sum = dur_sum + r.duration_ms; dur_count = dur_count + 1 end
            unique[r.appid or 0] = true
        end
    end
    local uniq = 0
    for _ in pairs(unique) do uniq = uniq + 1 end
    return {
        total_downloads = #store.records,
        by_status = by_status,
        by_source = by_source,
        avg_duration_ms = dur_count > 0 and math.floor(dur_sum / dur_count) or 0,
        total_bytes = total_bytes,
        unique_games = uniq,
    }
end

function M.get_stats_by_source()
    local store = load_store()
    local agg, order = {}, {}
    for _, r in ipairs(store.records) do
        local s = r.source or ""
        if not agg[s] then
            agg[s] = { total = 0, success = 0, failed = 0, kbps_sum = 0, kbps_n = 0, last = nil }
            table.insert(order, s)
        end
        local a = agg[s]
        a.total = a.total + 1
        if r.status == "complete" then
            a.success = a.success + 1
            if (r.duration_ms or 0) > 0 and (r.bytes_total or 0) > 0 then
                a.kbps_sum = a.kbps_sum + (r.bytes_total / r.duration_ms)
                a.kbps_n = a.kbps_n + 1
            end
            if r.finished_at and (a.last == nil or r.finished_at > a.last) then a.last = r.finished_at end
        elseif r.status == "failed" then
            a.failed = a.failed + 1
        end
    end
    local result = {}
    for _, s in ipairs(order) do
        local a = agg[s]
        local avg = a.kbps_n > 0 and st.round(a.kbps_sum / a.kbps_n, 1) or 0
        result[s] = {
            total = a.total,
            success = a.success,
            failed = a.failed,
            success_rate = a.total > 0 and st.round(a.success / a.total, 3) or st.null,
            avg_speed_kbps = (avg ~= 0) and avg or st.null,
            last_success_at = a.last ~= nil and a.last or st.null,
        }
    end
    return result
end

function M.prune_history(days)
    days = math.max(1, math.floor(tonumber(days) or 30))
    local cutoff = now() - days * 86400
    local store = load_store()
    local total_before = #store.records

    -- most-recent id per appid is never deleted
    local max_id = {}
    for _, r in ipairs(store.records) do
        local a = r.appid or 0
        if not max_id[a] or (r.id or 0) > max_id[a] then max_id[a] = r.id or 0 end
    end

    local kept, oldest = {}, nil
    for _, r in ipairs(store.records) do
        local keep = true
        if (r.created_at or 0) < cutoff and (r.id or 0) ~= max_id[r.appid or 0] then keep = false end
        if keep then
            table.insert(kept, r)
            if oldest == nil or (r.created_at or 0) < oldest then oldest = r.created_at end
        end
    end
    store.records = kept
    save_store(store)
    return {
        success = true,
        deleted = total_before - #kept,
        kept = #kept,
        oldest_kept_at = oldest ~= nil and oldest or st.null,
    }
end

-- ── IPC wrappers ─────────────────────────────────────────────────────────────

function M.get_download_history_json(appid, limit, status, source, date_from, date_to)
    local ok, rows = pcall(M.get_history, appid, limit, 0, status, source, date_from, date_to)
    if not ok then return { success = false, error = tostring(rows) } end
    return { success = true, history = st.A(rows), count = #rows }
end

function M.prune_history_json(days)
    local ok, res = pcall(M.prune_history, days)
    if not ok then return { success = false, error = tostring(res) } end
    return res
end

function M.get_download_stats_json()
    local ok, res = pcall(M.get_stats)
    if not ok then return { success = false, error = tostring(res) } end
    return { success = true, stats = res }
end

return M
