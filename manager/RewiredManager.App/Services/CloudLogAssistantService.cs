using System.Text.RegularExpressions;

namespace RewiredManager.App.Services;

public sealed class CloudLogAssistantService
{
    private static readonly Regex AppIdRegex = new(@"\bappid[=\s:]+(\d{4,})\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex BareAppIdRegex = new(@"\b(\d{5,7})\b", RegexOptions.Compiled);

    public CloudLogScanResult Scan(string? steamPath, int maxTailLines = 800)
    {
        if (string.IsNullOrWhiteSpace(steamPath))
            return new CloudLogScanResult(false, "Путь Steam не задан.", null, Array.Empty<CloudLogIssue>());

        var logPath = Path.Combine(steamPath, "logs", "cloud_log.txt");
        if (!File.Exists(logPath))
            return new CloudLogScanResult(false, $"Файл не найден: {logPath}", logPath, Array.Empty<CloudLogIssue>());

        try
        {
            var lines = TailLines(logPath, maxTailLines);
            var issues = ExtractIssues(lines);
            var summary = issues.Count == 0
                ? $"Последние {lines.Count} строк: явных cloud-ошибок не найдено."
                : $"Найдено проблем: {issues.Count} (последние {lines.Count} строк).";

            return new CloudLogScanResult(true, summary, logPath, issues);
        }
        catch (Exception ex)
        {
            return new CloudLogScanResult(false, ex.Message, logPath, Array.Empty<CloudLogIssue>());
        }
    }

    private static List<string> TailLines(string path, int maxLines)
    {
        var queue = new Queue<string>();
        foreach (var line in File.ReadLines(path))
        {
            queue.Enqueue(line);
            while (queue.Count > maxLines)
                queue.Dequeue();
        }
        return queue.ToList();
    }

    private static List<CloudLogIssue> ExtractIssues(IReadOnlyList<string> lines)
    {
        var issues = new List<CloudLogIssue>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        for (var i = 0; i < lines.Count; i++)
        {
            var line = lines[i];
            var lower = line.ToLowerInvariant();
            var kind = Classify(lower);
            if (kind == null) continue;

            var appId = ExtractAppId(line) ?? ExtractAppId(i > 0 ? lines[i - 1] : "") ?? ExtractAppId(i + 1 < lines.Count ? lines[i + 1] : "");
            var key = kind + "|" + (appId ?? "") + "|" + line.Trim();
            if (!seen.Add(key)) continue;

            issues.Add(new CloudLogIssue(kind, appId, line.Trim()));
        }

        return issues
            .OrderByDescending(i => i.Kind == "upload_denied")
            .ThenByDescending(i => i.Kind == "sync_failed")
            .Take(40)
            .ToList();
    }

    private static string? Classify(string lower)
    {
        if (lower.Contains("upload access denied")) return "upload_denied";
        if (lower.Contains("failed sync")) return "sync_failed";
        if (lower.Contains("cloud sync conflict")) return "sync_conflict";
        if (lower.Contains("cloud") && lower.Contains("error")) return "cloud_error";
        return null;
    }

    private static string? ExtractAppId(string line)
    {
        var m = AppIdRegex.Match(line);
        if (m.Success) return m.Groups[1].Value;
        if (!line.Contains("cloud", StringComparison.OrdinalIgnoreCase)) return null;
        m = BareAppIdRegex.Match(line);
        return m.Success ? m.Groups[1].Value : null;
    }
}

public sealed record CloudLogScanResult(
    bool Success,
    string Message,
    string? LogPath,
    IReadOnlyList<CloudLogIssue> Issues);

public sealed record CloudLogIssue(string Kind, string? AppId, string Line);
