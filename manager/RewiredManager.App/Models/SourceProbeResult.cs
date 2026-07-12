namespace RewiredManager.App.Models;

public sealed record SourceProbeResult(
    string Name,
    string Url,
    bool Success,
    int? StatusCode,
    string Message,
    TimeSpan Duration);
