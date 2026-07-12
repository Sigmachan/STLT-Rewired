using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using RewiredManager.App.Models;

namespace RewiredManager.App.Services;

public sealed class RewiredConfigService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        WriteIndented = true
    };

    public static string ConfigDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Rewired");

    public static string ConfigPath => Path.Combine(ConfigDirectory, "rewired.json");

    public RewiredSharedConfig Load()
    {
        if (!File.Exists(ConfigPath))
        {
            return new RewiredSharedConfig
            {
                SteamPath = SteamInstallService.TryDetectSteamPath(),
                PluginPath = PluginDiscoveryService.DefaultLivePluginPath,
                RepoRoot = PluginDiscoveryService.DefaultRepoPath
            };
        }

        try
        {
            var json = File.ReadAllText(ConfigPath);
            var cfg = JsonSerializer.Deserialize<RewiredSharedConfig>(json, JsonOptions) ?? new RewiredSharedConfig();
            cfg.Version = RewiredSharedConfig.CurrentVersion;
            if (string.IsNullOrWhiteSpace(cfg.SteamPath))
                cfg.SteamPath = SteamInstallService.TryDetectSteamPath();
            if (string.IsNullOrWhiteSpace(cfg.PluginPath))
                cfg.PluginPath = PluginDiscoveryService.DefaultLivePluginPath;
            if (string.IsNullOrWhiteSpace(cfg.RepoRoot))
                cfg.RepoRoot = PluginDiscoveryService.DefaultRepoPath;
            return cfg;
        }
        catch
        {
            return new RewiredSharedConfig
            {
                SteamPath = SteamInstallService.TryDetectSteamPath(),
                PluginPath = PluginDiscoveryService.DefaultLivePluginPath,
                RepoRoot = PluginDiscoveryService.DefaultRepoPath
            };
        }
    }

    public void Save(RewiredSharedConfig config)
    {
        config.Version = RewiredSharedConfig.CurrentVersion;
        Directory.CreateDirectory(ConfigDirectory);
        var json = JsonSerializer.Serialize(config, JsonOptions);
        File.WriteAllText(ConfigPath, json);
    }
}
