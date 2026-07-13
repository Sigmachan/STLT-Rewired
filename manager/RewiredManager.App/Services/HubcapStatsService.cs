using System.Net;
using System.Net.Http;
using System.Text.Json;
using RewiredManager.App.Models;

namespace RewiredManager.App.Services;

public sealed class HubcapStatsService
{
    private static readonly HttpClient Http = CreateClient();

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("RewiredManager/1.0 (+https://github.com/Sigmachan/STLT-Rewired)");
        return client;
    }

    public async Task<HubcapStatsResult> FetchAsync(string apiKey, CancellationToken ct = default)
    {
        var key = (apiKey ?? "").Trim();
        if (key == "")
            return new HubcapStatsResult(false, "ManifestHub API key is empty.", null, null, null, null);

        var url = "https://hubcapmanifest.com/api/v1/user/stats?api_key=" + Uri.EscapeDataString(key);
        using var resp = await Http.GetAsync(url, ct);
        var body = await resp.Content.ReadAsStringAsync(ct);

        if (resp.StatusCode != HttpStatusCode.OK)
        {
            if (resp.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
                return new HubcapStatsResult(false, "ManifestHub rejected the key.", null, null, null, null);
            return new HubcapStatsResult(false, $"ManifestHub returned HTTP {(int)resp.StatusCode}.", null, null, null, null);
        }

        try
        {
            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;
            var username = root.TryGetProperty("username", out var u) ? u.GetString() : "";
            bool? canRequest = root.TryGetProperty("can_make_requests", out var c) && c.ValueKind is JsonValueKind.True or JsonValueKind.False
                ? c.GetBoolean()
                : null;
            int? usage = ReadInt(root, "daily_usage", "daily_downloads", "used");
            int? limit = ReadInt(root, "daily_limit", "limit");

            var msg = string.IsNullOrWhiteSpace(username)
                ? "ManifestHub stats loaded."
                : $"User: {username}";
            if (usage.HasValue || limit.HasValue)
                msg += $" | Daily {usage?.ToString() ?? "?"} / {limit?.ToString() ?? "?"}";

            return new HubcapStatsResult(true, msg, username, canRequest, usage, limit);
        }
        catch (Exception ex)
        {
            return new HubcapStatsResult(false, "Could not parse ManifestHub stats: " + ex.Message, null, null, null, null);
        }
    }

    private static int? ReadInt(JsonElement root, params string[] names)
    {
        foreach (var name in names)
        {
            if (!root.TryGetProperty(name, out var el)) continue;
            if (el.ValueKind == JsonValueKind.Number && el.TryGetInt32(out var n)) return n;
            if (el.ValueKind == JsonValueKind.String && int.TryParse(el.GetString(), out var parsed)) return parsed;
        }
        return null;
    }
}
