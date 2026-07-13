using RewiredManager.App.Models;

namespace RewiredManager.App.Services;

public sealed class InstalledInventoryService
{
    public InstalledInventorySummary Scan(UnlockBackendStatus status)
    {
        var luaScripts = ListFiles(status.LuaScriptDir, "*.lua");
        var manifests = ListFiles(status.DepotCacheDir, "*.manifest");
        return new InstalledInventorySummary(
            status.LuaScriptDir,
            status.DepotCacheDir,
            luaScripts,
            manifests);
    }

    public string GetLuaFullPath(UnlockBackendStatus status, string fileName)
        => Path.Combine(status.LuaScriptDir, fileName);

    public (bool Success, string Message) RemoveLuaScript(UnlockBackendStatus status, string fileName)
    {
        if (string.IsNullOrWhiteSpace(fileName))
            return (false, "No script selected.");

        var safeName = Path.GetFileName(fileName);
        if (!safeName.EndsWith(".lua", StringComparison.OrdinalIgnoreCase))
            return (false, "Only .lua scripts can be removed here.");

        var fullPath = GetLuaFullPath(status, safeName);
        if (!File.Exists(fullPath))
            return (false, "Script not found: " + safeName);

        File.Delete(fullPath);
        return (true, "Removed " + safeName);
    }

    public static void OpenFolder(string? directory)
    {
        if (string.IsNullOrWhiteSpace(directory) || !Directory.Exists(directory))
            throw new InvalidOperationException("Folder does not exist.");

        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
        {
            FileName = directory,
            UseShellExecute = true
        });
    }

    private static IReadOnlyList<string> ListFiles(string directory, string pattern)
    {
        if (!Directory.Exists(directory))
            return Array.Empty<string>();

        return Directory.GetFiles(directory, pattern)
            .Select(Path.GetFileName)
            .Where(n => !string.IsNullOrWhiteSpace(n))
            .Cast<string>()
            .OrderBy(n => n, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }
}

public sealed record InstalledInventorySummary(
    string LuaDirectory,
    string DepotCacheDirectory,
    IReadOnlyList<string> LuaScripts,
    IReadOnlyList<string> Manifests);
