# Microsoft-Bloatware-Removal-PSModule

A PowerShell tool that removes common Windows inbox bloatware and disables
intrusive UI features (Copilot, Widgets, sponsored Start menu pins, Start
menu web search, OneDrive auto-startup). No installation needed - just
download and run.

**Requires Windows 10/11 and PowerShell.** Both entry points prompt for
Administrator elevation automatically when run from a saved `.ps1` file.

## Remove-MSBloat-GUI.ps1 (recommended for most people)

A graphical app: tick which apps and tweaks you want, click Run, watch
progress in a live log. Checks GitHub for a newer version on launch.

1. Download `Remove-MSBloat-GUI.ps1` (and `MSBloat.Core.ps1` alongside it, if
   you want to avoid a network fetch on first run - the GUI will download it
   automatically otherwise).
2. Double-click it, or run `.\Remove-MSBloat-GUI.ps1` from PowerShell.
3. Approve the UAC prompt, tick the apps/tweaks you want (a sensible
   "Recommended" preset is checked by default), and click **Run**.

Check "Preview only (no changes)" to see what would happen without changing
anything. If a newer version is available, the status bar shows an "Install
Update" button - click it to download and relaunch on the new version.

Needs a Windows desktop session (it's a window) - for headless, remote, or
scripted use, use the CLI script below instead.

## Remove-MSBloat.ps1 (command line)

Same underlying logic, no window - for scripting, remote sessions, or if you
just prefer the terminal.

Download and run:

```powershell
.\Remove-MSBloat.ps1
```

Keep the Xbox app / Game Bar installed:

```powershell
.\Remove-MSBloat.ps1 -KeepXbox
```

Preview changes without applying them:

```powershell
.\Remove-MSBloat.ps1 -WhatIf
```

Run without any prompts (e.g. for unattended use):

```powershell
.\Remove-MSBloat.ps1 -Force
```

One-liner (download and run in a single command). **Open PowerShell "as
Administrator" first** - a script launched this way has no file on disk to
relaunch itself elevated:

```powershell
irm https://raw.githubusercontent.com/musicman0917/Microsoft-Bloatware-Removal-PSModule/main/Remove-MSBloat.ps1 | iex
```

The CLI script does not self-update - a saved `.ps1` used for scheduled or
unattended tasks shouldn't change out from under you, and the `irm | iex`
form already always fetches the current version.

## What it does

- Removes inbox apps such as Clipchamp, Bing News/Weather, To Do, Solitaire,
  Your Phone, Zune Music/Video, and the Xbox app family (individually
  selectable in the GUI; `-KeepXbox` skips all of them in the CLI) - both for
  the current user and from system provisioning, so they don't come back for
  new user accounts.
- Disables Windows Copilot, taskbar Widgets, sponsored Start menu pins, and
  Start menu web search via registry policy keys.
- Removes OneDrive from startup.
- Creates a System Restore Point first, unless skipped.

A restart is required for the registry changes to take full effect.

## Files

- `Remove-MSBloat-GUI.ps1` - graphical entry point, self-updating
- `Remove-MSBloat.ps1` - command-line entry point
- `MSBloat.Core.ps1` - shared logic used by both (app/tweak catalogs, removal
  functions); not meant to be run directly

## Disclaimer

This script modifies the Windows Registry and removes system-provisioned
packages. Use at your own risk.
