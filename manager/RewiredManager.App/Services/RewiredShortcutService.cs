namespace RewiredManager.App.Services;

public static class RewiredShortcutService
{
    public static void CreateOrUpdateDesktopShortcut(string exePath)
    {
        exePath = Path.GetFullPath(exePath);
        if (!File.Exists(exePath)) return;

        var desktop = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
        var lnk = Path.Combine(desktop, "Rewired.lnk");

        var shellType = Type.GetTypeFromProgID("WScript.Shell");
        if (shellType is null) return;

        dynamic shell = Activator.CreateInstance(shellType)!;
        dynamic shortcut = shell.CreateShortcut(lnk);
        shortcut.TargetPath = exePath;
        shortcut.WorkingDirectory = Path.GetDirectoryName(exePath) ?? "";
        shortcut.Description = "Rewired — unlock, add games, in-Steam UI";
        shortcut.Save();
    }
}
