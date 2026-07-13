namespace RewiredManager.App.Models;

public sealed record UnlockModeStatus(
    string Name,
    string Description,
    bool Active,
    bool Detected,
    string Detail);
