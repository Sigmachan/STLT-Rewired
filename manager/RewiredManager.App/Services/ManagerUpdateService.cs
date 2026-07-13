using System.Diagnostics;
using System.IO.Compression;
using System.Net.Http;
using System.Reflection;
using System.Text.Json;
using RewiredManager.App.Models;

namespace RewiredManager.App.Services;

public sealed record ManagerUpdateStatus(
    string CurrentVersion,
    string LatestVersion,
    bool UpdateAvailable,
    string ReleaseUrl,
    string? PluginZipUrl,
    string? ManagerZipUrl);

public sealed record ManagerUpdateResult(bool Success, string Message, string? InstalledExePath);

public sealed class ManagerUpdateService
{
    private const string Owner = "Sigmachan";
    private const string Repo = "STLT-Rewired";
    private const string ManagerAsset = "RewiredManager-win-x64-framework-dependent.zip";
    private const string PluginAsset = "STLT-Rewired.zip";
    private const string TagPrefix = "v";

    private static readonly HttpClient Http = CreateClient();

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("RewiredManager/1.0 (+https://github.com/Sigmachan/STLT-Rewired)");
        client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        return client;
    }

    public string GetCurrentManagerVersion()
    {
        var exe = Assembly.GetExecutingAssembly().Location;
        if (!string.IsNullOrEmpty(exe) && File.Exists(exe))
        {
            var info = FileVersionInfo.GetVersionInfo(exe);
            if (!string.IsNullOrWhiteSpace(info.ProductVersion))
                return info.ProductVersion.Split('+')[0];
        }
        return "0.0.0";
    }

    public async Task<ManagerUpdateStatus> CheckAsync(CancellationToken ct = default)
    {
        var release = await FetchLatestReleaseAsync(ct);
        var current = GetCurrentManagerVersion();
        var latest = StripTagPrefix(release.TagName);
        var cmp = CompareVersions(latest, current);
        return new ManagerUpdateStatus(
            current,
            latest,
            cmp > 0,
            release.HtmlUrl,
            release.PluginUrl,
            release.ManagerUrl);
    }

    public async Task<ManagerUpdateResult> ApplyManagerUpdateAsync(CancellationToken ct = default)
    {
        var status = await CheckAsync(ct);
        if (!status.UpdateAvailable)
            return new ManagerUpdateResult(true, $"Already on {status.CurrentVersion} (latest {status.LatestVersion}).", null);

        if (string.IsNullOrWhiteSpace(status.ManagerZipUrl))
            return new ManagerUpdateResult(false, "Latest release has no Manager zip asset.", null);

        var dest = RewiredConfigService.GetDefaultManagerInstallDir;
        var work = Path.Combine(Path.GetTempPath(), "rewired-mgr-upd-" + Guid.NewGuid().ToString("N"));
        var zipPath = Path.Combine(work, "manager.zip");
        try
        {
            Directory.CreateDirectory(work);
            await using (var stream = await Http.GetStreamAsync(status.ManagerZipUrl, ct))
            await using (var file = File.Create(zipPath))
                await stream.CopyToAsync(file, ct);

            if (Directory.Exists(dest))
                Directory.Delete(dest, recursive: true);

            ZipFile.ExtractToDirectory(zipPath, dest);
            var exe = Path.Combine(dest, "Rewired.exe");
            if (!File.Exists(exe))
                exe = Path.Combine(dest, "RewiredManager.App.exe");
            return new ManagerUpdateResult(true, $"Updated Manager to {status.LatestVersion}. Restart Rewired.", exe);
        }
        catch (Exception ex)
        {
            return new ManagerUpdateResult(false, ex.Message, null);
        }
        finally
        {
            try { if (Directory.Exists(work)) Directory.Delete(work, recursive: true); } catch { /* ignore */ }
        }
    }

    public async Task<(bool Success, string Message)> ApplyPluginUpdateAsync(string steamPath, CancellationToken ct = default)
    {
        var status = await CheckAsync(ct);
        if (string.IsNullOrWhiteSpace(status.PluginZipUrl))
            return (false, "No plugin zip on latest release.");

        var pluginRoot = Path.Combine(steamPath, "millennium", "plugins", "luatools");
        var work = Path.Combine(Path.GetTempPath(), "rewired-plugin-upd-" + Guid.NewGuid().ToString("N"));
        var zipPath = Path.Combine(work, "plugin.zip");
        var extract = Path.Combine(work, "extract");
        try
        {
            Directory.CreateDirectory(work);
            Directory.CreateDirectory(extract);
            await using (var stream = await Http.GetStreamAsync(status.PluginZipUrl, ct))
            await using (var file = File.Create(zipPath))
                await stream.CopyToAsync(file, ct);

            ZipFile.ExtractToDirectory(zipPath, extract);

            string? preserved = null;
            var liveData = Path.Combine(pluginRoot, "backend", "data");
            if (Directory.Exists(liveData))
            {
                preserved = Path.Combine(work, "preserved-data");
                CopyDirectory(liveData, preserved);
            }

            foreach (var name in new[] { "backend", "public", ".millennium", "plugin.json" })
            {
                var src = Path.Combine(extract, name);
                var dst = Path.Combine(pluginRoot, name);
                if (!Directory.Exists(src) && !File.Exists(src)) continue;
                if (Directory.Exists(dst)) Directory.Delete(dst, recursive: true);
                if (File.Exists(dst)) File.Delete(dst);
                if (Directory.Exists(src)) CopyDirectory(src, dst);
                else if (File.Exists(src)) File.Copy(src, dst, overwrite: true);
            }

            if (preserved != null && Directory.Exists(preserved))
            {
                var newData = Path.Combine(pluginRoot, "backend", "data");
                Directory.CreateDirectory(newData);
                CopyDirectory(preserved, newData);
            }

            return (true, $"Plugin updated to {status.LatestVersion}. Restart Steam.");
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
        Directory.CreateDirectory(dest);
        foreach (var file in Directory.GetFiles(source, "*", SearchOption.AllDirectories))
        {
            var rel = Path.GetRelativePath(source, file);
            var target = Path.Combine(dest, rel);
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            File.Copy(file, target, overwrite: true);
        }
    }

    private sealed record ReleaseInfo(string TagName, string HtmlUrl, string? PluginUrl, string? ManagerUrl);

    private async Task<ReleaseInfo> FetchLatestReleaseAsync(CancellationToken ct)
    {
        try
        {
            var token = Environment.GetEnvironmentVariable("GITHUB_TOKEN")
                ?? Environment.GetEnvironmentVariable("GH_TOKEN");
            using var request = new HttpRequestMessage(HttpMethod.Get,
                $"https://api.github.com/repos/{Owner}/{Repo}/releases/latest");
            request.Headers.UserAgent.ParseAdd("Rewired/1.0");
            request.Headers.Accept.ParseAdd("application/vnd.github+json");
            if (!string.IsNullOrWhiteSpace(token))
                request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);

            using var response = await Http.SendAsync(request, ct);
            var body = await response.Content.ReadAsStringAsync(ct);
            if (!response.IsSuccessStatusCode)
                throw new InvalidOperationException(body);

            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;
            var tag = root.GetProperty("tag_name").GetString() ?? "";
            var html = root.GetProperty("html_url").GetString() ?? "";
            string? plugin = null;
            string? manager = null;
            foreach (var asset in root.GetProperty("assets").EnumerateArray())
            {
                var name = asset.GetProperty("name").GetString() ?? "";
                var url = asset.GetProperty("browser_download_url").GetString();
                if (name == PluginAsset) plugin = url;
                if (name == ManagerAsset) manager = url;
            }
            return new ReleaseInfo(tag, html, plugin, manager);
        }
        catch
        {
            var baseUrl = $"https://github.com/{Owner}/{Repo}/releases/latest/download";
            return new ReleaseInfo(
                "latest",
                $"https://github.com/{Owner}/{Repo}/releases/latest",
                $"{baseUrl}/{PluginAsset}",
                $"{baseUrl}/{ManagerAsset}");
        }
    }

    private static string StripTagPrefix(string tag)
    {
        if (tag.StartsWith(TagPrefix, StringComparison.OrdinalIgnoreCase))
            return tag[TagPrefix.Length..];
        return tag;
    }

    private static int CompareVersions(string latest, string current)
    {
        static int[] Parse(string v)
        {
            var parts = v.Trim().TrimStart('v').Split('.');
            var nums = new int[3];
            for (var i = 0; i < 3; i++)
            {
                if (i < parts.Length && int.TryParse(parts[i], out var n)) nums[i] = n;
            }
            return nums;
        }
        var a = Parse(latest);
        var b = Parse(current);
        for (var i = 0; i < 3; i++)
        {
            if (a[i] > b[i]) return 1;
            if (a[i] < b[i]) return -1;
        }
        return 0;
    }
}
