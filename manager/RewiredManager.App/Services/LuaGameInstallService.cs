using System.IO.Compression;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.RegularExpressions;
using RewiredManager.App.Models;

namespace RewiredManager.App.Services;

public sealed class LuaGameInstallService
{
    private const string RyuuDownloadUrlTemplate = "https://generator.ryuu.lol/api/download/{0}";
    private static readonly HttpClient Http = CreateClient();

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("RewiredManager/1.0 (+https://github.com/Sigmachan/STLT-Rewired)");
        return client;
    }

    public async Task<GameInstallResult> InstallFromRyuuAsync(
        int appId,
        UnlockBackendStatus unlock,
        string? ryuuCookieHeader,
        CancellationToken ct = default)
    {
        if (appId <= 0)
            return new GameInstallResult(false, "Invalid AppID.", null);

        new UnlockBackendService().EnsureDirectories(unlock);

        var tempRoot = Path.Combine(Path.GetTempPath(), "rewired-add-" + Guid.NewGuid().ToString("N"));
        var zipPath = Path.Combine(tempRoot, appId + ".zip");
        var extractDir = Path.Combine(tempRoot, "extracted");
        try
        {
            Directory.CreateDirectory(tempRoot);
            Directory.CreateDirectory(extractDir);

            var url = string.Format(RyuuDownloadUrlTemplate, appId);
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            if (!string.IsNullOrWhiteSpace(ryuuCookieHeader))
                request.Headers.TryAddWithoutValidation("Cookie", ryuuCookieHeader);

            using var response = await Http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
            if (!response.IsSuccessStatusCode)
            {
                var body = await response.Content.ReadAsStringAsync(ct);
                var snippet = body.Length > 200 ? body[..200] + "…" : body;
                return new GameInstallResult(false, $"Ryuu download failed: HTTP {(int)response.StatusCode} {snippet}", null);
            }

            await using (var stream = await response.Content.ReadAsStreamAsync(ct))
            await using (var file = File.Create(zipPath))
                await stream.CopyToAsync(file, ct);

            ZipFile.ExtractToDirectory(zipPath, extractDir);

            string? luaSource = null;
            foreach (var file in Directory.EnumerateFiles(extractDir, "*.lua", SearchOption.AllDirectories))
            {
                var name = Path.GetFileName(file);
                if (name == appId + ".lua" || Regex.IsMatch(name, @"^\d+\.lua$"))
                {
                    luaSource = file;
                    if (name == appId + ".lua") break;
                }
            }

            foreach (var manifest in Directory.EnumerateFiles(extractDir, "*.manifest", SearchOption.AllDirectories))
            {
                var dest = Path.Combine(unlock.DepotCacheDir, Path.GetFileName(manifest));
                File.Copy(manifest, dest, overwrite: true);
            }

            if (luaSource == null)
                return new GameInstallResult(false, "Archive did not contain a .lua file.", null);

            var text = await File.ReadAllTextAsync(luaSource, ct);
            text = CommentOutSetManifestIdLines(text);
            var targetLua = Path.Combine(unlock.LuaScriptDir, appId + ".lua");
            await File.WriteAllTextAsync(targetLua, text, Encoding.UTF8, ct);

            return new GameInstallResult(true, $"Installed {appId}.lua → {targetLua}", targetLua);
        }
        catch (Exception ex)
        {
            return new GameInstallResult(false, ex.Message, null);
        }
        finally
        {
            try { if (Directory.Exists(tempRoot)) Directory.Delete(tempRoot, recursive: true); } catch { /* ignore */ }
        }
    }

    internal static string CommentOutSetManifestIdLines(string text)
    {
        var lines = text.Replace("\r\n", "\n").Split('\n');
        for (var i = 0; i < lines.Length; i++)
        {
            if (Regex.IsMatch(lines[i], @"^\s*setManifestid\s*\(", RegexOptions.IgnoreCase)
                && !Regex.IsMatch(lines[i], @"^\s*--"))
            {
                lines[i] = Regex.Replace(lines[i], @"^(\s*)(setManifestid)", "$1-- $2", RegexOptions.IgnoreCase);
            }
        }
        return string.Join(Environment.NewLine, lines);
    }
}
