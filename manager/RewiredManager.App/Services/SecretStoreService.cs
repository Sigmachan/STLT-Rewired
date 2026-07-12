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
