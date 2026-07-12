-- manifesthub.lua — ManifestHub (formerly Morrenus / Hubcap) API key validation.

local http_client = require("http_client")
local cjson       = require("json")

local M = {}

local STATS_URL = "https://hubcapmanifest.com/api/v1/user/stats?api_key="

local function trim(s)
    return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function format_ok(key)
    return key:match("^smm_[0-9a-f]+$") and #key == 100
end

function M.validate_key(api_key)
    local key = trim(api_key)
    if key == "" then
        return { success = false, error = "api_key required" }
    end

    if not format_ok(key) then
        return {
            success = true,
            valid = false,
            reason = "bad_format",
            message = "Key should look like 'smm_' followed by 96 hex characters.",
        }
    end

    local ok_http, resp = pcall(http_client.get, STATS_URL .. key, { timeout = 10 })
    if not ok_http then
        return { success = false, error = tostring(resp) }
    end

    local status = resp and resp.status or 0
    if status == 200 and resp.body then
        local ok_json, info = pcall(cjson.decode, resp.body)
        info = ok_json and type(info) == "table" and info or {}
        return {
            success = true,
            valid = true,
            username = tostring(info.username or ""),
            canMakeRequests = info.can_make_requests,
            dailyUsage = info.daily_usage or info.daily_downloads or info.used,
            dailyLimit = info.daily_limit or info.limit,
        }
    end

    if status == 401 or status == 403 then
        return {
            success = true,
            valid = false,
            reason = "rejected",
            message = "Key rejected by ManifestHub (invalid or expired).",
        }
    end

    return {
        success = true,
        valid = false,
        reason = "http",
        message = "ManifestHub returned HTTP " .. tostring(status) .. ".",
    }
end

return M
