-- batch.lua — batch download pipeline (poll-driven scheduler).
--
-- Behavioral port of batch.py. Python used a ThreadPoolExecutor; Millennium's
-- Lua is single-threaded, but the download itself (downloads.start_add_via_luatools)
-- is already fire-and-forget (detached process, status via a state file). So the
-- batch is driven by polling: each GetBatchStatus call advances the scheduler --
-- reaps finished downloads (with retry), then fills free slots up to `parallel`.
-- State persists in this module (loaded once) + batch_queue.json for recovery.

local cjson       = require("json")
local m_utils     = require("utils")
local fs          = require("fs")
local logger      = require("plugin_logger")
local steam_utils = require("steam_utils")
local st          = require("st_util")

local M = {}

local state = {
    active = false, batch_id = "", queue = {}, results = {},
    config = { parallel = 3, max_retries = 2, delay_between_s = 1.0 },
    started_at = 0, finished_at = 0, cancelled = false, paused = false, skipped = {},
}

local function queue_path() return st.data_path("batch_queue.json") end

local function save_queue()
    pcall(function()
        st.write_file(queue_path(), cjson.encode({
            batch_id = state.batch_id, queue = st.A(state.queue), config = state.config,
        }))
    end)
end

local function load_queue()
    local p = queue_path()
    if not fs.is_file(p) then return nil end
    local ok, data = pcall(cjson.decode, m_utils.read_file(p) or "")
    if ok and type(data) == "table" then return data end
    return nil
end

local function clear_queue_file() pcall(fs.remove, queue_path()) end

local function emit(event, data)
    pcall(function()
        local ev = require("events")
        if type(ev.emit) == "function" then ev.emit(event, data) end
    end)
end

-- Scheduler tick: reap finished downloads (+retry), then fill free slots.
function M._advance()
    if not state.active then return end
    local dl = require("downloads")

    if state.cancelled then
        for _, item in ipairs(state.queue) do
            if item.status == "queued" then
                item.status = "cancelled"
                state.results[tostring(item.appid)] = { status = "cancelled" }
            end
        end
    end

    for _, item in ipairs(state.queue) do
        if item.status == "downloading" then
            local ok, r = pcall(dl.get_add_status, item.appid)
            local status = (ok and type(r) == "table" and type(r.state) == "table") and r.state.status or nil
            if status == "done" then
                item.status = "done"
                state.results[tostring(item.appid)] = { status = "done", source = r.state.currentApi or "unknown" }
                emit("batch.progress", { appid = item.appid })
            elseif status == "failed" then
                if item.retries_left > 0 then
                    item.retries_left = item.retries_left - 1
                    item.status = "queued"
                    logger.log("batch: retry for " .. item.appid .. " (" .. item.retries_left .. " left)")
                else
                    item.status = "failed"
                    state.results[tostring(item.appid)] = { status = "failed", error = (r.state.error or "Unknown failure") }
                    emit("batch.progress", { appid = item.appid })
                end
            end
        end
    end

    if not state.paused and not state.cancelled then
        local active_count = 0
        for _, item in ipairs(state.queue) do if item.status == "downloading" then active_count = active_count + 1 end end
        local slots = state.config.parallel - active_count
        for _, item in ipairs(state.queue) do
            if slots <= 0 then break end
            if item.status == "queued" then
                item.status = "downloading"
                pcall(dl.start_add_via_luatools, item.appid)
                slots = slots - 1
            end
        end
    end

    save_queue()

    local all_terminal = true
    for _, item in ipairs(state.queue) do
        local s = item.status
        if not (s == "done" or s == "failed" or s == "cancelled" or s == "skipped") then
            all_terminal = false; break
        end
    end
    if all_terminal then
        state.active = false
        state.finished_at = m_utils.time()
        clear_queue_file()
        local done, failed = 0, 0
        for _, v in pairs(state.results) do
            if v.status == "done" then done = done + 1 elseif v.status == "failed" then failed = failed + 1 end
        end
        emit("batch.complete", { batch_id = state.batch_id, total = #state.queue, success = done, failed = failed })
        logger.log("batch: complete - " .. done .. "/" .. #state.queue .. " ok, " .. failed .. " failed")
    end
end

function M.start_batch(appids, parallel, max_retries, delay, priority_appids, skip_installed, force)
    if state.active then
        return { success = false, error = "Batch already running", batch_id = state.batch_id }
    end
    parallel = math.max(1, math.min(8, math.floor(tonumber(parallel) or 3)))
    max_retries = math.floor(tonumber(max_retries) or 2)
    delay = tonumber(delay) or 1.0
    if skip_installed == nil then skip_installed = true end

    local raw = 0
    local seen, unique = {}, {}
    for _, a in ipairs(appids or {}) do
        raw = raw + 1
        a = tonumber(a)
        if a and not seen[a] then seen[a] = true; table.insert(unique, a) end
    end
    local dedup_count = #unique

    local skipped_installed = {}
    if skip_installed and not force then
        local to_queue = {}
        for _, a in ipairs(unique) do
            local ok, has = pcall(steam_utils.has_lua_for_app, a)
            if ok and has == true then table.insert(skipped_installed, a) else table.insert(to_queue, a) end
        end
        unique = to_queue
    end

    local prio = {}
    for _, a in ipairs(priority_appids or {}) do prio[tonumber(a)] = true end
    local queue = {}
    for _, appid in ipairs(unique) do
        table.insert(queue, {
            appid = appid, priority = prio[appid] and 0 or 1,
            retries_left = max_retries, status = "queued",
        })
    end
    table.sort(queue, function(a, b) return a.priority < b.priority end)

    state.active = true
    state.batch_id = "batch_" .. math.floor(m_utils.time()) .. "_" .. #queue
    state.queue = queue
    state.results = {}
    state.config = { parallel = parallel, max_retries = max_retries, delay_between_s = delay }
    state.started_at = m_utils.time()
    state.finished_at = 0
    state.cancelled = false
    state.paused = false
    state.skipped = skipped_installed
    save_queue()

    emit("batch.start", { batch_id = state.batch_id, total = #queue, parallel = parallel })
    M._advance()

    return {
        success = true, batch_id = state.batch_id, queued = #queue,
        skipped_installed = #skipped_installed, deduplicated = raw - dedup_count,
    }
end

function M.get_batch_status()
    if state.active then M._advance() end
    if not state.active and not next(state.results) then
        return { success = true, active = false }
    end

    local done, failed, skipped_ui = 0, 0, 0
    for _, v in pairs(state.results) do
        if v.status == "done" then done = done + 1
        elseif v.status == "failed" then failed = failed + 1
        elseif v.status == "skipped" then skipped_ui = skipped_ui + 1 end
    end
    local active, queued = 0, 0
    for _, item in ipairs(state.queue) do
        if item.status == "downloading" then active = active + 1
        elseif item.status == "queued" then queued = queued + 1 end
    end
    local elapsed = state.started_at > 0 and (m_utils.time() - state.started_at) or 0
    local completed = done + failed
    local eta = 0
    if completed > 0 and (queued + active) > 0 then eta = math.floor((elapsed / completed) * (queued + active)) end

    return {
        success = true, active = state.active, paused = state.paused, batch_id = state.batch_id,
        total = #state.queue, done = done, failed = failed, skipped = skipped_ui,
        active_downloads = active, queued = queued,
        elapsed_s = math.floor(elapsed), eta_s = eta,
        cancelled = state.cancelled, skipped_installed = st.A(state.skipped), results = state.results,
    }
end

function M.cancel_batch()
    if not state.active then return { success = false, error = "No batch running" } end
    state.cancelled = true
    return { success = true }
end

function M.pause_batch()
    if not state.active then return { success = false, error = "No batch running" } end
    if state.paused then return { success = false, error = "Batch already paused" } end
    state.paused = true
    return { success = true, message = "Batch paused - active downloads will complete" }
end

function M.unpause_batch()
    if not state.active then return { success = false, error = "No batch running" } end
    if not state.paused then return { success = false, error = "Batch is not paused" } end
    state.paused = false
    return { success = true, message = "Batch resumed" }
end

function M.skip_batch_item(appid)
    appid = tonumber(appid)
    if not state.active then return { success = false, error = "No batch running" } end
    for _, item in ipairs(state.queue) do
        if item.appid == appid and item.status == "queued" then
            item.status = "skipped"
            state.results[tostring(appid)] = { status = "skipped", error = "Skipped by user" }
            return { success = true, appid = appid }
        end
    end
    return { success = false, error = "AppID " .. tostring(appid) .. " not in queue or not queued" }
end

function M.resume_batch()
    local saved = load_queue()
    if not saved or type(saved.queue) ~= "table" or #saved.queue == 0 then
        return { success = false, error = "No saved queue found" }
    end
    local remaining = {}
    for _, item in ipairs(saved.queue) do
        if item.status == "queued" or item.status == "downloading" then
            table.insert(remaining, item.appid)
        end
    end
    if #remaining == 0 then
        clear_queue_file()
        return { success = false, error = "All items already processed" }
    end
    local cfg = saved.config or {}
    return M.start_batch(remaining, cfg.parallel or 3, cfg.max_retries or 2, cfg.delay_between_s or 1.0)
end

return M
