local m_http = require("http")
local config = require("config")
local logger = require("plugin_logger")

local http_client = {}

function http_client.get(url, options)
    options = options or {}
    options.timeout = options.timeout or config.HTTP_TIMEOUT_SECONDS
    return m_http.get(url, options)
end

function http_client.head(url, options)
    options = options or {}
    options.timeout = options.timeout or config.HTTP_TIMEOUT_SECONDS
    -- Millennium's http module exposes http.request(url, { method = "HEAD" })
    -- and has NO http.head helper. Never fall back to GET — a HEAD→GET probe
    -- on large archive URLs trips Millennium's AV (see commits 617d9d4/0acb1f6).
    if type(m_http.request) == "function" then
        return m_http.request(url, options)
    end
    logger.warn("http_client.head: m_http.request unavailable; refusing HEAD→GET fallback")
    return nil
end

function http_client.post(url, options)
    options = options or {}
    options.timeout = options.timeout or config.HTTP_TIMEOUT_SECONDS
    local data = options.data
    options.data = nil
    return m_http.post(url, data, options)
end

return http_client
