local http_client = require("http_client")
local settings = require("settings.manager")
local st = require("st_util")

local M = {}

local SEARCH_URL = "https://generator.ryuu.lol/api/games"
local CATALOG_CACHE = nil
local CATALOG_CACHE_TS = 0
local CATALOG_TTL = 10 * 60
local PAGE_LIMIT = 40
-- Keep this small: SearchRyuuCatalog runs on Millennium's Lua thread; long paginated
-- loops freeze the Steam UI (the old 80-page scan could block for minutes).
local MAX_SEARCH_PAGES = 3
local HTTP_TIMEOUT = 8

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

local function url_encode(s)
    return tostring(s or ""):gsub("([^%w%-%_%.%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

local function normalize_game(g)
    return {
        appid = tostring(g.appid or ""),
        name = tostring(g.name or ""),
        header_image = tostring(g.header_image or ""),
        tags = st.A(g.tags or {}),
        nsfw = g.nsfw == true,
        drm = g.drm == true,
    }
end

local function fetch_page(query, page)
    local url = SEARCH_URL .. "?limit=" .. PAGE_LIMIT .. "&page=" .. tostring(page) .. "&search=" .. url_encode(query)
    local ok_http, resp = pcall(http_client.get, url, { headers = ryuu_headers(), timeout = HTTP_TIMEOUT })
    if not ok_http then
        return nil, "Ryuu catalog fetch failed: " .. tostring(resp)
    end
    if not resp or resp.status ~= 200 or not resp.body then
        return nil, "Ryuu catalog HTTP " .. tostring((resp and resp.status) or "?")
    end

    local ok, data = pcall(require("json").decode, resp.body)
    if not ok or type(data) ~= "table" then
        return nil, "Ryuu catalog JSON decode failed"
    end

    if type(data.games) == "table" then
        return data.games, nil, tonumber(data.total_pages) or page, tonumber(data.total)
    end
    return data, nil, page, nil
end

local function search_remote(query, limit)
    local cache_key = tostring(query or "") .. ":" .. tostring(limit or "")
    local now = now_seconds()
    if CATALOG_CACHE and CATALOG_CACHE[cache_key] and (now - CATALOG_CACHE_TS) < CATALOG_TTL then
        return CATALOG_CACHE[cache_key]
    end

    local out = {}
    local first_err = nil
    local pages_scanned = 0
    local reported_total = 0
    for page = 1, MAX_SEARCH_PAGES do
        local games, err, total_pages, api_total = fetch_page(query, page)
        if not games then
            first_err = first_err or err
            break
        end
        pages_scanned = page
        if api_total and api_total > reported_total then reported_total = api_total end
        if #games == 0 then break end

        -- The Ryuu API already filters by ?search=; trust page results instead of
        -- re-scanning up to 80 pages client-side (that pattern froze Steam).
        for _, g in ipairs(games) do
            if #out < limit then
                table.insert(out, normalize_game(g))
            end
        end

        if total_pages and tonumber(total_pages) then
            reported_total = math.max(reported_total, tonumber(total_pages) * PAGE_LIMIT)
        end
        if #out >= limit then break end
        if #games < PAGE_LIMIT then break end
        if total_pages and page >= total_pages then break end
    end

    if #out == 0 and first_err then
        return nil, first_err
    end

    local total = reported_total > 0 and reported_total or #out
    local result = { total = total, results = out, scannedPages = pages_scanned }
    CATALOG_CACHE = CATALOG_CACHE or {}
    CATALOG_CACHE[cache_key] = result
    CATALOG_CACHE_TS = now
    return result
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

    local data, err = search_remote(query, limit)
    if not data then
        return { success = false, error = err or "Ryuu catalog unavailable", results = st.A({}) }
    end

    return {
        success = true,
        query = query,
        total = data.total or #data.results,
        results = st.A(data.results or {}),
        scannedPages = data.scannedPages,
    }
end

return M
