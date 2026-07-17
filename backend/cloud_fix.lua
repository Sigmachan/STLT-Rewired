-- cloud_fix.lua — SteamTools cloud-save diagnostic (read-only) + safe quarantine.
--
-- Faithful Lua port of cloud_fix.py (safe subset only): read-only diagnosis of
-- the SteamTools cloud hijack DLLs (xinput1_4/dwmapi) + stella fallback
-- remnants, and reversible quarantine of the obsolete stella files. No binary
-- patching (points users to STFixer for that). SHA256 via PowerShell Get-FileHash.

local m_utils     = require("utils")
local fs          = require("fs")
local logger      = require("plugin_logger")
local steam_utils = require("steam_utils")
local st          = require("st_util")

local M = {}

local KNOWN_GOOD = {
    ["xinput1_4.dll"] = "ddb1f0909c7092f06890674f90b5d4f1198724b05b4bf1e656b4063897340243",
    ["dwmapi.dll"]    = "1ce49ed63af004ad37a4d2921a5659a17001c4c0026d6245fcc0d543e9c265d0",
}
local HIJACK_DLLS = { "xinput1_4.dll", "dwmapi.dll" }
local STELLA_REMNANTS = { "stella_fallback.dll", "stella.cfg" }
local STFIXER_URL = "https://github.com/Selectively11/STFixer"

local function sha256(path)
    local platform = require("platform")
    if platform.is_windows() then
        local ok, out = pcall(m_utils.exec,
            'powershell -NoProfile -Command "(Get-FileHash -LiteralPath \'' .. path .. '\' -Algorithm SHA256).Hash"')
        if ok and out then
            local h = tostring(out):gsub("%s+", "")
            if h:match("^%x+$") and #h >= 40 then return h:lower() end
        end
        return ""
    end
    local ok, out = pcall(m_utils.exec, "sha256sum " .. platform.shell_quote(path) .. " 2>/dev/null | awk '{print $1}'")
    if ok and out then
        local h = tostring(out):gsub("%s+", "")
        if h:match("^%x+$") and #h >= 40 then return h:lower() end
    end
    return ""
end

function M.diagnose_cloud_fix()
    local platform = require("platform")
    if platform.is_linux() then
        return {
            success = true,
            platform = "linux",
            skipped = true,
            message = "SteamTools cloud-hijack DLL checks are Windows-only. On Linux, cloud saves are handled by the unlock stack (SLSsteam/ACCELA).",
            dlls = st.A({}),
            stellaRemnants = st.A({}),
        }
    end
    local root = steam_utils.detect_steam_install_path()
    if not root or root == "" or not fs.is_directory(root) then
        return { success = false, error = "Steam installation not found" }
    end

    local dlls = {}
    for _, name in ipairs(HIJACK_DLLS) do
        local p = fs.join(root, name)
        if fs.is_file(p) then
            local digest = sha256(p)
            table.insert(dlls, {
                name = name, present = true, sha256 = digest,
                isKnownGood = digest ~= "" and digest == (KNOWN_GOOD[name] or ""),
            })
        else
            table.insert(dlls, { name = name, present = false })
        end
    end

    local stella, stella_present = {}, false
    for _, n in ipairs(STELLA_REMNANTS) do
        local pres = fs.is_file(fs.join(root, n))
        if pres then stella_present = true end
        table.insert(stella, { name = n, present = pres })
    end

    local hijack_present, suspicious = false, false
    for _, d in ipairs(dlls) do
        if d.present then
            hijack_present = true
            if not d.isKnownGood then suspicious = true end
        end
    end

    local verdict, recommendation
    if stella_present then
        verdict = "obsolete_fallback_present"
        recommendation = "Obsolete Morrenus/stella fallback remnants found. They are no longer needed " ..
            "and can break cloud saves - use 'Quarantine stella fallback' below (reversible), or run STFixer."
    elseif suspicious then
        verdict = "modified_hijack_dll"
        recommendation = "A SteamTools hijack DLL differs from the known-good build. Run STFixer (" ..
            STFIXER_URL .. ") to repair binary patches - this plugin does not binary-patch for safety."
    elseif hijack_present then
        verdict = "ok_known_good"
        recommendation = "SteamTools cloud helper DLLs look healthy."
    else
        verdict = "no_steamtools_cloud_layer"
        recommendation = "No SteamTools cloud hijack layer detected."
    end

    return {
        success = true, steamPath = root, verdict = verdict, recommendation = recommendation,
        hijackDlls = st.A(dlls), stellaRemnants = st.A(stella), stellaFallbackPresent = stella_present,
        httpCacheDirExists = fs.is_directory(fs.join(root, "appcache", "httpcache", "3b")),
        steamToolsExePresent = fs.is_file(fs.join(root, "SteamTools.exe")),
        stfixerUrl = STFIXER_URL, binaryPatching = false,
    }
end

function M.remove_stella_fallback()
    local root = steam_utils.detect_steam_install_path()
    if not root or root == "" or not fs.is_directory(root) then
        return { success = false, error = "Steam installation not found" }
    end
    if st.steam_is_running() then
        return { success = false, error = "Steam is running - close Steam fully, then retry.", steamRunning = true }
    end

    local targets = {}
    for _, n in ipairs(STELLA_REMNANTS) do
        local p = fs.join(root, n)
        if fs.is_file(p) then table.insert(targets, { name = n, path = p }) end
    end
    if #targets == 0 then
        return { success = true, moved = st.A({}), message = "No stella fallback remnants present - nothing to do." }
    end

    local backup_dir = fs.join(root, "luatools_cloudfix_backup", st.stamp())
    pcall(fs.create_directories, backup_dir)

    local moved, failed = {}, {}
    for _, t in ipairs(targets) do
        if fs.rename(t.path, fs.join(backup_dir, t.name)) then
            table.insert(moved, t.name)
            logger.log("cloud_fix: quarantined " .. t.name)
        else
            table.insert(failed, { file = t.name, error = "move failed" })
        end
    end

    if #moved == 0 and #failed > 0 then
        return { success = false, error = "Failed to move any stella fallback files", failures = st.A(failed) }
    end
    return {
        success = true, moved = st.A(moved), backupDir = backup_dir, failures = st.A(failed),
        message = "Stella fallback quarantined. Restart Steam. Restore from the backup folder if anything misbehaves.",
    }
end

return M
