using System.Diagnostics;
using System.Net;
using System.Net.Http;
using RewiredManager.App.Models;

namespace RewiredManager.App.Services;

public sealed class SourceHealthService
{
    private readonly HttpClient _http;

    public SourceHealthService()
    {
        _http = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        _http.DefaultRequestHeaders.UserAgent.ParseAdd("RewiredManager/1.0");
    }

    public async Task<IReadOnlyList<SourceProbeResult>> ProbeAsync(
        string? ryuuCookie,
        string? manifestHubKey = null,
        CancellationToken cancellationToken = default)
    {
        var probes = new List<(string Name, string Url, string? Cookie, bool SkipWithoutKey)>
        {
            ("Ryuu catalog", "https://generator.ryuu.lol/api/games?limit=40&page=1&search=portal", ryuuCookie, false),
            ("Ryuu fixes", "https://generator.ryuu.lol/fixes", ryuuCookie, false),
            ("Ryuu games.json", "https://generator.ryuu.lol/files/games.json", ryuuCookie, false),
            ("LuaTools fixes index", "https://index.luatools.work/fixes-index.json", null, false),
            ("ManifestHub", BuildManifestHubUrl(manifestHubKey), null, true),
            ("jsDelivr CDN", "https://cdn.jsdelivr.net/npm/", null, false),
            ("GitHub", "https://github.com", null, false),
        };

        var results = new List<SourceProbeResult>();
        foreach (var probe in probes)
        {
            if (probe.SkipWithoutKey && string.IsNullOrWhiteSpace(manifestHubKey))
            {
                results.Add(new SourceProbeResult(
                    probe.Name,
                    probe.Url,
                    false,
                    null,
                    "skipped (no ManifestHub key)",
                    TimeSpan.Zero));
                continue;
            }

            results.Add(await ProbeOneAsync(probe.Name, probe.Url, probe.Cookie, cancellationToken));
        }

        return results;
    }

    private static string BuildManifestHubUrl(string? apiKey)
    {
        var key = (apiKey ?? "").Trim();
        if (key == "") return "https://hubcapmanifest.com/api/v1/user/stats";
        return "https://hubcapmanifest.com/api/v1/user/stats?api_key=" + Uri.EscapeDataString(key);
    }

    private async Task<SourceProbeResult> ProbeOneAsync(string name, string url, string? cookie, CancellationToken cancellationToken)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, url);
            if (!string.IsNullOrWhiteSpace(cookie))
                req.Headers.TryAddWithoutValidation("Cookie", cookie);

            using var resp = await _http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            sw.Stop();

            var success = resp.StatusCode is >= HttpStatusCode.OK and < HttpStatusCode.MultipleChoices;
            var message = success ? "OK" : $"HTTP {(int)resp.StatusCode} {resp.ReasonPhrase}";
            return new SourceProbeResult(name, url, success, (int)resp.StatusCode, message, sw.Elapsed);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or OperationCanceledException)
        {
            sw.Stop();
            return new SourceProbeResult(name, url, false, null, ex.GetType().Name, sw.Elapsed);
        }
    }
}
