using System.IO.Compression;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using RewiredManager.App.Models;

namespace RewiredManager.App.Services;

public sealed class OpenSteamToolInstallService
{
    private const string ReleasesApi = "https://api.github.com/repos/OpenSteam001/OpenSteamTool/releases/latest";
    private static readonly HttpClient Http = CreateClient();

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("RewiredManager/1.0 (+https://github.com/Sigmachan/STLT-Rewired)");
        client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        return client;
    }

    public async Task<OpenSteamToolInstallResult> InstallLatestAsync(string steamPath, CancellationToken ct = default)
    {
        steamPath = Path.GetFullPath(steamPath);
        if (!Directory.Exists(steamPath))
            return new OpenSteamToolInstallResult(false, "Steam path does not exist.", Array.Empty<string>());

        var releaseJson = await Http.GetStringAsync(ReleasesApi, ct);
        using var doc = JsonDocument.Parse(releaseJson);
        var assets = doc.RootElement.GetProperty("assets");
        string? zipUrl = null;
        foreach (var asset in assets.EnumerateArray())
        {
            var name = asset.GetProperty("name").GetString() ?? "";
            if (name.Contains("Release", StringComparison.OrdinalIgnoreCase)
                && name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)
                && !name.Contains("Debug", StringComparison.OrdinalIgnoreCase))
            {
                zipUrl = asset.GetProperty("browser_download_url").GetString();
                break;
            }
        }

        if (string.IsNullOrWhiteSpace(zipUrl))
            return new OpenSteamToolInstallResult(false, "No OpenSteamTool Release zip found on GitHub.", Array.Empty<string>());

        var tempZip = Path.Combine(Path.GetTempPath(), "rewired-ost-" + Guid.NewGuid().ToString("N") + ".zip");
        var tempDir = Path.Combine(Path.GetTempPath(), "rewired-ost-" + Guid.NewGuid().ToString("N"));
        try
        {
            await using (var stream = await Http.GetStreamAsync(zipUrl, ct))
            await using (var file = File.Create(tempZip))
                await stream.CopyToAsync(file, ct);

            Directory.CreateDirectory(tempDir);
            ZipFile.ExtractToDirectory(tempZip, tempDir);

            var wanted = new[] { "dwmapi.dll", "xinput1_4.dll", "OpenSteamTool.dll" };
            var installed = new List<string>();
            foreach (var fileName in wanted)
            {
                var source = FindFileRecursive(tempDir, fileName);
                if (source == null)
                    return new OpenSteamToolInstallResult(false, $"Missing {fileName} in release archive.", installed);

                var dest = Path.Combine(steamPath, fileName);
                File.Copy(source, dest, overwrite: true);
                installed.Add(dest);
            }

            Directory.CreateDirectory(Path.Combine(steamPath, "config", "lua"));
            return new OpenSteamToolInstallResult(true, "OpenSteamTool installed. Restart Steam from Rewired Manager.", installed);
        }
        finally
        {
            try { if (File.Exists(tempZip)) File.Delete(tempZip); } catch { /* ignore */ }
            try { if (Directory.Exists(tempDir)) Directory.Delete(tempDir, recursive: true); } catch { /* ignore */ }
        }
    }

    private static string? FindFileRecursive(string root, string fileName)
    {
        foreach (var path in Directory.EnumerateFiles(root, fileName, SearchOption.AllDirectories))
            return path;
        return null;
    }
}
