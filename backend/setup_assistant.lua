-- setup_assistant.lua — first-run setup + quiet self-heal (Windows-native port of setup_assistant.py)

local fs          = require("fs")
local st          = require("st_util")
local health      = require("health")
local unlock_paths = require("unlock_paths")
local logger      = require("plugin_logger")

local M = {}

local MARKER = ".setup_seen"
local SAFE_FIX_IPCS = {
    EnsureStpluginDir = true,
    EnsureLuaScriptDir = true,
    -- InstallOpenSteamTool is Windows-only; never auto-run it on Linux.
    InstallOpenSteamTool = require("platform").is_windows(),
}

local function marker_path()
    return st.data_path(MARKER)
end

function M.has_seen_setup()
    return fs.exists(marker_path())
end

function M.mark_setup_seen()
    local ok = pcall(function()
        st.write_file(marker_path(), "1")
    end)
    if not ok then
        logger.warn("setup_assistant: could not write marker")
    end
    return ok
end

local function classify(report)
    local auto_fixable = {}
    local blockers = {}
    for _, c in ipairs(report.checks or {}) do
        if c.status == "fail" then
            local fix = c.fix
            if fix and fix.ipc and SAFE_FIX_IPCS[fix.ipc] then
                table.insert(auto_fixable, {
                    id = c.id,
                    label = c.label,
                    ipc = fix.ipc,
                    args = fix.args or {},
                })
            else
                table.insert(blockers, {
                    id = c.id,
                    label = c.label,
                    detail = c.detail or "",
                    command = fix and fix.args and fix.args.command or nil,
                })
            end
        end
    end
    return auto_fixable, blockers
end

local function apply_safe_fix(ipc, args)
    if ipc == "EnsureStpluginDir" or ipc == "EnsureLuaScriptDir" then
        local ok, res = pcall(unlock_paths.ensure_lua_script_dir)
        return ok and res == true
    end
    if ipc == "InstallOpenSteamTool" then
        local ok, ost = pcall(require, "opensteamtool_install")
        if not ok or not ost or not ost.install_latest then return false end
        local ok2, res = pcall(ost.install_latest)
        return ok2 and type(res) == "table" and res.success == true
    end
    return false
end

function M.get_setup_state()
    local ok, report = pcall(health.run_health_check, nil, true)
    if not ok or not report or report.success ~= true then
        return { success = false, error = tostring(report) }
    end
    local auto_fixable, blockers = classify(report)
    return {
        success = true,
        firstRun = not M.has_seen_setup(),
        seen = M.has_seen_setup(),
        ready = report.overall ~= "fail",
        overall = report.overall,
        summary = report.summary,
        platform = report.platform,
        autoFixable = auto_fixable,
        blockers = blockers,
    }
end

function M.run_setup()
    local applied = {}
    local ok, report = pcall(health.run_health_check, nil, true)
    if ok and report and report.success then
        local auto_fixable, _ = classify(report)
        for _, fx in ipairs(auto_fixable) do
            if apply_safe_fix(fx.ipc, fx.args) then
                table.insert(applied, fx.label)
                logger.log("setup_assistant: auto-applied " .. tostring(fx.label))
            end
        end
    end
    unlock_paths.invalidate_cache()
    local state = M.get_setup_state()
    state.applied = applied
    return state
end

function M.self_heal()
    local healed = {}
    local platform = require("platform")
    if not M.has_seen_setup() then
        return { success = true, ran = false, healed = healed, platform = platform.name() }
    end
    local ok, res = pcall(unlock_paths.ensure_lua_script_dir)
    if ok and res then
        table.insert(healed, "Ensured unlock script directory")
    end
    return { success = true, ran = true, healed = healed, platform = platform.name() }
end

return M
