local http_client = require("http_client")
local settings = require("settings.manager")
local st = require("st_util")

local M = {}

local SEARCH_URL = "https://generator.ryuu.lol/api/games"
local CATALOG_CACHE = nil
local CATALOG_CACHE_TS = 0
local CATALOG_TTL = 10 * 60
local PAGE_LIMIT = 40
local MAX_SEARCH_PAGES = 80

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

local function contains(haystack, needle)
    return tostring(haystack or ""):lower():find(tostring(needle or ""):lower(), 1, true) ~= nil
end

local function fetch_page(query, page)
    local url = SEARCH_URL .. "?limit=" .. PAGE_LIMIT .. "&page=" .. tostring(page) .. "&search=" .. url_encode(query)
    local ok_http, resp = pcall(http_client.get, url, { headers = ryuu_headers(), timeout = 15 })
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
        return data.games, nil, tonumber(data.total_pages) or page
    end
    return data, nil, page
end

local function search_remote(query, limit)
    local cache_key = tostring(query or "") .. ":" .. tostring(limit or "")
    local now = now_seconds()
    if CATALOG_CACHE and CATALOG_CACHE[cache_key] and (now - CATALOG_CACHE_TS) < CATALOG_TTL then
        return CATALOG_CACHE[cache_key]
    end

    local out = {}
    local total = 0
    local first_err = nil
    local max_pages = MAX_SEARCH_PAGES
    for page = 1, max_pages do
        local games, err, total_pages = fetch_page(query, page)
        if not games then
            first_err = first_err or err
            break
        end
        if #games == 0 then break end

        for _, g in ipairs(games) do
            if contains(g.name, query) or tostring(g.appid or "") == query then
                total = total + 1
                if #out < limit then
                    table.insert(out, {
                        appid = tostring(g.appid or ""),
                        name = tostring(g.name or ""),
                        header_image = tostring(g.header_image or ""),
                        tags = st.A(g.tags or {}),
                        nsfw = g.nsfw == true,
                        drm = g.drm == true,
                    })
                end
            end
        end

        if #out >= limit then break end
        if total_pages and page >= math.min(total_pages, max_pages) then break end
    end

    if #out == 0 and first_err then
        return nil, first_err
    end

    local result = { total = total, results = out, scannedPages = max_pages }
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
