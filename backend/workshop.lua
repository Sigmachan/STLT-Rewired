-- workshop.lua — Steam Workshop content manager for .lua-activated games.
--
-- Faithful Lua port of workshop_manager.py: read subscriptions from
-- localconfig.vdf, cross-reference on-disk content, and download items directly
-- via the public ISteamRemoteStorage/GetPublishedFileDetails API (bypassing the
-- Steam client's ownership check). ZIP items are unpacked with PowerShell.

local cjson       = require("json")
local m_utils     = require("utils")
local fs          = require("fs")
local http_client = require("http_client")
local logger      = require("plugin_logger")
local steam_utils = require("steam_utils")
local st          = require("st_util")

local M = {}

local PUBLISHED_FILE_DETAILS_URL =
    "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"

local function workshop_content_dir(appid)
    local base = steam_utils.detect_steam_install_path()
    if not base or base == "" then return "" end
    return fs.join(base, "steamapps", "workshop", "content", tostring(appid))
end

local function localconfig_path(account_id32)
    local base = steam_utils.detect_steam_install_path()
    if not base or base == "" then return "" end
    return fs.join(base, "userdata", tostring(account_id32), "config", "localconfig.vdf")
end

-- Best-effort parse of Workshop subscriptions for an appid from localconfig.vdf.
local function parse_subscribed_items(account_id32, appid)
    local p = localconfig_path(account_id32)
    if p == "" or not fs.is_file(p) then return {} end
    local text = m_utils.read_file(p) or ""
    local astart = text:find('"' .. tostring(appid) .. '"%s*{')
    if not astart then return {} end
    local win = text:sub(astart)
    local sub_pos = win:find('"Subscriptions"%s*{')
    if not sub_pos then return {} end
    -- brace-count from the Subscriptions '{' to its matching '}' (nested VDF)
    local open_pos = win:find("{", sub_pos, true)
    local depth, close_pos = 0, nil
    for i = open_pos, #win do
        local c = win:sub(i, i)
        if c == "{" then
            depth = depth + 1
        elseif c == "}" then
            depth = depth - 1
            if depth == 0 then close_pos = i; break end
        end
    end
    local sub_block = win:sub(open_pos, close_pos or #win)

    local items = {}
    for wid, body in sub_block:gmatch('"(%d%d%d%d%d%d+)"%s*{(.-)}') do
        local ts = body:match('"TimeSubscribed"%s*"(%d+)"')
        table.insert(items, { workshopId = wid, timeSubscribed = tonumber(ts) or 0 })
    end
    return items
end

local function is_item_downloaded(appid, wid)
    local content = workshop_content_dir(appid)
    if content == "" then return false, 0 end
    local item = fs.join(content, tostring(wid))
    if not fs.exists(item) then return false, 0 end
    if fs.is_file(item) then return true, (fs.file_size(item) or 0) end
    if fs.is_directory(item) then
        local total = st.dir_size(item)
        return total > 0, total
    end
    return false, 0
end

local function fetch_published_file_details(ids)
    if #ids == 0 then return {} end
    local parts = { "itemcount=" .. #ids }
    for i, wid in ipairs(ids) do parts[#parts + 1] = "publishedfileids[" .. (i - 1) .. "]=" .. wid end
    local ok, resp = pcall(http_client.post, PUBLISHED_FILE_DETAILS_URL, {
        data = table.concat(parts, "&"), timeout = 15,
        headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
    })
    local out = {}
    if ok and resp and resp.status == 200 and resp.body then
        local ok2, data = pcall(cjson.decode, resp.body)
        if ok2 and type(data) == "table" and type(data.response) == "table" then
            for _, d in ipairs(data.response.publishedfiledetails or {}) do
                local wid = tostring(d.publishedfileid or "")
                if wid ~= "" then
                    out[wid] = {
                        title = d.title or "",
                        description = tostring(d.description or ""):sub(1, 200),
                        creator = d.creator or "",
                        appid = tonumber(d.consumer_app_id) or 0,
                        fileUrl = d.file_url or "",
                        fileSize = tonumber(d.file_size) or 0,
                        previewUrl = d.preview_url or "",
                        fileName = d.filename or "",
                        timeUpdated = tonumber(d.time_updated) or 0,
                        result = tonumber(d.result) or 0,
                        banned = d.banned == true,
                    }
                end
            end
        end
    else
        logger.warn("workshop: GetPublishedFileDetails failed")
    end
    return out
end

local function download_to_workshop_dir(appid, workshop_id, file_url, file_name)
    if not file_url or file_url == "" then
        return { success = false, error = "no file_url - item may be private" }
    end
    local content_dir = workshop_content_dir(appid)
    if content_dir == "" then return { success = false, error = "Steam install path not found" } end
    pcall(fs.create_directories, content_dir)

    local item_dir = fs.join(content_dir, tostring(workshop_id))
    if fs.is_directory(item_dir) then
        local existing = 0
        for _, e in ipairs(fs.list_recursive(item_dir) or {}) do if e.is_file then existing = existing + 1 end end
        if existing > 0 then
            return { success = false, itemDir = item_dir,
                error = "Item already downloaded (" .. existing .. " files). Remove the folder manually to re-download." }
        end
    end

    local tmp_dir = m_utils.getenv("TEMP") or m_utils.getenv("TMP") or content_dir
    local safe_name = (tostring(file_name or "workshop_item")):gsub("[^%w_%.%-]+", "_")
    local tmp_path = fs.join(tmp_dir, "wsdl_" .. workshop_id .. "_" .. safe_name)

    local ok, resp = pcall(http_client.get, file_url, { timeout = 120 })
    if not (ok and resp and resp.status == 200 and resp.body) then
        return { success = false, error = "download failed (HTTP " .. tostring(resp and resp.status or "?") .. ")" }
    end
    if #resp.body < 16 then
        return { success = false, error = "downloaded file too small (network error?)" }
    end
    local f = io.open(tmp_path, "wb")
    if not f then return { success = false, error = "temp write failed" } end
    f:write(resp.body); f:close()

    pcall(fs.create_directories, item_dir)
    local extracted = false
    if resp.body:sub(1, 4) == "PK\3\4" then
        local ps = string.format(
            'powershell -NoProfile -NonInteractive -Command "Expand-Archive -LiteralPath \'%s\' -DestinationPath \'%s\' -Force"',
            tmp_path, item_dir)
        local ok_ex = pcall(m_utils.exec, ps)
        if ok_ex then extracted = true end
    end
    if not extracted then
        local dest = fs.join(item_dir, file_name ~= "" and file_name or "workshop_item")
        fs.rename(tmp_path, dest)
    else
        pcall(fs.remove, tmp_path)
    end

    local final_size, final_count = 0, 0
    for _, e in ipairs(fs.list_recursive(item_dir) or {}) do
        if e.is_file then
            final_count = final_count + 1
            final_size = final_size + (fs.file_size(e.path) or 0)
        end
    end
    logger.log("workshop: downloaded " .. workshop_id .. " (" .. final_count .. " files)")
    return {
        success = true, workshopId = workshop_id, itemDir = item_dir,
        extracted = extracted, fileCount = final_count, totalBytes = final_size,
    }
end

-- ── public IPC ───────────────────────────────────────────────────────────────

function M.list_subscribed(appid, account_id32)
    appid = tonumber(appid)
    account_id32 = tonumber(account_id32)
    if not appid or not account_id32 then
        return { success = false, error = "invalid appid or accountId32" }
    end

    local subs = parse_subscribed_items(account_id32, appid)
    if #subs == 0 then
        return {
            success = true, appid = appid, accountId32 = account_id32, items = st.A({}),
            message = "No Workshop subscriptions found in localconfig.vdf for this game/account",
        }
    end

    local ids = {}
    for _, s in ipairs(subs) do table.insert(ids, s.workshopId) end
    local details = fetch_published_file_details(ids)

    local items, downloaded_count = {}, 0
    for _, s in ipairs(subs) do
        local det = details[s.workshopId] or {}
        local downloaded, size_local = is_item_downloaded(appid, s.workshopId)
        if downloaded then downloaded_count = downloaded_count + 1 end
        table.insert(items, {
            workshopId = s.workshopId,
            title = det.title or "(metadata unavailable)",
            creator = det.creator or "",
            downloaded = downloaded, localBytes = size_local,
            remoteBytes = det.fileSize or 0,
            hasFileUrl = (det.fileUrl ~= nil and det.fileUrl ~= "") and true or false,
            fileName = det.fileName or "",
            timeSubscribed = s.timeSubscribed or 0,
            timeUpdated = det.timeUpdated or 0,
            banned = det.banned or false,
            previewUrl = det.previewUrl or "",
            result = det.result or 0,
        })
    end

    return {
        success = true, appid = appid, accountId32 = account_id32,
        totalSubscribed = #items, downloadedCount = downloaded_count,
        missingCount = #items - downloaded_count, items = st.A(items),
    }
end

function M.list_local_items(appid)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "invalid appid" } end
    local content = workshop_content_dir(appid)
    if content == "" or not fs.is_directory(content) then
        return { success = true, appid = appid, items = st.A({}) }
    end
    local items = {}
    for _, e in ipairs(fs.list(content) or {}) do
        local name = e.name or ""
        if name:match("^%d+$") then
            if e.is_directory then
                local file_count, size = 0, 0
                for _, fe in ipairs(fs.list_recursive(e.path) or {}) do
                    if fe.is_file then file_count = file_count + 1; size = size + (fs.file_size(fe.path) or 0) end
                end
                table.insert(items, { workshopId = name, isDir = true, fileCount = file_count, totalBytes = size })
            elseif e.is_file then
                table.insert(items, { workshopId = name, isDir = false, fileCount = 1, totalBytes = fs.file_size(e.path) or 0 })
            end
        end
    end
    return { success = true, appid = appid, items = st.A(items), total = #items }
end

function M.download_item(appid, workshop_id)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "invalid appid" } end
    workshop_id = st.trim(workshop_id or "")
    if workshop_id == "" or not workshop_id:match("^%d+$") then
        return { success = false, error = "valid workshopId required" }
    end

    local details = fetch_published_file_details({ workshop_id })
    local item = details[workshop_id]
    if not item then return { success = false, error = "Could not fetch item details from Steam Web API" } end
    if item.result == 9 then return { success = false, error = "Item not found on Steam" } end
    if item.banned then return { success = false, error = "Item is banned" } end
    if not item.fileUrl or item.fileUrl == "" then
        return { success = false, title = item.title or "",
            error = "Item has no direct download URL - typical for hidden, friends-only, or in-game-only Workshop items. Cannot bypass." }
    end

    local result = download_to_workshop_dir(appid, workshop_id, item.fileUrl, item.fileName or "")
    result.title = item.title or ""
    return result
end

function M.delete_item(appid, workshop_id)
    appid = tonumber(appid)
    if not appid then return { success = false, error = "invalid appid" } end
    workshop_id = st.trim(workshop_id or "")
    if workshop_id == "" or not workshop_id:match("^%d+$") then
        return { success = false, error = "valid workshopId required" }
    end
    local content = workshop_content_dir(appid)
    if content == "" then return { success = false, error = "Steam install not found" } end
    local item_path = fs.join(content, workshop_id)
    if not fs.exists(item_path) then return { success = false, error = "Item not found locally" } end
    local ok
    if fs.is_file(item_path) then ok = fs.remove(item_path) else ok = fs.remove_all(item_path) end
    if ok == nil or ok == false then return { success = false, error = "delete failed" } end
    logger.log("workshop: deleted local copy of item " .. workshop_id .. " (appid " .. appid .. ")")
    return { success = true, workshopId = workshop_id }
end

return M
