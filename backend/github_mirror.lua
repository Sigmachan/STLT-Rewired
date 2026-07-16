-- github_mirror.lua — GitHub fetch resilience (direct -> Vercel proxy -> jsDelivr).
-- Port of STLT downloads.py _try_with_github_proxy / _jsdelivr_from_raw.

local logger = require("plugin_logger")

local M = {}

function M.is_github_url(url)
    return type(url) == "string" and url:lower():find("github", 1, true) ~= nil
end

function M.jsdelivr_from_raw(url)
    if type(url) ~= "string" or not url:find("raw%.githubusercontent%.com/", 1, false) then
        return ""
    end
    local tail = url:match("raw%.githubusercontent%.com/(.+)$")
    if not tail then return "" end
    local parts = {}
    for part in tail:gmatch("[^/]+") do
        table.insert(parts, part)
    end
    if #parts < 4 then return "" end
    local owner, repo = parts[1], parts[2]
    local rest = {}
    for i = 3, #parts do rest[#rest + 1] = parts[i] end
    local ref, path
    if #rest >= 3 and rest[1] == "refs" and (rest[2] == "heads" or rest[2] == "tags") then
        ref = rest[3]
        path = table.concat(rest, "/", 4)
    else
        ref = rest[1]
        path = table.concat(rest, "/", 2)
    end
    if not path or path == "" then return "" end
    return "https://cdn.jsdelivr.net/gh/" .. owner .. "/" .. repo .. "@" .. ref .. "/" .. path
end

function M.vercel_proxy_url(url, proxy_base)
    proxy_base = proxy_base or ""
    if proxy_base == "" or not M.is_github_url(url) then return "" end
    if url:find("api%.github%.com", 1, false) then
        local path = url:match("api%.github%.com(.*)$")
        return path and (proxy_base .. path) or ""
    end
    if url:find("raw%.githubusercontent%.com", 1, false) then
        local path = url:match("raw%.githubusercontent%.com(.*)$")
        local raw_base = proxy_base:gsub("/api/github", "/api/raw")
        return path and (raw_base .. path) or ""
    end
    return ""
end

local function try_get(http_client, url, options)
    local ok, resp = pcall(http_client.get, url, options)
    if ok and resp and resp.status == 200 and resp.body and #resp.body > 0 then
        return resp.body, resp.status or 200
    end
    local status = 0
    if ok and resp and resp.status then status = resp.status end
    return nil, status
end

--- Fetch URL; for GitHub hosts retry via optional proxy then jsDelivr (raw only).
--- Direct 404 means the object is missing. Proxy 404 must NOT abort — a dead
--- proxy would otherwise skip jsDelivr and hard-fail recoverable fetches.
function M.fetch(http_client, url, options, proxy_base)
    options = options or {}
    local body, status = try_get(http_client, url, options)
    if body then return body end
    if status == 404 then return nil end
    if not M.is_github_url(url) then return nil end

    local proxy_url = M.vercel_proxy_url(url, proxy_base)
    if proxy_url ~= "" then
        logger.warn("GitHub direct failed for " .. url .. ", trying proxy")
        body = try_get(http_client, proxy_url, options)
        if body then return body end
    end

    local jsdelivr = M.jsdelivr_from_raw(url)
    if jsdelivr ~= "" then
        logger.warn("GitHub fetch falling back to jsDelivr for " .. url)
        body = try_get(http_client, jsdelivr, options)
        if body then return body end
    end
    return nil
end

return M
