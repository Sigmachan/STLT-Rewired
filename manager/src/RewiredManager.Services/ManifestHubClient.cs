using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace RewiredManager.Services;

/// <summary>Live ManifestHub key validation (matches backend/manifesthub.lua).</summary>
public sealed class ManifestHubClient
{
    private static readonly Regex KeyFormat = new(@"^smm_[0-9a-fA-F]{96}$", RegexOptions.Compiled);
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(12) };

    public async Task<ManifestHubValidation> ValidateKeyAsync(string apiKey, CancellationToken ct = default)
    {
        if (!KeyFormat.IsMatch(apiKey))
            return ManifestHubValidation.Fail("Key must be smm_ + 96 hex characters.");

        var url = "https://hubcapmanifest.com/api/v1/user/stats?api_key=" + Uri.EscapeDataString(apiKey);
        try
        {
            using var resp = await Http.GetAsync(url, ct);
            var body = await resp.Content.ReadAsStringAsync(ct);
            if (!resp.IsSuccessStatusCode)
                return ManifestHubValidation.Fail($"HTTP {(int)resp.StatusCode}");

            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;
            var username = root.TryGetProperty("username", out var u) ? u.GetString() : null;
            int? used = TryInt(root, "daily_downloads", "downloads_today", "used", "downloads_used");
            int? limit = TryInt(root, "daily_limit", "limit", "downloads_limit");
            return ManifestHubValidation.Ok(username, used, limit);
        }
        catch (Exception ex)
        {
            return ManifestHubValidation.Fail(ex.Message);
        }
    }

    private static int? TryInt(JsonElement root, params string[] names)
    {
        foreach (var n in names)
        {
            if (root.TryGetProperty(n, out var el) && el.TryGetInt32(out var v))
                return v;
        }
        return null;
    }
}

public sealed record ManifestHubValidation(
    bool Success,
    string? Username,
    int? Used,
    int? Limit,
    string? Error)
{
    public static ManifestHubValidation Ok(string? username, int? used, int? limit) =>
        new(true, username, used, limit, null);

    public static ManifestHubValidation Fail(string error) =>
        new(false, null, null, null, error);
}
