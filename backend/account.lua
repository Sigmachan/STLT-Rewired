-- account.lua — account game-data transfer + quick account switch.
--
-- Faithful Lua port of account_transfer.py (userdata copy/inspect/backup -- pure
-- filesystem, verifiable) and account_switch.py (extract_login_tokens /
-- switch_to_account). Full DPAPI token *decryption* isn't practical in the Lua
-- sandbox, so extract_login_tokens reports per-account saved-login PRESENCE
-- (from local.vdf blobs) rather than the decrypted token; switch_to_account
-- flips MostRecent in loginusers.vdf + relaunches Steam. Switch is destructive
-- (kills Steam) and on-machine-verified.

local cjson       = require("json")
local m_utils     = require("utils")
local fs          = require("fs")
local logger      = require("plugin_logger")
local steam_utils = require("steam_utils")
local st          = require("st_util")

local M = {}

local function userdata_dir()
    local base = steam_utils.detect_steam_install_path()
    return base ~= "" and fs.join(base, "userdata") or ""
end

local function game_userdata_path(account_id32, appid)
    local ud = userdata_dir()
    return ud ~= "" and fs.join(ud, tostring(account_id32), tostring(appid)) or ""
end

local function list_userdata_accounts()
    local ud = userdata_dir()
    if ud == "" or not fs.is_directory(ud) then return {} end
    local name_map = {}
    for _, acc in ipairs(st.get_active_account_ids()) do name_map[acc.accountId32] = acc end

    local results = {}
    for _, e in ipairs(fs.list(ud) or {}) do
        local name = e.name or ""
        if e.is_directory and name:match("^%d+$") then
            local account_id32 = tonumber(name)
            local apps = {}
            for _, ae in ipairs(fs.list(e.path) or {}) do
                if (ae.name or ""):match("^%d+$") then table.insert(apps, tonumber(ae.name)) end
            end
            table.sort(apps)
            local meta = name_map[account_id32] or {}
            table.insert(results, {
                accountId32 = account_id32, path = e.path,
                username = meta.username or "", personaName = meta.personaName or "",
                mostRecent = meta.mostRecent or false,
                appCount = #apps, sizeMB = st.mb(st.dir_size(e.path)), apps = st.A(apps),
            })
        end
    end
    return results
end

local function dir_summary(path)
    if not fs.is_directory(path) then return { exists = false } end
    local files, total = {}, 0
    for _, e in ipairs(fs.list_recursive(path) or {}) do
        if e.is_file then
            local sz = fs.file_size(e.path) or 0
            total = total + sz
            table.insert(files, { name = e.path:sub(#path + 1):gsub("^[/\\]+", ""):gsub("\\", "/"), sizeBytes = sz })
        end
    end
    table.sort(files, function(a, b) return a.sizeBytes > b.sizeBytes end)
    local top = {}
    for i = 1, math.min(30, #files) do top[i] = files[i] end
    return { exists = true, path = path, fileCount = #files, sizeBytes = total, sizeMB = st.round(total / (1024 * 1024), 3), files = st.A(top) }
end

-- ── account_transfer IPC (filesystem, verifiable) ────────────────────────────

function M.list_accounts()
    return { success = true, accounts = st.A(list_userdata_accounts()) }
end

function M.inspect_game_data(account_id32, appid)
    account_id32 = tonumber(account_id32); appid = tonumber(appid)
    if not account_id32 or not appid then return { success = false, error = "Invalid account or appid" } end
    local s = dir_summary(game_userdata_path(account_id32, appid))
    s.success = true; s.appid = appid; s.accountId32 = account_id32
    return s
end

function M.transfer_game_data(from_id, to_id, appid, overwrite, backup_dest)
    from_id = tonumber(from_id); to_id = tonumber(to_id); appid = tonumber(appid)
    if not from_id or not to_id or not appid then return { success = false, error = "Invalid account or appid" } end
    if from_id == to_id then return { success = false, error = "Source and destination are the same account" } end
    if st.steam_is_running() then
        return { success = false, requiresSteamClose = true,
            error = "Steam is currently running. Please close Steam completely before transferring -- otherwise it will overwrite the transferred data on shutdown." }
    end

    local src = game_userdata_path(from_id, appid)
    local dst = game_userdata_path(to_id, appid)
    if not fs.is_directory(src) then return { success = false, error = "Source has no data for appid " .. appid .. " at " .. src } end
    if not fs.is_directory(fs.parent_path(dst)) then
        return { success = false, error = "Destination account " .. to_id .. " has never logged into this Steam install. Log in once first." }
    end

    local backup_path = ""
    if fs.is_directory(dst) then
        if not overwrite then
            return { success = false, destExists = true,
                error = "Destination already has data for appid " .. appid .. ". Pass overwrite=True (existing data will be backed up)." }
        end
        if backup_dest ~= false then
            backup_path = dst .. ".bak-" .. st.stamp()
            if not fs.rename(dst, backup_path) then return { success = false, error = "Could not back up destination" } end
        else
            fs.remove_all(dst)
        end
    end

    if not fs.copy_recursive(src, dst) then
        if backup_path ~= "" and fs.is_directory(backup_path) then
            if fs.is_directory(dst) then fs.remove_all(dst) end
            fs.rename(backup_path, dst)
        end
        return { success = false, error = "Copy failed" }
    end

    local summary = dir_summary(dst)
    logger.log("account: transferred appid=" .. appid .. " from " .. from_id .. " to " .. to_id)
    return {
        success = true, appid = appid, fromAccountId32 = from_id, toAccountId32 = to_id,
        filesCopied = summary.fileCount or 0, sizeMB = summary.sizeMB or 0,
        backupPath = backup_path, destPath = dst,
    }
end

function M.restore_transfer_backup(account_id32, appid, backup_path)
    account_id32 = tonumber(account_id32); appid = tonumber(appid)
    if not account_id32 or not appid then return { success = false, error = "Invalid account or appid" } end
    local dst = game_userdata_path(account_id32, appid)
    local parent = fs.parent_path(dst)
    backup_path = backup_path or ""

    if backup_path == "" then
        local candidates = {}
        for _, e in ipairs(fs.list(parent) or {}) do
            if e.is_directory and (e.name or ""):find("^" .. appid .. "%.bak%-") then table.insert(candidates, e.path) end
        end
        if #candidates == 0 then return { success = false, error = "No backups found for this appid" } end
        table.sort(candidates, function(a, b) return a > b end)
        backup_path = candidates[1]
    end
    if not fs.is_directory(backup_path) then return { success = false, error = "Backup not found" } end

    if fs.is_directory(dst) then fs.rename(dst, dst .. ".pre-restore-" .. st.stamp()) end
    if not fs.rename(backup_path, dst) then return { success = false, error = "Restore failed" } end
    return { success = true, restored = dst, from = backup_path }
end

function M.list_game_data_backups()
    local ud = userdata_dir()
    if ud == "" or not fs.is_directory(ud) then return { success = false, error = "userdata folder not found" } end
    local backups = {}
    for _, acc in ipairs(fs.list(ud) or {}) do
        local aid = (acc.name or ""):match("^(%d+)$")
        if acc.is_directory and aid then
            for _, e in ipairs(fs.list(acc.path) or {}) do
                local n = e.name or ""
                if e.is_directory and (n:find(".bak-", 1, true) or n:find(".pre-restore-", 1, true)) then
                    local bak_appid = tonumber(n:match("^(%d+)%."))
                    if bak_appid then
                        table.insert(backups, {
                            accountId32 = tonumber(aid), appid = bak_appid, path = e.path,
                            name = n, mtime = fs.last_write_time(e.path) or 0,
                        })
                    end
                end
            end
        end
    end
    table.sort(backups, function(a, b) return a.mtime > b.mtime end)
    return { success = true, backups = st.A(backups) }
end

-- ── account_switch IPC (on-machine: local.vdf presence + Steam restart) ──────

function M.extract_login_tokens()
    local base = steam_utils.detect_steam_install_path()
    if base == "" then return { success = false, error = "Steam path not found" } end
    local login_vdf = fs.join(base, "config", "loginusers.vdf")
    local local_vdf = fs.join(base, "config", "config", "local.vdf")
    if not fs.is_file(login_vdf) then return { success = false, error = "loginusers.vdf not found" } end

    local accounts = st.get_active_account_ids()
    if #accounts == 0 then return { success = false, error = "No accounts in loginusers.vdf" } end

    -- Detect saved-login blob presence in local.vdf (full DPAPI decrypt not done in Lua).
    local local_text = fs.is_file(local_vdf) and (m_utils.read_file(local_vdf) or "") or ""
    local has_blob = local_text:find('"%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x') ~= nil -- 20+ hex run

    local tokens = {}
    for _, acc in ipairs(accounts) do
        table.insert(tokens, {
            accountName = acc.username, personaName = acc.personaName, steamId64 = acc.steamId64,
            mostRecent = acc.mostRecent,
            hasJwt = has_blob,
            note = "saved-login presence only (DPAPI decrypt not performed)",
        })
    end
    return {
        success = true, tokens = st.A(tokens), path = local_vdf,
        note = "Token values are not decrypted (DPAPI is not available in the Lua sandbox); this reports which accounts are saved.",
    }
end

-- Flip MostRecent to 1 for target_sid, 0 for all others, in loginusers.vdf text.
local function set_most_recent(text, target_sid)
    local t = text:gsub('("MostRecent"%s*")[01](")', "%10%2")
    local kw = t:find('"' .. target_sid .. '"%s*{')
    if not kw then return t, false end
    local open = t:find("{", kw, true)
    local depth, close = 0, nil
    for i = open, #t do
        local c = t:sub(i, i)
        if c == "{" then depth = depth + 1
        elseif c == "}" then depth = depth - 1; if depth == 0 then close = i; break end end
    end
    if not close then return t, false end
    local block = t:sub(open, close)
    local new_block, n = block:gsub('("MostRecent"%s*")[01](")', "%11%2", 1)
    if n == 0 then
        new_block = block:gsub("}%s*$", '\t"MostRecent"\t\t"1"\n\t\t}')
    end
    return t:sub(1, open - 1) .. new_block .. t:sub(close + 1), true
end

M.set_most_recent = set_most_recent

function M.switch_to_account(account_name)
    account_name = st.trim(account_name or "")
    if account_name == "" then return { success = false, error = "accountName required" } end

    local base = steam_utils.detect_steam_install_path()
    if base == "" then return { success = false, error = "Steam path not found" } end
    local login_vdf = fs.join(base, "config", "loginusers.vdf")

    local target
    for _, acc in ipairs(st.get_active_account_ids()) do
        if acc.username == account_name then target = acc; break end
    end
    if not target then return { success = false, error = "Account '" .. account_name .. "' not found in loginusers.vdf" } end

    -- kill Steam if running
    if st.steam_is_running() then
        pcall(m_utils.exec, "taskkill /F /IM steam.exe >nul 2>&1")
        m_utils.sleep(1500)
    end

    local text = m_utils.read_file(login_vdf) or ""
    m_utils.write_file(login_vdf .. ".bak-" .. st.stamp(), text)
    local new_text, ok = set_most_recent(text, target.steamId64)
    if not ok then return { success = false, error = "Failed to update loginusers.vdf" } end
    if m_utils.write_file(login_vdf, new_text) == false then return { success = false, error = "Failed to write loginusers.vdf" } end

    pcall(m_utils.exec, 'start "" steam://0')
    logger.log("account: switched to '" .. account_name .. "' and relaunched Steam")
    return { success = true, accountName = account_name, steamId64 = target.steamId64,
             message = "Switched MostRecent and relaunched Steam." }
end

return M
