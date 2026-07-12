using System.Text.Json;

namespace RewiredManager.Core;

/// <summary>
/// Locates Steam, Millennium, and the live STLT-Rewired (luatools) plugin install.
/// Mirrors deploy.ps1 path assumptions.
/// </summary>
public sealed class PluginLocator
{
    public string? SteamPath { get; private set; }
    public string? PluginPath { get; private set; }
    public string? SecretsPath { get; private set; }
    public string? SettingsPath { get; private set; }

    public bool TryLocate(string? steamPathOverride = null)
    {
        SteamPath = steamPathOverride ?? TryFindSteamPath();
        if (string.IsNullOrWhiteSpace(SteamPath))
            return false;

        PluginPath = Path.Combine(SteamPath, "millennium", "plugins", "luatools");
        if (!Directory.Exists(PluginPath))
            return false;

        var dataDir = Path.Combine(PluginPath, "backend", "data");
        SecretsPath = Path.Combine(dataDir, "secrets.local.json");
        SettingsPath = Path.Combine(dataDir, "settings.json");
        return true;
    }

    public PluginInfo? ReadPluginInfo()
    {
        if (PluginPath is null)
            return null;

        var pluginJson = Path.Combine(PluginPath, "plugin.json");
        if (!File.Exists(pluginJson))
            return null;

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(pluginJson));
            var root = doc.RootElement;
            return new PluginInfo(
                Name: root.GetProperty("name").GetString() ?? "luatools",
                CommonName: root.TryGetProperty("common_name", out var cn) ? cn.GetString() : null,
                Version: root.TryGetProperty("version", out var v) ? v.GetString() : null,
                PluginPath: PluginPath);
        }
        catch
        {
            return null;
        }
    }

    private static string? TryFindSteamPath()
    {
        var candidates = new[]
        {
            Environment.GetEnvironmentVariable("STEAM_PATH"),
            @"C:\Program Files (x86)\Steam",
            @"C:\Program Files\Steam",
        };

        foreach (var c in candidates)
        {
            if (string.IsNullOrWhiteSpace(c))
                continue;
            if (File.Exists(Path.Combine(c, "steam.exe")))
                return c;
        }

        return null;
    }
}

public sealed record PluginInfo(string Name, string? CommonName, string? Version, string PluginPath);
