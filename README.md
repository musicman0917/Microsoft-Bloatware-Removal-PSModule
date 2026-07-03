# Microsoft-Bloatware-Removal-PSModule

A standalone PowerShell script that removes common Windows inbox bloatware
and disables intrusive UI features (Copilot, Widgets, sponsored Start menu
pins, Start menu web search, OneDrive auto-startup). No installation or
module import needed - just run the file.

**Requires Windows 10/11 and PowerShell.** The script prompts for
Administrator elevation automatically when run from a saved `.ps1` file.

## Usage

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

## What it does

- Removes inbox apps such as Clipchamp, Bing News/Weather, To Do, Solitaire,
  Your Phone, Zune Music/Video, and (unless `-KeepXbox` is used) the Xbox
  app family - both for the current user and from system provisioning, so
  they don't come back for new user accounts.
- Disables Windows Copilot, taskbar Widgets, sponsored Start menu pins, and
  Start menu web search via registry policy keys.
- Removes OneDrive from startup.
- Creates a System Restore Point first, unless `-SkipRestorePoint` is used.

A restart is required for the registry changes to take full effect.

## Disclaimer

This script modifies the Windows Registry and removes system-provisioned
packages. Use at your own risk.
