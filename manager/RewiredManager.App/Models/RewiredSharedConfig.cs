namespace RewiredManager.App.Models;

public sealed class RewiredSharedConfig
{
    public const int CurrentVersion = 1;

    public int Version { get; set; } = CurrentVersion;

    public string? SteamPath { get; set; }

    public string UnlockBackend { get; set; } = "auto";

    public bool MillenniumOptional { get; set; } = true;

    public string? PluginPath { get; set; }

    public string? RepoRoot { get; set; }

    public UnlockBackendKind BackendKind
    {
        get => UnlockBackendKindExtensions.FromConfigValue(UnlockBackend);
        set => UnlockBackend = value.ToConfigValue();
    }
}
