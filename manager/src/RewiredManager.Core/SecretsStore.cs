using System.Text.Json;
using System.Text.Json.Nodes;

namespace RewiredManager.Core;

/// <summary>
/// Read/write plugin secrets.local.json without logging values.
/// Keys align with backend/settings/manager.lua.
/// </summary>
public sealed class SecretsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = null,
    };

    private readonly string _path;

    public SecretsStore(string secretsFilePath)
    {
        _path = secretsFilePath;
    }

    public SecretsSnapshot Load()
    {
        if (!File.Exists(_path))
            return new SecretsSnapshot(false, false);

        try
        {
            var node = JsonNode.Parse(File.ReadAllText(_path)) as JsonObject ?? new JsonObject();
            var ryuu = node["ryuuSession"]?.GetValue<string>();
            var hub = node["morrenusApiKey"]?.GetValue<string>() ?? node["manifestHubApiKey"]?.GetValue<string>();
            return new SecretsSnapshot(
                HasRyuuSession: !string.IsNullOrWhiteSpace(ryuu),
                HasManifestHubKey: !string.IsNullOrWhiteSpace(hub));
        }
        catch
        {
            return new SecretsSnapshot(false, false);
        }
    }

    public void Save(string? ryuuSession, string? manifestHubKey)
    {
        var dir = Path.GetDirectoryName(_path);
        if (!string.IsNullOrEmpty(dir))
            Directory.CreateDirectory(dir);

        JsonObject node;
        if (File.Exists(_path))
        {
            node = JsonNode.Parse(File.ReadAllText(_path)) as JsonObject ?? new JsonObject();
        }
        else
        {
            node = new JsonObject();
        }

        if (ryuuSession is not null)
        {
            if (string.IsNullOrWhiteSpace(ryuuSession))
                node.Remove("ryuuSession");
            else
                node["ryuuSession"] = ryuuSession;
        }

        if (manifestHubKey is not null)
        {
            if (string.IsNullOrWhiteSpace(manifestHubKey))
            {
                node.Remove("morrenusApiKey");
                node.Remove("manifestHubApiKey");
            }
            else
            {
                node["morrenusApiKey"] = manifestHubKey;
            }
        }

        File.WriteAllText(_path, node.ToJsonString(JsonOptions));
    }
}

public sealed record SecretsSnapshot(bool HasRyuuSession, bool HasManifestHubKey);
