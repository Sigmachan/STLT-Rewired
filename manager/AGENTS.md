## Manager scope

C# WPF control plane → `Rewired.exe`. See `manager/docs/REWIRED_MANAGER_ARCHITECTURE.md`.

- Config: `%LOCALAPPDATA%\Rewired\rewired.json`
- Build: `pwsh -NoProfile -File manager/scripts/publish-manager.ps1`
- UI theme: `Themes/SteamDarkTheme.xaml` — Steam dark 1:1
- UX parity reference: `E:\LuaTools-win-Portable` (LuaTools v1.2.2) — sidebar IA Home/Add/Manage/Mode/Fixes/Plugin; Steam Original dark, not LuaTools purple WPF-UI

Services live in `RewiredManager.App/Services/`. Keep code-behind thin.
