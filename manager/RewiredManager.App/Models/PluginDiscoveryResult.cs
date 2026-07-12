namespace RewiredManager.App.Models;

public sealed record PluginDiscoveryResult(
    string PluginPath,
    bool Exists,
    bool HasPluginJson,
    bool HasBackend,
    bool HasFrontendBundle,
    bool HasSecretsFile,
    bool HasRyuuSession,
    bool HasMorrenusKey,
    string Version,
    string CommonName)
{
    public bool LooksUsable => Exists && HasPluginJson && HasBackend;
}
