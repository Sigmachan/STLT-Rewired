using System.Diagnostics;
using System.IO.Compression;
using System.Text.RegularExpressions;
using RewiredManager.App.Models;

namespace RewiredManager.App.Services;

public sealed class LocalFileInstallService
{
    public async Task<GameInstallResult> InstallFromFileAsync(
        string filePath,
        UnlockBackendStatus unlock,
        CancellationToken ct = default)
    {
        if (!File.Exists(filePath))
            return new GameInstallResult(false, "File not found.", null);

        new UnlockBackendService().EnsureDirectories(unlock);
        var ext = Path.GetExtension(filePath).ToLowerInvariant();

        return ext switch
        {
            ".zip" => await InstallZipAsync(filePath, unlock, ct),
            ".lua" => await InstallLuaAsync(filePath, unlock, ct),
            ".manifest" => InstallManifest(filePath, unlock),
            _ => new GameInstallResult(false, "Unsupported file type. Use .lua, .manifest, or .zip.", null)
        };
    }

    private static async Task<GameInstallResult> InstallLuaAsync(string filePath, UnlockBackendStatus unlock, CancellationToken ct)
    {
        var fileName = Path.GetFileName(filePath);
        var match = Regex.Match(fileName, @"^(\d+)\.lua$", RegexOptions.IgnoreCase);
        if (!match.Success)
            return new GameInstallResult(false, "Lua file must be named like 12345.lua.", null);

        var appId = int.Parse(match.Groups[1].Value);
        var text = await File.ReadAllTextAsync(filePath, ct);
        text = LuaGameInstallService.CommentOutSetManifestIdLines(text);
        var target = Path.Combine(unlock.LuaScriptDir, appId + ".lua");
        await File.WriteAllTextAsync(target, text, ct);
        return new GameInstallResult(true, $"Installed {appId}.lua from local file.", target);
    }

    private static GameInstallResult InstallManifest(string filePath, UnlockBackendStatus unlock)
    {
        var dest = Path.Combine(unlock.DepotCacheDir, Path.GetFileName(filePath));
        File.Copy(filePath, dest, overwrite: true);
        return new GameInstallResult(true, $"Copied manifest → {dest}", dest);
    }

    private static async Task<GameInstallResult> InstallZipAsync(string filePath, UnlockBackendStatus unlock, CancellationToken ct)
    {
        var tempRoot = Path.Combine(Path.GetTempPath(), "rewired-local-" + Guid.NewGuid().ToString("N"));
        var extractDir = Path.Combine(tempRoot, "extracted");
        try
        {
            Directory.CreateDirectory(extractDir);
            ZipFile.ExtractToDirectory(filePath, extractDir);

            string? luaSource = null;
            int? appId = null;
            foreach (var file in Directory.EnumerateFiles(extractDir, "*.lua", SearchOption.AllDirectories))
            {
                var name = Path.GetFileName(file);
                var match = Regex.Match(name, @"^(\d+)\.lua$");
                if (!match.Success) continue;
                luaSource = file;
                appId = int.Parse(match.Groups[1].Value);
                break;
            }

            foreach (var manifest in Directory.EnumerateFiles(extractDir, "*.manifest", SearchOption.AllDirectories))
            {
                var dest = Path.Combine(unlock.DepotCacheDir, Path.GetFileName(manifest));
                File.Copy(manifest, dest, overwrite: true);
            }

            if (luaSource == null || !appId.HasValue)
                return new GameInstallResult(false, "Archive did not contain a numbered .lua file.", null);

            var text = await File.ReadAllTextAsync(luaSource, ct);
            text = LuaGameInstallService.CommentOutSetManifestIdLines(text);
            var targetLua = Path.Combine(unlock.LuaScriptDir, appId.Value + ".lua");
            await File.WriteAllTextAsync(targetLua, text, ct);
            return new GameInstallResult(true, $"Installed {appId.Value}.lua from zip.", targetLua);
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
}
