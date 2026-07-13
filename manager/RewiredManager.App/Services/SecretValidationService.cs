using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;
using RewiredManager.App.Models;

namespace RewiredManager.App.Services;

public sealed class SecretValidationService
{
    private static readonly HttpClient Http = CreateClient();

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("RewiredManager/1.0 (+https://github.com/Sigmachan/STLT-Rewired)");
        return client;
    }

    public async Task<SecretValidationResult> ValidateRyuuAsync(string cookie, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(cookie))
            return new SecretValidationResult(false, "Ryuu session cookie is empty.");

        using var req = new HttpRequestMessage(HttpMethod.Get, "https://generator.ryuu.lol/api/check_session");
        req.Headers.TryAddWithoutValidation("Cookie", cookie.Trim());
        using var resp = await Http.SendAsync(req, ct);
        var body = await resp.Content.ReadAsStringAsync(ct);

        if (resp.StatusCode is >= HttpStatusCode.OK and < HttpStatusCode.MultipleChoices)
        {
            try
            {
                using var doc = JsonDocument.Parse(body);
                if (doc.RootElement.TryGetProperty("valid", out var valid) && valid.ValueKind == JsonValueKind.True)
                    return new SecretValidationResult(true, "Ryuu session is valid.");
                if (doc.RootElement.TryGetProperty("message", out var msg))
                    return new SecretValidationResult(false, msg.GetString() ?? "Session rejected.");
            }
            catch
            {
                return new SecretValidationResult(true, "Ryuu check_session returned HTTP 200.");
            }
        }

        return new SecretValidationResult(false, $"Ryuu check failed: HTTP {(int)resp.StatusCode}.");
    }

    public async Task<SecretValidationResult> ValidateManifestHubAsync(string apiKey, CancellationToken ct = default)
    {
        var key = (apiKey ?? "").Trim();
        if (key == "")
            return new SecretValidationResult(false, "ManifestHub API key is empty.");

        if (!Regex.IsMatch(key, "^smm_[0-9a-f]{96}$"))
            return new SecretValidationResult(false, "Key should look like smm_ followed by 96 hex characters.");

        var url = "https://hubcapmanifest.com/api/v1/user/stats?api_key=" + Uri.EscapeDataString(key);
        using var resp = await Http.GetAsync(url, ct);
        var body = await resp.Content.ReadAsStringAsync(ct);

        if (resp.StatusCode == HttpStatusCode.OK)
        {
            try
            {
                using var doc = JsonDocument.Parse(body);
                var user = doc.RootElement.TryGetProperty("username", out var u) ? u.GetString() : "";
                return new SecretValidationResult(true, string.IsNullOrWhiteSpace(user)
                    ? "ManifestHub key accepted."
                    : $"ManifestHub key valid for user: {user}");
            }
            catch
            {
                return new SecretValidationResult(true, "ManifestHub key accepted (HTTP 200).");
            }
        }

        if (resp.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
            return new SecretValidationResult(false, "ManifestHub rejected the key (invalid or expired).");

        return new SecretValidationResult(false, $"ManifestHub returned HTTP {(int)resp.StatusCode}.");
    }

    public async Task<SecretValidationResult> ValidateRyuuFixesAsync(string cookie, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(cookie))
            return new SecretValidationResult(false, "Ryuu session cookie is empty — save it in Settings first.");

        using var req = new HttpRequestMessage(HttpMethod.Get, "https://generator.ryuu.lol/fixes");
        req.Headers.TryAddWithoutValidation("Cookie", cookie.Trim());
        using var resp = await Http.SendAsync(req, ct);

        if (resp.StatusCode is >= HttpStatusCode.OK and < HttpStatusCode.MultipleChoices)
            return new SecretValidationResult(true, $"Ryuu fixes endpoint OK (HTTP {(int)resp.StatusCode}). Open Fixes in Steam for per-game patches.");

        if (resp.StatusCode == HttpStatusCode.TooManyRequests)
            return new SecretValidationResult(false, "Ryuu fixes rate-limited (429). Try again later.");

        return new SecretValidationResult(false, $"Ryuu fixes check failed: HTTP {(int)resp.StatusCode}.");
    }
}
