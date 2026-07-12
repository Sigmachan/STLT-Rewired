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
        _http.DefaultRequestHeaders.UserAgent.ParseAdd("RewiredManager/0.1");
    }

    public async Task<IReadOnlyList<SourceProbeResult>> ProbeAsync(string? ryuuCookie, CancellationToken cancellationToken = default)
    {
        var probes = new List<(string Name, string Url, bool Cookie)>
        {
            ("Ryuu catalog", "https://generator.ryuu.lol/api/games?limit=40&page=1&search=portal", true),
            ("Ryuu fixes", "https://generator.ryuu.lol/fixes", true),
            ("LuaTools fixes index", "https://index.luatools.work/fixes-index.json", false),
            ("GitHub", "https://github.com", false),
        };

        var results = new List<SourceProbeResult>();
        foreach (var probe in probes)
        {
            results.Add(await ProbeOneAsync(probe.Name, probe.Url, probe.Cookie ? ryuuCookie : null, cancellationToken));
        }
        return results;
    }

    private async Task<SourceProbeResult> ProbeOneAsync(string name, string url, string? cookie, CancellationToken cancellationToken)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, url);
            if (!string.IsNullOrWhiteSpace(cookie)) req.Headers.TryAddWithoutValidation("Cookie", cookie);
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
