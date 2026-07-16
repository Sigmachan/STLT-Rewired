-- profiles.lua — per-game configuration profiles.
--
-- Faithful Lua port of profiles.py. A profile is a named snapshot of a game's
-- .lua activation script (+ optional launch options). Stored under
-- backend/data/profiles/<appid>/<slug>.json with an active.json pointer.
-- Activating rewrites the .lua (pre-activate backup kept). Launch-option apply
-- reuses tokeer_launcher when present; otherwise it's skipped gracefully.

local cjson       = require("json")
local m_utils     = require("utils")
local fs          = require("fs")
local logger      = require("plugin_logger")
local steam_utils = require("steam_utils")
local st          = require("st_util")

local M = {}

-- ── storage paths ────────────────────────────────────────────────────────────

local function profiles_root()
    local p = st.data_path("profiles")
    if not fs.exists(p) then pcall(fs.create_directories, p) end
    return p
end

local function profile_dir(appid)
    local p = fs.join(profiles_root(), tostring(appid))
    if not fs.exists(p) then pcall(fs.create_directories, p) end
    return p
end

local function active_path() return fs.join(profiles_root(), "active.json") end

local function slugify(name)
    local s = st.trim(name):gsub("[^%w_%-]+", "_")
    s = s:gsub("^_+", ""):gsub("_+$", "")
    if s == "" then return "profile" end
    return s:sub(1, 64)
end

-- ── lua + launch-options snapshots ───────────────────────────────────────────

local function lua_path(appid)
    local dir = st.lua_script_dir()
    if dir == "" then return "" end
<<<<<<< HEAD
    return fs.join(dir, tostring(appid) .. ".lua")
=======
    return fs.join(dir, appid .. ".lua")
>>>>>>> f7770ef (fix: prefer SteamTools unlock backend and unify script paths)
end

local function read_lua_snapshot(appid)
    local p = lua_path(appid)
    if p == "" or not fs.is_file(p) then return nil end
    return m_utils.read_file(p)
end

local function write_lua_snapshot(appid, content)
    local p = lua_path(appid)
    if p == "" then return false end
    local ok = m_utils.write_file(p, content or "")
    return ok ~= false
end

local function localconfig_path(account_id32)
    local base = steam_utils.detect_steam_install_path()
    if not base or base == "" then return "" end
    return fs.join(base, "userdata", tostring(account_id32), "config", "localconfig.vdf")
end

local function read_launch_options(appid, account_id32)
    local p = localconfig_path(account_id32)
    if p == "" or not fs.is_file(p) then return "" end
    local text = m_utils.read_file(p) or ""
    local apps = text:match('"apps"%s*{(.-)\n%s*}%s*\n')
    if not apps then return "" end
    local body = apps:match('"%s*' .. appid .. '%s*"%s*{(.-)\n%s*}%s*\n')
    if not body then return "" end
    return body:match('"LaunchOptions"%s*"([^"]*)"') or ""
end

-- ── active pointer ───────────────────────────────────────────────────────────

local function read_active()
    local p = active_path()
    if not fs.is_file(p) then return {} end
    local ok, data = pcall(cjson.decode, m_utils.read_file(p) or "")
    if ok and type(data) == "table" then return data end
    return {}
end

local function write_active(data)
    m_utils.write_file(active_path(), cjson.encode(data))
end

-- ── public IPC ───────────────────────────────────────────────────────────────

function M.list_profiles_for(appid)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "invalid appid" } end
    local pdir = profile_dir(appid)
    if not fs.is_directory(pdir) then
        return { success = true, appid = appid, profiles = st.A({}), active = st.null }
    end
    local active_map = read_active()
    local active_slug = active_map[tostring(appid)]

    local profiles = {}
    for _, e in ipairs(fs.list(pdir) or {}) do
        local fname = e.name or ""
        if fname:match("%.json$") then
            local slug = fname:sub(1, #fname - 5)
            local ok, data = pcall(cjson.decode, m_utils.read_file(e.path) or "")
            if ok and type(data) == "table" then
                local lua_content = data.luaContent or ""
                local lo = data.launchOptions or ""
                table.insert(profiles, {
                    slug = slug,
                    name = data.name or slug,
                    description = data.description or "",
                    createdAt = data.createdAt or 0,
                    luaLength = #tostring(lua_content),
                    hasLaunchOptions = (lo ~= nil and lo ~= "") and true or false,
                    launchOptionsPreview = tostring(lo):sub(1, 80),
                    active = (slug == active_slug),
                })
            end
        end
    end
    table.sort(profiles, function(a, b)
        if a.active ~= b.active then return a.active end
        return (a.createdAt or 0) > (b.createdAt or 0)
    end)

    return {
        success = true, appid = appid, profiles = st.A(profiles),
        active = active_slug ~= nil and active_slug or st.null,
    }
end

function M.save_profile(appid, name, description, account_id32)
    appid = tonumber(appid)
    account_id32 = tonumber(account_id32) or 0
    if not appid then return { success = false, error = "invalid appid or accountId32" } end

    name = st.trim(name or "")
    if name == "" then return { success = false, error = "name required" } end

    local slug = slugify(name)
    local lua_content = read_lua_snapshot(appid)
    if lua_content == nil then
        return { success = false, error = ".lua file for AppID " .. appid .. " not found" }
    end
    local launch_options = account_id32 ~= 0 and read_launch_options(appid, account_id32) or ""

    local data = {
        appid = appid, slug = slug, name = name, description = description or "",
        createdAt = math.floor(m_utils.time()),
        luaContent = lua_content, launchOptions = launch_options,
        snapshotAccountId32 = account_id32,
    }
    local path = fs.join(profile_dir(appid), slug .. ".json")
    local ok = m_utils.write_file(path, cjson.encode(data))
    if ok == false then return { success = false, error = "write failed" } end

    logger.log("profiles: saved '" .. name .. "' for appid " .. appid)
    return {
        success = true, appid = appid, slug = slug, name = name,
        luaLength = #lua_content, hasLaunchOptions = launch_options ~= "",
    }
end

function M.activate_profile(appid, slug, apply_launch_options, account_id32)
    appid = tonumber(appid)
    account_id32 = tonumber(account_id32) or 0
    if not appid then return { success = false, error = "invalid args" } end
    local apply_lo = apply_launch_options ~= false

    slug = st.trim(slug or "")
    if slug == "" then return { success = false, error = "slug required" } end

    local profile_path = fs.join(profile_dir(appid), slug .. ".json")
    if not fs.is_file(profile_path) then return { success = false, error = "profile not found" } end
    local okp, profile = pcall(cjson.decode, m_utils.read_file(profile_path) or "")
    if not okp or type(profile) ~= "table" then return { success = false, error = "profile read failed" } end

    -- backup current state
    local backup_name = ".pre-activate-" .. math.floor(m_utils.time())
    local backup_path = fs.join(profile_dir(appid), backup_name .. ".json")
    local current_lua = read_lua_snapshot(appid) or ""
    local current_lo = account_id32 ~= 0 and read_launch_options(appid, account_id32) or ""
    pcall(function()
        m_utils.write_file(backup_path, cjson.encode({
            appid = appid, slug = backup_name, name = "(pre-activate backup)",
            description = "Auto-backup before activating '" .. (profile.name or slug) .. "'",
            createdAt = math.floor(m_utils.time()),
            luaContent = current_lua, launchOptions = current_lo,
            snapshotAccountId32 = account_id32,
        }))
    end)

    if not write_lua_snapshot(appid, profile.luaContent or "") then
        return { success = false, error = "lua write failed" }
    end

    local lo_applied, lo_skipped_reason = false, ""
    if apply_lo and account_id32 ~= 0 and profile.launchOptions and profile.launchOptions ~= "" then
        if st.steam_is_running() then
            lo_skipped_reason = "Steam is running - launch options will be overwritten on exit, skipped"
        else
            local ok_tk, tk = pcall(require, "tokeer")
            if ok_tk and type(tk) == "table" and type(tk.set_launch_options) == "function" then
                local ok = pcall(function()
                    local lc_path = localconfig_path(account_id32)
                    if lc_path ~= "" and fs.is_file(lc_path) then
                        local lc_text = m_utils.read_file(lc_path) or ""
                        local new_text, action = tk.set_launch_options(lc_text, appid, profile.launchOptions)
                        if action ~= "no_file" and action ~= "no_apps_section" then
                            m_utils.write_file(lc_path .. ".bak-" .. st.stamp(), lc_text)
                            m_utils.write_file(lc_path, new_text)
                            lo_applied = true
                        end
                    end
                end)
                if not ok then lo_skipped_reason = "launch options write failed" end
            else
                lo_skipped_reason = "launch options unsupported (tokeer not available)"
            end
        end
    end

    local active = read_active()
    active[tostring(appid)] = slug
    write_active(active)

    logger.log("profiles: activated '" .. (profile.name or slug) .. "' for appid " .. appid)
    return {
        success = true, appid = appid, slug = slug, name = profile.name or slug,
        luaApplied = true, launchOptionsApplied = lo_applied,
        launchOptionsSkippedReason = lo_skipped_reason, backupPath = backup_path,
    }
end

function M.delete_profile(appid, slug)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "invalid appid" } end
    slug = st.trim(slug or "")
    if slug == "" then return { success = false, error = "slug required" } end

    local path = fs.join(profile_dir(appid), slug .. ".json")
    if not fs.is_file(path) then return { success = false, error = "profile not found" } end
    local ok = pcall(fs.remove, path)
    if not ok then return { success = false, error = "delete failed" } end

    local active = read_active()
    if active[tostring(appid)] == slug then
        active[tostring(appid)] = nil
        write_active(active)
    end
    return { success = true, slug = slug }
end

function M.list_all_profiles()
    local root = profiles_root()
    if not fs.is_directory(root) then
        return { success = true, appids = st.A({}), totalProfiles = 0 }
    end
    local active_map = read_active()
    local out, total = {}, 0
    for _, e in ipairs(fs.list(root) or {}) do
        local name = e.name or ""
        if e.is_directory and name:match("^%d+$") then
            local appid = tonumber(name)
            local slugs = {}
            for _, pe in ipairs(fs.list(e.path) or {}) do
                local pn = pe.name or ""
                if pn:match("%.json$") and not pn:find("^%.pre%-activate%-") then
                    table.insert(slugs, pn:sub(1, #pn - 5))
                end
            end
            if #slugs > 0 then
                total = total + #slugs
                table.sort(slugs)
                table.insert(out, {
                    appid = appid, profileCount = #slugs,
                    activeSlug = active_map[tostring(appid)] ~= nil and active_map[tostring(appid)] or st.null,
                    slugs = st.A(slugs),
                })
            end
        end
    end
    return { success = true, appids = st.A(out), totalProfiles = total }
end

return M
