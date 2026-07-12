using System.IO;
using System.Text.Json;

namespace RewiredManager.App.Services;

public sealed record SecretShape(bool Exists, bool HasRyuuSession, bool HasMorrenusKey);

public sealed class SecretStoreService
{
    public static string GetSecretsPath(string pluginRoot) => Path.Combine(pluginRoot, "backend", "data", "secrets.local.json");

    public SecretShape ReadSecretShape(string pluginRoot)
    {
        var path = GetSecretsPath(pluginRoot);
        if (!File.Exists(path)) return new SecretShape(false, false, false);

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(path));
            var root = doc.RootElement;
            var hasRyuu = root.TryGetProperty("ryuuSession", out var ryuu)
                && ryuu.ValueKind == JsonValueKind.String
                && !string.IsNullOrWhiteSpace(ryuu.GetString());
            var hasMorrenus = HasNonEmptyString(root, "morrenusApiKey")
                || HasNonEmptyString(root, "manifestHubApiKey");
            return new SecretShape(true, hasRyuu, hasMorrenus);
        }
        catch
        {
            return new SecretShape(true, false, false);
        }
    }

    private static bool HasNonEmptyString(JsonElement root, string property)
    {
        return root.TryGetProperty(property, out var value)
            && value.ValueKind == JsonValueKind.String
            && !string.IsNullOrWhiteSpace(value.GetString());
    }

    public string? ReadRyuuCookieHeader(string pluginRoot)
    {
        var path = GetSecretsPath(pluginRoot);
        if (!File.Exists(path)) return null;

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(path));
            if (!doc.RootElement.TryGetProperty("ryuuSession", out var value)) return null;
            var cookie = value.GetString();
            return string.IsNullOrWhiteSpace(cookie) ? null : cookie;
        }
        catch
        {
            return null;
        }
    }
}
