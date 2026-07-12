namespace RewiredManager.App.Models;

public sealed record UnlockBackendStatus(
    string SteamPath,
    UnlockBackendKind Preference,
    UnlockBackendKind Resolved,
    string LuaScriptDir,
    string DepotCacheDir,
    bool OpenSteamToolDll,
    bool SteamToolsMarkers,
    bool LumaCoreDll,
    bool ReadyForAdd);

public sealed record GameInstallResult(bool Success, string Message, string? LuaPath);

public sealed record OpenSteamToolInstallResult(bool Success, string Message, IReadOnlyList<string> InstalledFiles);
