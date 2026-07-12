-- manifest_auto_updater.lua — keep depotcache manifests current without manual clicks.
--
-- Runs after a successful add and on a throttled schedule when Steam loads.
-- Uses manifests.sync_depotcache (pinned .lua manifests) + manifests.update_manifests
-- (latest public gids from steamcmd).

local manifests = require("manifests")
local st          = require("st_util")
local fs          = require("fs")
local utils       = require("plugin_utils")
local logger      = require("plugin_logger")
local m_utils     = require("utils")
local settings    = require("settings.manager")

local M = {}

local STATE_FILE = "manifest_autoupdate_state.json"
local MIN_INTERVAL_SEC = 6 * 60 * 60
local MAX_APPS_PER_RUN = 8

local function state_path()
    return st.data_path(STATE_FILE)
end

local function read_state()
    local data = utils.read_json(state_path())
    return type(data) == "table" and data or {}
end

local function write_state(data)
    pcall(function()
        utils.write_text(state_path(), require("json").encode(data or {}))
    end)
end

function M.is_enabled()
    local ok, values = pcall(settings._get_values_locked)
    if not ok or type(values) ~= "table" then return true end
    local general = values.general or {}
    if general.autoUpdateManifests == false then return false end
    return true
end

local function list_lua_appids()
    local stplug = st.stplug_dir()
    local out = {}
    if stplug == "" or not fs.is_directory(stplug) then return out end
    for _, e in ipairs(fs.list(stplug) or {}) do
        local aid = (e.name or ""):match("^(%d+)%.lua$")
        if aid then table.insert(out, tonumber(aid)) end
    end
    table.sort(out)
    return out
end

local function tally_manifest_run(sync_res, upd_res)
    local downloaded = 0
    local skipped = 0
    local failed = 0
    if sync_res and sync_res.success then
        downloaded = downloaded + (tonumber(sync_res.fetched) or 0)
        failed = failed + (tonumber(sync_res.failed) or 0)
    end
    if upd_res and upd_res.success and type(upd_res.summary) == "table" then
        downloaded = downloaded + (tonumber(upd_res.summary.downloaded) or 0)
        downloaded = downloaded + (tonumber(upd_res.summary.refreshed) or 0)
        skipped = skipped + (tonumber(upd_res.summary.skipped) or 0)
        failed = failed + (tonumber(upd_res.summary.failed) or 0)
    end
    return downloaded, skipped, failed
end

function M.update_app(appid, reason)
    appid = tonumber(appid)
    if not appid or appid <= 0 then
        return { success = false, error = "invalid appid" }
    end
    if not M.is_enabled() then
        return { success = true, skipped = true, reason = "disabled", appid = appid }
    end

    local sync_res = manifests.sync_depotcache(appid)
    local upd_res = manifests.update_manifests(appid)
    local downloaded, skipped, failed = tally_manifest_run(sync_res, upd_res)

    if reason and reason ~= "" then
        logger.log(string.format(
            "manifest_auto_updater: appid %s (%s) downloaded=%d skipped=%d failed=%d",
            tostring(appid), tostring(reason), downloaded, skipped, failed
        ))
    end

    return {
        success = true,
        appid = appid,
        reason = reason or "",
        downloaded = downloaded,
        skipped = skipped,
        failed = failed,
        sync = sync_res,
        update = upd_res,
    }
end

function M.run_scheduled(force)
    if not M.is_enabled() and force ~= true then
        return { success = true, skipped = true, reason = "disabled" }
    end

    local now = os.time()
    local state = read_state()
    if force ~= true and state.lastRun and (now - tonumber(state.lastRun) or 0) < MIN_INTERVAL_SEC then
        return {
            success = true,
            skipped = true,
            reason = "throttled",
            nextRunInSec = MIN_INTERVAL_SEC - (now - tonumber(state.lastRun)),
        }
    end

    local targets = list_lua_appids()
    if #targets == 0 then
        state.lastRun = now
        state.lastAppCount = 0
        write_state(state)
        return { success = true, processed = 0, downloaded = 0, message = "no lua games" }
    end

    local processed, downloaded, failed = 0, 0, 0
    local details = {}
    for i = 1, math.min(#targets, MAX_APPS_PER_RUN) do
        local aid = targets[i]
        local res = M.update_app(aid, "scheduled")
        processed = processed + 1
        downloaded = downloaded + (tonumber(res.downloaded) or 0)
        failed = failed + (tonumber(res.failed) or 0)
        table.insert(details, {
            appid = aid,
            downloaded = res.downloaded or 0,
            failed = res.failed or 0,
        })
        m_utils.sleep(250)
    end

    state.lastRun = now
    state.lastAppCount = #targets
    state.lastProcessed = processed
    state.lastDownloaded = downloaded
    write_state(state)

    logger.log(string.format(
        "manifest_auto_updater: sweep processed=%d downloaded=%d failed=%d (of %d games)",
        processed, downloaded, failed, #targets
    ))

    return {
        success = true,
        processed = processed,
        totalGames = #targets,
        downloaded = downloaded,
        failed = failed,
        details = st.A(details),
        capped = #targets > MAX_APPS_PER_RUN,
    }
end

return M
