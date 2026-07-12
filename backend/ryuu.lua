local http_client = require("http_client")
local settings    = require("settings.manager")
local st          = require("st_util")
local fs          = require("fs")
local utils       = require("plugin_utils")
local logger      = require("plugin_logger")

local M = {}

-- Ryuu's paginated /api/games endpoint ignores ?search= (returns appid-sorted pages).
-- The real catalog lives in games.json (~40 MB); cache it under backend/data and search locally.
local CATALOG_JSON_URL = "https://generator.ryuu.lol/files/games.json"
local CATALOG_CACHE_FILE = "ryuu_games.json"
local CATALOG_TTL = 24 * 60 * 60
local DOWNLOAD_TIMEOUT = 120

local INDEX_MEM = nil
local INDEX_MEM_TS = 0
local INDEX_MEM_SIZE = 0

local function now_seconds()
    return os.time()
end

local function ryuu_headers()
    local headers = { ["User-Agent"] = "STLT-Rewired" }
    local ok, sess = pcall(settings.get_ryuu_session)
    if ok and type(sess) == "string" and sess ~= "" then
        headers["Cookie"] = sess
    end
    return headers
end

local function normalize_game(g)
    if type(g) ~= "table" then return nil end
    return {
        appid = tostring(g.appid or ""),
        name = tostring(g.name or ""),
        header_image = tostring(g.header_image or ""),
        tags = st.A(g.tags or {}),
        nsfw = g.nsfw == true,
        drm = g.drm == true,
    }
end

local function contains(haystack, needle)
    return tostring(haystack or ""):lower():find(tostring(needle or ""):lower(), 1, true) ~= nil
end

local function catalog_cache_path()
    return st.data_path(CATALOG_CACHE_FILE)
end

local function cache_is_fresh(path)
    if not path or path == "" or not fs.exists(path) then return false end
    local mtime = fs.last_write_time and fs.last_write_time(path)
    if not mtime then return true end -- unknown age — still usable
    return (now_seconds() - tonumber(mtime) or 0) <= CATALOG_TTL
end

local function parse_catalog_blob(text)
    local data = utils.decode_json(text)
    if type(data) == "table" then
        if data[1] ~= nil then
            return data
        end
        local out = {}
        for _, g in pairs(data) do
            if type(g) == "table" then table.insert(out, g) end
        end
        return out
    end
    return nil
end

local function load_catalog_from_disk(path)
    local text = utils.read_text(path)
    if text == "" then return nil, "empty catalog cache" end
    local games = parse_catalog_blob(text)
    if not games or #games == 0 then
        return nil, "catalog cache JSON invalid"
    end
    return games, nil
end

local function download_catalog_to_disk(path)
    logger.log("ryuu: downloading catalog index from games.json (first run may take ~1 min)")
    local ok_http, resp = pcall(http_client.get, CATALOG_JSON_URL, {
        headers = ryuu_headers(),
        timeout = DOWNLOAD_TIMEOUT,
    })
    if not ok_http then
        return nil, "Ryuu catalog download failed: " .. tostring(resp)
    end
    if not resp or resp.status ~= 200 or not resp.body or resp.body == "" then
        return nil, "Ryuu catalog HTTP " .. tostring((resp and resp.status) or "?")
    end

    local games = parse_catalog_blob(resp.body)
    if not games or #games == 0 then
        return nil, "Ryuu catalog JSON decode failed"
    end

    local ok_write = pcall(function()
        local dir = st.data_dir()
        if dir and dir ~= "" and not fs.exists(dir) then
            fs.create_directories(dir)
        end
        utils.write_text(path, resp.body)
    end)
    if not ok_write then
        logger.warn("ryuu: could not persist catalog cache — using in-memory index only")
    end
    return games, nil
end

local function ensure_catalog_index(force_refresh)
    local now = now_seconds()
    if not force_refresh and INDEX_MEM and INDEX_MEM_TS > 0 and (now - INDEX_MEM_TS) < CATALOG_TTL then
        return INDEX_MEM, nil, INDEX_MEM_SIZE
    end

    local path = catalog_cache_path()
    local games, err

    if not force_refresh and cache_is_fresh(path) then
        games, err = load_catalog_from_disk(path)
    end

    if not games then
        games, err = download_catalog_to_disk(path)
        if not games and path ~= "" and fs.exists(path) then
            logger.warn("ryuu: refresh failed (" .. tostring(err) .. ") — falling back to stale cache")
            games, err = load_catalog_from_disk(path)
        end
    end

    if not games then
        return nil, err or "Ryuu catalog unavailable"
    end

    INDEX_MEM = games
    INDEX_MEM_TS = now
    INDEX_MEM_SIZE = #games
    return games, nil, INDEX_MEM_SIZE
end

local function search_index(catalog, query, limit)
    local out = {}
    local total = 0
    local q = tostring(query or "")
    local digits_only = q:match("^%d+$") ~= nil

    for _, raw in ipairs(catalog) do
        local g = normalize_game(raw)
        if g then
            local hit = false
            if digits_only then
                hit = g.appid == q
            else
                hit = contains(g.name, q) or g.appid == q
            end
            if hit then
                total = total + 1
                if #out < limit then
                    table.insert(out, g)
                end
            end
        end
    end

    return out, total
end

function M.warm_catalog_cache(force_refresh)
    local catalog, err, size = ensure_catalog_index(force_refresh == true)
    if not catalog then
        return { success = false, error = err or "Ryuu catalog unavailable" }
    end
    return {
        success = true,
        catalogSize = size or #catalog,
        cachePath = catalog_cache_path(),
        refreshed = force_refresh == true,
    }
end

function M.search_catalog(query, limit)
    query = tostring(query or "")
    query = query:gsub("^%s+", ""):gsub("%s+$", "")
    limit = tonumber(limit) or 60
    if limit < 1 then limit = 1 end
    if limit > 100 then limit = 100 end
    if #query < 2 then
        return { success = true, query = query, total = 0, results = st.A({}), message = "type >=2 chars" }
    end

    local catalog, err, size = ensure_catalog_index(false)
    if not catalog then
        return { success = false, error = err or "Ryuu catalog unavailable", results = st.A({}) }
    end

    local matches, total = search_index(catalog, query, limit)
    return {
        success = true,
        query = query,
        total = total,
        results = st.A(matches),
        catalogSize = size or #catalog,
        source = "games.json",
    }
end

return M
