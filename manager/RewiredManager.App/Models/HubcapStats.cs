namespace RewiredManager.App.Models;

public sealed record HubcapStatsResult(
    bool Success,
    string Message,
    string? Username,
    bool? CanMakeRequests,
    int? DailyUsage,
    int? DailyLimit);
