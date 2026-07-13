using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using RewiredManager.App.Models;

namespace RewiredManager.App.Services;

public sealed record SecretShape(bool Exists, bool HasRyuuSession, bool HasMorrenusKey);

public sealed class SecretStoreService
{
    public static string GetSecretsPath(string pluginRoot) => Path.Combine(pluginRoot, "backend", "data", "secrets.local.json");

    public PluginSecrets Load(string pluginRoot)
    {
        var path = GetSecretsPath(pluginRoot);
        var secrets = ReadSecretsFile(path);
        secrets = MergeLegacySettingsSecrets(pluginRoot, secrets);
        return secrets;
    }

    private static PluginSecrets ReadSecretsFile(string path)
    {
        if (!File.Exists(path))
            return new PluginSecrets(path, "", "");

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(path));
            var root = doc.RootElement;
            var ryuu = ReadString(root, "ryuuSession");
            var hub = ReadString(root, "morrenusApiKey");
            if (hub == "") hub = ReadString(root, "manifestHubApiKey");
            return new PluginSecrets(path, ryuu, hub);
        }
        catch
        {
            return new PluginSecrets(path, "", "");
        }
    }

    /// <summary>
    /// STLT 10.x stored Ryuu/ManifestHub keys in backend/data/settings.json; Rewired prefers secrets.local.json.
    /// </summary>
    private PluginSecrets MergeLegacySettingsSecrets(string pluginRoot, PluginSecrets current)
    {
        var ryuu = current.RyuuSession;
        var hub = current.ManifestHubKey;
        if (!string.IsNullOrWhiteSpace(ryuu) && !string.IsNullOrWhiteSpace(hub))
            return current;

        var settingsPath = Path.Combine(pluginRoot, "backend", "data", "settings.json");
        if (!File.Exists(settingsPath))
            return current;

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(settingsPath));
            if (!doc.RootElement.TryGetProperty("general", out var general))
                return current;

            if (string.IsNullOrWhiteSpace(ryuu))
                ryuu = ReadString(general, "ryuuSession");
            if (string.IsNullOrWhiteSpace(hub))
            {
                hub = ReadString(general, "morrenusApiKey");
                if (hub == "") hub = ReadString(general, "manifestHubApiKey");
            }

            if (string.IsNullOrWhiteSpace(ryuu) && string.IsNullOrWhiteSpace(hub))
                return current;

            var merged = new PluginSecrets(current.SecretsPath, ryuu, hub);
            var shouldPersist = !File.Exists(current.SecretsPath)
                || (string.IsNullOrWhiteSpace(current.RyuuSession) && !string.IsNullOrWhiteSpace(ryuu))
                || (string.IsNullOrWhiteSpace(current.ManifestHubKey) && !string.IsNullOrWhiteSpace(hub));
            if (shouldPersist)
                Save(pluginRoot, merged.RyuuSession, merged.ManifestHubKey);
            return merged;
        }
        catch
        {
            return current;
        }
    }

    public void Save(string pluginRoot, string ryuuSession, string manifestHubKey)
    {
        var path = GetSecretsPath(pluginRoot);
        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);

        JsonObject root;
        if (File.Exists(path))
        {
            try
            {
                root = JsonNode.Parse(File.ReadAllText(path))?.AsObject() ?? new JsonObject();
            }
            catch
            {
                root = new JsonObject();
            }
        }
        else
        {
            root = new JsonObject();
        }

        root["ryuuSession"] = ryuuSession.Trim();
        root["morrenusApiKey"] = manifestHubKey.Trim();
        root["manifestHubApiKey"] = manifestHubKey.Trim();

        File.WriteAllText(path, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    }

    public SecretShape ReadSecretShape(string pluginRoot)
    {
        var loaded = Load(pluginRoot);
        return new SecretShape(
            File.Exists(loaded.SecretsPath),
            !string.IsNullOrWhiteSpace(loaded.RyuuSession),
            !string.IsNullOrWhiteSpace(loaded.ManifestHubKey));
    }

    public string? ReadRyuuCookieHeader(string pluginRoot)
    {
        var session = Load(pluginRoot).RyuuSession;
        return string.IsNullOrWhiteSpace(session) ? null : session;
    }

    private static string ReadString(JsonElement root, string property)
    {
        return root.TryGetProperty(property, out var value)
            && value.ValueKind == JsonValueKind.String
            ? value.GetString() ?? ""
            : "";
    }
}
