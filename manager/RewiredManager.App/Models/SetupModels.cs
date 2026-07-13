namespace RewiredManager.App.Models;

public sealed record SetupReadiness(
    bool SteamFound,
    string? SteamPath,
    bool MillenniumPresent,
    bool OpenSteamToolPresent,
    bool PluginPresent,
    bool CanAddGames)
{
    public bool NeedsSetup => !CanAddGames || !PluginPresent;
}

public sealed class SetupOptions
{
    public required string SteamPath { get; init; }

    public bool InstallInSteamUi { get; init; } = true;

    public bool InstallOpenSteamTool { get; init; } = true;

    public bool CreateDesktopShortcut { get; init; } = true;
}

public sealed record SetupStepResult(bool Success, string Message);

public sealed record SetupResult(bool Success, string Summary, IReadOnlyList<string> Log);
