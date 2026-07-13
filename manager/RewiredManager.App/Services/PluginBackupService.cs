using System.Diagnostics;
using RewiredManager.App.Models;

namespace RewiredManager.App.Services;

public sealed class PluginBackupService
{
    public IReadOnlyList<PluginBackupEntry> ListBackups(string steamPath)
    {
        var root = Path.Combine(steamPath, "millennium", "_plugin-backups");
        if (!Directory.Exists(root))
            return Array.Empty<PluginBackupEntry>();

        return Directory.GetDirectories(root, "luatools.backup-*")
            .Select(path => new DirectoryInfo(path))
            .OrderByDescending(d => d.CreationTimeUtc)
            .Select(d => new PluginBackupEntry(d.Name, d.FullName, d.CreationTimeUtc))
            .ToList();
    }
}
