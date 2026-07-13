using System.Diagnostics;
using System.Net.Http;
using System.Text.Json;

namespace RewiredManager.App.Services;

/// <summary>
/// Explicit CloudRedirect launcher — downloads on demand, never patches Steam silently.
/// </summary>
public sealed class CloudRedirectAssistantService
{
    private const string ReleasesApi = "https://api.github.com/repos/Selectively11/CloudRedirect/releases/latest";
    private static readonly string ToolDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Rewired",
        "cloudredirect");

    private static readonly HttpClient Http = CreateClient();
    private readonly SemaphoreSlim _gate = new(1, 1);

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(3) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("RewiredManager/1.0 (+https://github.com/Sigmachan/STLT-Rewired)");
        client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        return client;
    }

    public static string ExePath => Path.Combine(ToolDir, "CloudRedirect.exe");

    public CloudRedirectDetectResult Detect(string? steamPath)
    {
        var paths = new List<string>();
        if (!string.IsNullOrWhiteSpace(steamPath) && Directory.Exists(steamPath))
        {
            var dll = Path.Combine(steamPath, "cloud_redirect.dll");
            if (File.Exists(dll))
                paths.Add(dll);
        }

        if (File.Exists(ExePath))
            paths.Add(ExePath);

        var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        foreach (var candidate in new[]
        {
            Path.Combine(userProfile, "Downloads", "CloudRedirect.exe"),
            Path.Combine(userProfile, "Desktop", "CloudRedirect.exe"),
            @"C:\Program Files\CloudRedirect\CloudRedirect.exe",
            @"C:\Program Files (x86)\CloudRedirect\CloudRedirect.exe",
        })
        {
            if (File.Exists(candidate) && !paths.Contains(candidate, StringComparer.OrdinalIgnoreCase))
                paths.Add(candidate);
        }

        return new CloudRedirectDetectResult(paths.Count > 0, paths);
    }

    public async Task<CloudRedirectLaunchResult> LaunchAsync(CancellationToken ct = default)
    {
        var exe = await EnsureToolAsync(ct);
        if (exe == null)
            return new CloudRedirectLaunchResult(false, "Could not download CloudRedirect.exe from GitHub.");

        try
        {
            Process.Start(new ProcessStartInfo(exe)
            {
                UseShellExecute = true,
                WorkingDirectory = Path.GetDirectoryName(exe) ?? ToolDir,
            });
            return new CloudRedirectLaunchResult(true, "CloudRedirect launched. Configure saves in its UI — Rewired does not patch Steam cloud layers.");
        }
        catch (Exception ex)
        {
            return new CloudRedirectLaunchResult(false, "Launch failed: " + ex.Message);
        }
    }

    private async Task<string?> EnsureToolAsync(CancellationToken ct)
    {
        if (File.Exists(ExePath))
            return ExePath;

        await _gate.WaitAsync(ct);
        try
        {
            if (File.Exists(ExePath))
                return ExePath;

            var json = await Http.GetStringAsync(ReleasesApi, ct);
            using var doc = JsonDocument.Parse(json);
            string? downloadUrl = null;
            foreach (var asset in doc.RootElement.GetProperty("assets").EnumerateArray())
            {
                var name = asset.GetProperty("name").GetString() ?? "";
                if (name.Equals("CloudRedirect.exe", StringComparison.OrdinalIgnoreCase))
                {
                    downloadUrl = asset.GetProperty("browser_download_url").GetString();
                    break;
                }
            }

            if (string.IsNullOrWhiteSpace(downloadUrl))
                return null;

            Directory.CreateDirectory(ToolDir);
            await using var stream = await Http.GetStreamAsync(downloadUrl, ct);
            await using var file = File.Create(ExePath);
            await stream.CopyToAsync(file, ct);
            return File.Exists(ExePath) ? ExePath : null;
        }
        finally
        {
            _gate.Release();
        }
    }
}

public sealed record CloudRedirectDetectResult(bool Detected, IReadOnlyList<string> Paths);

public sealed record CloudRedirectLaunchResult(bool Success, string Message);
