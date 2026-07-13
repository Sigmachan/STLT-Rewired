namespace RewiredManager.App.Models;

public sealed record MillenniumInfo(
    bool Installed,
    string Version,
    string TargetVersion,
    bool VersionCompatible,
    string? InstallPath);
