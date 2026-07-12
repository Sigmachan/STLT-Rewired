namespace RewiredManager.App.Models;

public sealed record PluginSecrets(
    string SecretsPath,
    string RyuuSession,
    string ManifestHubKey);

public sealed record SecretValidationResult(bool Success, string Message);
