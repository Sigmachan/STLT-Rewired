namespace RewiredManager.App.Models;

public sealed record RyuuCatalogEntry(int AppId, string Name, string? ImageUrl, string Source);

public sealed record RyuuCatalogSearchResult(
    bool Success,
    string Message,
    IReadOnlyList<RyuuCatalogEntry> Results,
    int Total,
    bool UsedCatalogCache);
