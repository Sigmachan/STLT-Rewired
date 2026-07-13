using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;
using RewiredManager.App.Models;

namespace RewiredManager.App.Services;

public sealed class RyuuCatalogService
{
    private const string CatalogUrl = "https://generator.ryuu.lol/files/games.json";
    private static readonly string CachePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Rewired",
        "ryuu_games.json");
    private static readonly TimeSpan CacheTtl = TimeSpan.FromHours(24);

    private static readonly HttpClient Http = CreateClient();

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(3) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("RewiredManager/1.0 (+https://github.com/Sigmachan/STLT-Rewired)");
        return client;
    }

    public async Task<RyuuCatalogSearchResult> SearchAsync(
        string query,
        string? ryuuCookieHeader,
        int limit = 40,
        CancellationToken ct = default)
    {
        query = (query ?? "").Trim();
        if (query.Length < 2)
            return new RyuuCatalogSearchResult(true, "Type at least 2 characters.", Array.Empty<RyuuCatalogEntry>(), 0, false);

        limit = Math.Clamp(limit, 1, 100);

        if (Regex.IsMatch(query, @"^\d+$") && int.TryParse(query, out var appId) && appId > 0)
        {
            var direct = await LookupSteamStoreAsync(appId, ct);
            if (direct != null)
                return new RyuuCatalogSearchResult(true, "AppID match.", new[] { direct }, 1, false);
        }

        var steamResults = await SearchSteamStoreAsync(query, limit, ct);
        if (steamResults.Count >= limit)
            return new RyuuCatalogSearchResult(true, $"Steam store search ({steamResults.Count} shown).", steamResults, steamResults.Count, false);

        var catalogHits = await SearchCachedCatalogAsync(query, limit, ryuuCookieHeader, ct);
        if (catalogHits.Count > 0)
        {
            var merged = MergeResults(steamResults, catalogHits, limit);
            return new RyuuCatalogSearchResult(
                true,
                $"Catalog search ({merged.Count} shown).",
                merged,
                merged.Count,
                true);
        }

        if (steamResults.Count > 0)
            return new RyuuCatalogSearchResult(true, $"Steam store search ({steamResults.Count} shown).", steamResults, steamResults.Count, false);

        return new RyuuCatalogSearchResult(false, "No matches. Try warming the Ryuu catalog cache.", Array.Empty<RyuuCatalogEntry>(), 0, false);
    }

    public async Task<(bool Success, string Message)> WarmCacheAsync(string? ryuuCookieHeader, CancellationToken ct = default)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(CachePath)!);
            using var request = new HttpRequestMessage(HttpMethod.Get, CatalogUrl);
            if (!string.IsNullOrWhiteSpace(ryuuCookieHeader))
                request.Headers.TryAddWithoutValidation("Cookie", ryuuCookieHeader);

            using var response = await Http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
            if (!response.IsSuccessStatusCode)
                return (false, $"Ryuu catalog download failed: HTTP {(int)response.StatusCode}.");

            await using var stream = await response.Content.ReadAsStreamAsync(ct);
            await using var file = File.Create(CachePath);
            await stream.CopyToAsync(file, ct);
            return (true, $"Ryuu catalog cached ({new FileInfo(CachePath).Length / (1024 * 1024)} MB).");
        }
        catch (Exception ex)
        {
            return (false, ex.Message);
        }
    }

    private async Task<IReadOnlyList<RyuuCatalogEntry>> SearchCachedCatalogAsync(
        string query,
        int limit,
        string? ryuuCookieHeader,
        CancellationToken ct)
    {
        if (!IsCacheFresh())
        {
            var warm = await WarmCacheAsync(ryuuCookieHeader, ct);
            if (!warm.Success)
                return Array.Empty<RyuuCatalogEntry>();
        }

        if (!File.Exists(CachePath))
            return Array.Empty<RyuuCatalogEntry>();

        var q = query.ToLowerInvariant();
        var digitsOnly = Regex.IsMatch(query, @"^\d+$");
        var results = new List<RyuuCatalogEntry>();
        var total = 0;

        await foreach (var game in EnumerateCatalogGamesAsync(CachePath, ct))
        {
            var hit = digitsOnly
                ? game.AppId.ToString() == query
                : game.Name.Contains(q, StringComparison.OrdinalIgnoreCase) || game.AppId.ToString() == query;

            if (!hit) continue;
            total++;
            if (results.Count < limit)
                results.Add(game with { Source = "Ryuu catalog" });
        }

        return results;
    }

    private static async IAsyncEnumerable<RyuuCatalogEntry> EnumerateCatalogGamesAsync(string path, [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken ct)
    {
        await using var stream = File.OpenRead(path);
        using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct);
        var root = doc.RootElement;

        if (root.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in root.EnumerateArray())
            {
                var entry = ParseGame(item);
                if (entry != null) yield return entry;
            }
            yield break;
        }

        if (root.ValueKind == JsonValueKind.Object)
        {
            foreach (var prop in root.EnumerateObject())
            {
                if (prop.Value.ValueKind != JsonValueKind.Object) continue;
                var entry = ParseGame(prop.Value);
                if (entry != null) yield return entry;
            }
        }
    }

    private static RyuuCatalogEntry? ParseGame(JsonElement item)
    {
        if (!item.TryGetProperty("appid", out var appEl)) return null;
        var appId = appEl.ValueKind == JsonValueKind.Number
            ? appEl.GetInt32()
            : int.TryParse(appEl.GetString(), out var parsed) ? parsed : 0;
        if (appId <= 0) return null;

        var name = item.TryGetProperty("name", out var nameEl) ? nameEl.GetString() ?? "" : "";
        var image = item.TryGetProperty("header_image", out var imgEl) ? imgEl.GetString() : null;
        return new RyuuCatalogEntry(appId, name, image, "Ryuu catalog");
    }

    private static async Task<IReadOnlyList<RyuuCatalogEntry>> SearchSteamStoreAsync(string query, int limit, CancellationToken ct)
    {
        var url = "https://store.steampowered.com/api/storesearch/?term=" + Uri.EscapeDataString(query) + "&l=english&cc=US";
        try
        {
            using var response = await Http.GetAsync(url, ct);
            if (!response.IsSuccessStatusCode)
                return Array.Empty<RyuuCatalogEntry>();

            await using var stream = await response.Content.ReadAsStreamAsync(ct);
            using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct);
            if (!doc.RootElement.TryGetProperty("items", out var items) || items.ValueKind != JsonValueKind.Array)
                return Array.Empty<RyuuCatalogEntry>();

            var results = new List<RyuuCatalogEntry>();
            foreach (var item in items.EnumerateArray())
            {
                if (!item.TryGetProperty("id", out var idEl)) continue;
                var appId = idEl.GetInt32();
                if (appId <= 0) continue;
                var name = item.TryGetProperty("name", out var nameEl) ? nameEl.GetString() ?? "" : "";
                var image = item.TryGetProperty("tiny_image", out var imgEl) ? imgEl.GetString() : null;
                results.Add(new RyuuCatalogEntry(appId, name, image, "Steam store"));
                if (results.Count >= limit) break;
            }
            return results;
        }
        catch
        {
            return Array.Empty<RyuuCatalogEntry>();
        }
    }

    private static async Task<RyuuCatalogEntry?> LookupSteamStoreAsync(int appId, CancellationToken ct)
    {
        var hits = await SearchSteamStoreAsync(appId.ToString(), 5, ct);
        return hits.FirstOrDefault(h => h.AppId == appId)
            ?? new RyuuCatalogEntry(appId, $"AppID {appId}", null, "AppID");
    }

    private static List<RyuuCatalogEntry> MergeResults(
        IReadOnlyList<RyuuCatalogEntry> primary,
        IReadOnlyList<RyuuCatalogEntry> secondary,
        int limit)
    {
        var seen = new HashSet<int>();
        var merged = new List<RyuuCatalogEntry>();
        foreach (var entry in primary.Concat(secondary))
        {
            if (!seen.Add(entry.AppId)) continue;
            merged.Add(entry);
            if (merged.Count >= limit) break;
        }
        return merged;
    }

    private static bool IsCacheFresh()
    {
        if (!File.Exists(CachePath)) return false;
        return DateTime.UtcNow - File.GetLastWriteTimeUtc(CachePath) < CacheTtl;
    }
}
