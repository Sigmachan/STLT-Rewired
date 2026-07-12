using System.IO;
using System.Text.Json;
using RewiredManager.App.Models;

namespace RewiredManager.App.Services;

public sealed class PluginDiscoveryService
{
    public static readonly string DefaultLivePluginPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
        "Steam", "millennium", "plugins", "luatools");

    /// <summary>Dev checkout root when running from STLT-Rewired/manager (optional).</summary>
    public static string DefaultRepoPath =>
        Environment.GetEnvironmentVariable("STLT_REWIRED_ROOT")
        ?? Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", ".."));

    public PluginDiscoveryResult Inspect(string? path)
    {
        var pluginPath = string.IsNullOrWhiteSpace(path) ? DefaultLivePluginPath : path.Trim();
        var root = new DirectoryInfo(pluginPath);
        var pluginJson = Path.Combine(root.FullName, "plugin.json");
        var backend = Path.Combine(root.FullName, "backend", "main.lua");
        var bundle = Path.Combine(root.FullName, ".millennium", "Dist", "webkit.js");
        var secrets = SecretStoreService.GetSecretsPath(root.FullName);

        var version = "unknown";
        var commonName = "unknown";
        if (File.Exists(pluginJson))
        {
            try
            {
                using var doc = JsonDocument.Parse(File.ReadAllText(pluginJson));
                var rootElement = doc.RootElement;
                if (rootElement.TryGetProperty("version", out var v)) version = v.GetString() ?? version;
                if (rootElement.TryGetProperty("common_name", out var n)) commonName = n.GetString() ?? commonName;
            }
            catch
            {
                version = "unreadable plugin.json";
            }
        }

        var secretStore = new SecretStoreService();
        var snapshot = secretStore.ReadSecretShape(root.FullName);

        return new PluginDiscoveryResult(
            root.FullName,
            root.Exists,
            File.Exists(pluginJson),
            File.Exists(backend),
            File.Exists(bundle),
            File.Exists(secrets),
            snapshot.HasRyuuSession,
            snapshot.HasMorrenusKey,
            version,
            commonName);
    }
}
