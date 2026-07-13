using System.Diagnostics;
using RewiredManager.App.Models;

namespace RewiredManager.App.Services;

public sealed class MillenniumInfoService
{
    public const string TargetVersion = "3.4.0-beta.8";

    public MillenniumInfo Inspect(string? steamPath)
    {
        if (string.IsNullOrWhiteSpace(steamPath))
            return new MillenniumInfo(false, "unknown", TargetVersion, false, null);

        var millenniumDir = Path.Combine(steamPath, "millennium");
        if (!Directory.Exists(millenniumDir))
            return new MillenniumInfo(false, "not installed", TargetVersion, false, millenniumDir);

        var version = ReadVersion(millenniumDir);
        var compatible = CompareVersion(version, TargetVersion) >= 0;
        return new MillenniumInfo(true, version, TargetVersion, compatible, millenniumDir);
    }

    private static string ReadVersion(string millenniumDir)
    {
        foreach (var candidate in new[]
        {
            Path.Combine(millenniumDir, "version.txt"),
            Path.Combine(millenniumDir, "VERSION"),
        })
        {
            if (!File.Exists(candidate)) continue;
            var text = File.ReadAllText(candidate).Trim();
            if (!string.IsNullOrWhiteSpace(text))
                return text.Split('\n')[0].Trim();
        }

        foreach (var dll in Directory.EnumerateFiles(millenniumDir, "*.dll", SearchOption.TopDirectoryOnly))
        {
            try
            {
                var info = FileVersionInfo.GetVersionInfo(dll);
                var product = info.ProductVersion ?? info.FileVersion;
                if (!string.IsNullOrWhiteSpace(product))
                    return product.Trim();
            }
            catch
            {
                // try next
            }
        }

        return "unknown";
    }

    private static int CompareVersion(string left, string right)
    {
        if (left == "unknown") return -1;
        var l = left.TrimStart('v', 'V').Split('.', '-', '+');
        var r = right.TrimStart('v', 'V').Split('.', '-', '+');
        var count = Math.Max(l.Length, r.Length);
        for (var i = 0; i < count; i++)
        {
            var ls = i < l.Length ? l[i] : "0";
            var rs = i < r.Length ? r[i] : "0";
            var li = int.TryParse(RegexDigits(ls), out var ln) ? ln : 0;
            var ri = int.TryParse(RegexDigits(rs), out var rn) ? rn : 0;
            if (li != ri) return li.CompareTo(ri);
            var lsSuffix = ls.Replace(li.ToString(), "");
            var rsSuffix = rs.Replace(ri.ToString(), "");
            var suffixCmp = string.Compare(lsSuffix, rsSuffix, StringComparison.OrdinalIgnoreCase);
            if (suffixCmp != 0) return suffixCmp;
        }
        return 0;
    }

    private static string RegexDigits(string input) => new string(input.TakeWhile(char.IsDigit).ToArray());
}
