using System.IO.Compression;
using System.Net.Http;

namespace RewiredManager.App.Services;

public sealed class MillenniumInstallService
{
    private const string DefaultVersion = "v3.4.0-beta.8";
    private static readonly HttpClient Http = CreateClient();

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("Rewired/1.0 (+https://github.com/Sigmachan/STLT-Rewired)");
        return client;
    }

    public bool IsInstalled(string steamPath)
    {
        steamPath = Path.GetFullPath(steamPath);
        var loader = Path.Combine(steamPath, "wsock32.dll");
        var millBin = Path.Combine(steamPath, "millennium", "bin");
        return File.Exists(loader) && Directory.Exists(millBin);
    }

    public async Task<(bool Success, string Message)> InstallAsync(string steamPath, CancellationToken ct = default)
    {
        steamPath = Path.GetFullPath(steamPath);
        if (!Directory.Exists(steamPath))
            return (false, "Steam path does not exist.");

        if (SteamProcessService.IsSteamRunningStatic())
            return (false, "Exit Steam fully before installing the in-Steam UI runtime.");

        if (IsInstalled(steamPath))
            return (true, "In-Steam UI runtime already installed.");

        var assetBase = $"millennium-{DefaultVersion}-windows-x86_64";
        var zipUrl = $"https://github.com/SteamClientHomebrew/Millennium/releases/download/{DefaultVersion}/{assetBase}.zip";
        var work = Path.Combine(Path.GetTempPath(), "rewired-millennium-" + Guid.NewGuid().ToString("N"));
        var zipPath = Path.Combine(work, assetBase + ".zip");
        var extract = Path.Combine(work, "extract");

        try
        {
            Directory.CreateDirectory(work);
            Directory.CreateDirectory(extract);

            await using (var stream = await Http.GetStreamAsync(zipUrl, ct))
            await using (var file = File.Create(zipPath))
                await stream.CopyToAsync(file, ct);

            ZipFile.ExtractToDirectory(zipPath, extract);

            var loader = Path.Combine(extract, "wsock32.dll");
            var bin = Path.Combine(extract, "millennium", "bin");
            var lib = Path.Combine(extract, "millennium", "lib");
            if (!File.Exists(loader) || !Directory.Exists(bin) || !Directory.Exists(lib))
                return (false, "Millennium archive layout unexpected.");

            File.Copy(loader, Path.Combine(steamPath, "wsock32.dll"), overwrite: true);
            var millRoot = Path.Combine(steamPath, "millennium");
            Directory.CreateDirectory(millRoot);
            CopyDirectory(bin, Path.Combine(millRoot, "bin"));
            CopyDirectory(lib, Path.Combine(millRoot, "lib"));

            return (true, $"Installed in-Steam UI runtime ({DefaultVersion}).");
        }
        catch (Exception ex)
        {
            return (false, ex.Message);
        }
        finally
        {
            try { if (Directory.Exists(work)) Directory.Delete(work, recursive: true); } catch { /* ignore */ }
        }
    }

    private static void CopyDirectory(string source, string dest)
    {
        if (Directory.Exists(dest)) Directory.Delete(dest, recursive: true);
        Directory.CreateDirectory(dest);
        foreach (var file in Directory.GetFiles(source, "*", SearchOption.AllDirectories))
        {
            var rel = Path.GetRelativePath(source, file);
            var target = Path.Combine(dest, rel);
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            File.Copy(file, target, overwrite: true);
        }
    }
}
