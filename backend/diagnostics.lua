-- diagnostics.lua — per-app health report + shareable text export.
--
-- Faithful Lua port of steamtools.py diagnose_app / export_diagnostic_report,
-- composing the already-ported validate/audit/manifest/update-lock pieces plus a
-- Goldberg/conflicting-file signature scan (incl. a Goldberg PE-string check).
-- NOT ported: _windows_denuvo_diagnostics (SAC/Defender probing) and the
-- _UNRELEASED_GAMES special-case table.

local m_utils     = require("utils")
local fs          = require("fs")
local steam_utils = require("steam_utils")
local st          = require("st_util")
local plugin_utils = require("plugin_utils")
local lua_tools   = require("lua_tools")
local acf_lock    = require("acf_lock")

local M = {}

local GB_SIGS = {
    "steam_settings", "steam_interfaces.txt", "coldclientloader.ini", "ColdClientLoader.ini",
    "local_save.txt", "configs.user.ini", "steam_api.dll.bak", "steam_api64.dll.bak",
}
local CONFLICTING_FILES = {
    "winmm.dll", "xinput1_3.dll", "xinput1_4.dll", "xinput9_1_0.dll", "dinput8.dll",
    "winhttp.dll", "iphlpapi.dll", "dsound.dll", "cream_api.ini", "steam_api_o.dll",
    "steam_api64_o.dll", "steamclient_loader.exe", "codex.cfg", "codex64.dll",
    "3dmgame.dll", "ali213.ini", "valve.ini", "hlm.ini", "denuvo.dll",
    "unsteam.ini", "unsteam.dll",
}

local GB_SET, CF_SET = {}, {}
for _, s in ipairs(GB_SIGS) do GB_SET[s:lower()] = true end
for _, s in ipairs(CONFLICTING_FILES) do CF_SET[s:lower()] = true end

local function relp(path, root)
    local r = root:gsub("[/\\]+$", "")
    local p = path
    if p:sub(1, #r):lower() == r:lower() then p = p:sub(#r + 1) end
    return (p:gsub("^[/\\]+", ""))
end

-- Scan install dir (bounded depth 3) for Goldberg + conflicting signatures.
local function scan_install(ip)
    local gb, cf = {}, {}
    local function recurse(dir, depth)
        if depth > 3 then return end
        for _, e in ipairs(fs.list(dir) or {}) do
            local lname = (e.name or ""):lower()
            if e.is_directory then
                if GB_SET[lname] then table.insert(gb, relp(e.path, ip) .. "/") end
                recurse(e.path, depth + 1)
            elseif e.is_file then
                if GB_SET[lname] then table.insert(gb, relp(e.path, ip)) end
                if CF_SET[lname] then table.insert(cf, relp(e.path, ip)) end
                if lname == "steam_api.dll" or lname == "steam_api64.dll" then
                    local f = io.open(e.path, "rb")
                    if f then
                        local header = f:read(65536) or ""
                        f:close()
                        if header:find("Goldberg", 1, true) or header:find("goldberg", 1, true) then
                            table.insert(gb, relp(e.path, ip) .. " (patched DLL)")
                        end
                    end
                end
                if lname:find("unsteam", 1, true) then
                    local rel = relp(e.path, ip)
                    local dup = false
                    for _, x in ipairs(cf) do if x == rel then dup = true; break end end
                    if not dup then table.insert(cf, rel) end
                end
            end
        end
    end
    recurse(ip, 0)
    return gb, cf
end

local function cap20(list)
    local out = {}
    for i = 1, math.min(20, #list) do out[i] = list[i] end
    return out
end

function M.diagnose_app(appid)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "Invalid appid" } end
    local base = st.steam_path()
    if base == "" then return { success = false, error = "Steam path not found" } end

    local report = {
        appid = appid, gameName = "", installed = false, installPath = "", folderSizeMB = 0,
        luaFile = { found = false, path = "", syntaxValid = st.null, disabled = false },
        goldberg = { detected = false, files = st.A({}) },
        conflictingFiles = st.A({}), updatesDisabled = false,
        manifestStatus = { total = 0, present = 0, missing = 0, corrupt = 0 },
        contentAudit = st.null,
        fixesAvailable = { generic = false, online = false },
    }

    local pr = steam_utils.get_game_install_path_response(appid)
    local ip = ""
    if pr.success then
        ip = pr.installPath or ""
        report.installed = true
        report.installPath = ip
    end
    if ip ~= "" and fs.is_directory(ip) then
        report.folderSizeMB = st.round(st.dir_size(ip) / (1024 * 1024), 2)
        local gb, cf = scan_install(ip)
        if #gb > 0 then report.goldberg = { detected = true, files = st.A(cap20(gb)) } end
        if #cf > 0 then report.conflictingFiles = st.A(cap20(cf)) end
    end

    -- update-lock (reuse acf_lock)
    local okl, lk = pcall(acf_lock.get_game_update_lock_status, appid)
    if okl and type(lk) == "table" and lk.success then
        report.updatesDisabled = (lk.autoUpdateBehavior == "1" or lk.autoUpdateBehavior == "2") or (lk.readOnly == true)
    end

    -- lua file
    local stplug = st.stplug_dir()
    for _, pair in ipairs({ { ".lua", false }, { ".lua.disabled", true } }) do
        local p = stplug ~= "" and fs.join(stplug, appid .. pair[1]) or ""
        if p ~= "" and fs.is_file(p) then
            report.luaFile = { found = true, path = p, syntaxValid = st.null, disabled = pair[2] }
            break
        end
    end

    if report.luaFile.found then
        local okv, sr = pcall(lua_tools.validate_lua_syntax, appid)
        if okv and type(sr) == "table" and sr.success then
            local all_valid = true
            for _, r in ipairs(sr.results or {}) do if not r.valid then all_valid = false; break end end
            report.luaFile.syntaxValid = all_valid
        end
        local oka, ar = pcall(lua_tools.audit_lua_content, appid)
        if oka and type(ar) == "table" and ar.success then
            report.contentAudit = { workshop = ar.workshop or {}, dlc = ar.dlc or {}, depotCount = ar.depotCount or 0 }
        end

        local content = st.read_lua_file(appid)
        if content then
            local dids = st.get_depot_ids_from_lua(content)
            local info = st.fetch_app_info(appid)
            if info.name and info.name ~= "" then report.gameName = info.name end
            local dd = info.depots or {}
            local t, p2, mi, corrupt = 0, 0, 0, 0
            for _, did in ipairs(dids) do
                local mid = st.get_manifest_id(dd, did)
                if mid and mid ~= "" then
                    t = t + 1
                    local fp = st.find_manifest_file(base, tostring(did), tostring(mid))
                    if fp then
                        if st.verify_manifest_magic(fp) then p2 = p2 + 1 else corrupt = corrupt + 1 end
                    else
                        mi = mi + 1
                    end
                end
            end
            report.manifestStatus = { total = t, present = p2, missing = mi, corrupt = corrupt }
        end
    end

    return { success = true, report = report }
end

function M.export_diagnostic_report(appid)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "Invalid appid" } end
    local raw = M.diagnose_app(appid)
    if not raw.success then return raw end
    local r = raw.report

    local lines = {
        "=== LuaTools Diagnostic Report ===",
        "AppID:        " .. tostring(r.appid or "?"),
        "Game:         " .. (r.gameName ~= "" and r.gameName or "Unknown"),
        "Installed:    " .. (r.installed and "Yes" or "No"),
    }
    if r.installed then
        table.insert(lines, "Path:         " .. tostring(r.installPath or "?"))
        table.insert(lines, "Folder Size:  " .. tostring(r.folderSizeMB or 0) .. " MB")
    end

    local lua = r.luaFile or {}
    table.insert(lines, "Lua File:     " .. (lua.found and "Found" or "Missing") ..
        (lua.disabled and " (DISABLED)" or ""))
    if lua.found then
        local sv = lua.syntaxValid
        local sv_txt = "Not checked"
        if sv == true then sv_txt = "Valid" elseif sv == false then sv_txt = "Errors" end
        table.insert(lines, "Syntax:       " .. sv_txt)
    end

    local ca = r.contentAudit
    if type(ca) == "table" then
        local ws = ca.workshop or {}
        local dlc = ca.dlc or {}
        local inc = type(dlc.included) == "table" and #dlc.included or 0
        local miss = type(dlc.missing) == "table" and #dlc.missing or 0
        table.insert(lines, "Depots:       " .. tostring(ca.depotCount or 0))
        table.insert(lines, "Workshop:     " .. tostring(ws.label or "?"))
        table.insert(lines, "DLC Included: " .. inc)
        table.insert(lines, "DLC Missing:  " .. miss)
    end

    local ms = r.manifestStatus or {}
    if (ms.total or 0) > 0 then
        local parts = {}
        if (ms.missing or 0) > 0 then table.insert(parts, ms.missing .. " missing") end
        if (ms.corrupt or 0) > 0 then table.insert(parts, ms.corrupt .. " corrupt") end
        local suffix = #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or " OK"
        table.insert(lines, "Manifests:    " .. (ms.present or 0) .. "/" .. (ms.total or 0) .. " present" .. suffix)
    end

    local gb = r.goldberg or {}
    table.insert(lines, "Goldberg:     " .. (gb.detected and "Detected (!)" or "Not found"))
    table.insert(lines, "Updates Off:  " .. (r.updatesDisabled and "Yes" or "No"))

    local fx = r.fixesAvailable or {}
    local fixes_parts = {}
    if fx.generic then table.insert(fixes_parts, "Generic") end
    if fx.online then table.insert(fixes_parts, "Online") end
    table.insert(lines, "Fixes Avail:  " .. (#fixes_parts > 0 and table.concat(fixes_parts, ", ") or "None"))
    table.insert(lines, "================================")
    local ver = "0"
    pcall(function() ver = plugin_utils.get_plugin_version() end)
    table.insert(lines, "STLT - Rewired v" .. ver)

    return { success = true, text = table.concat(lines, "\n"), appid = appid }
end

return M
