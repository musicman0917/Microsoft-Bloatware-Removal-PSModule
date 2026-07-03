<#
.SYNOPSIS
    Removes default Windows bloatware and disables intrusive UI features.

.DESCRIPTION
    Removes common inbox apps, disables Copilot, turns off the Widgets board
    system-wide, disables sponsored Start menu pins, disables web search in the
    Start Menu, and stops OneDrive from running at startup. Prints a summary of
    successes and failures when finished.

    This is a plain PowerShell script - no installation or module import is
    required. Just download and run it, or use the one-liner below.

.PARAMETER KeepXbox
    Leaves the Xbox app, Game Bar, and related overlay apps installed.

.PARAMETER SkipRestorePoint
    Skips creating a System Restore Point before making changes. A restore
    point is created by default so changes can be rolled back if needed.

.PARAMETER Force
    Skips the confirmation prompt and the "restart now?" prompt at the end.
    Useful for unattended / scripted runs.

.EXAMPLE
    .\Remove-MSBloat.ps1
    Runs the standard cleanup, including removing Xbox apps.

.EXAMPLE
    .\Remove-MSBloat.ps1 -KeepXbox
    Runs the cleanup but leaves the Xbox Game Bar and overlay apps intact.

.EXAMPLE
    .\Remove-MSBloat.ps1 -WhatIf
    Shows what would be removed/changed without making any changes.

.EXAMPLE
    irm https://raw.githubusercontent.com/musicman0917/Microsoft-Bloatware-Removal-PSModule/main/Remove-MSBloat.ps1 | iex
    Downloads and runs the script in one step. Open PowerShell "as
    Administrator" first - a script launched this way cannot prompt for
    elevation on its own.

.NOTES
    Modifies the Windows Registry and removes system-provisioned packages.
    Use at your own risk. A System Restore Point is created automatically
    unless -SkipRestorePoint is specified.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$KeepXbox,
    [switch]$SkipRestorePoint,
    [switch]$Force
)

function Remove-MSBloat {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$KeepXbox,
        [switch]$SkipRestorePoint,
        [switch]$Force
    )

    # --- AUTO-ELEVATION LOGIC ---
    $isAdmin = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent().IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        if (-not $PSCommandPath) {
            # Script was piped into iex (e.g. "irm ... | iex"). There is no file on
            # disk to relaunch, so we can't self-elevate - ask the user to do it.
            Write-Warning "Administrator privileges are required, but this script was run from a pipe (e.g. 'irm | iex')."
            Write-Warning "Open PowerShell 'as Administrator' and run the command again."
            return
        }

        Write-Host "Administrator privileges are required. Prompting for User Account Control (UAC) elevation..." -ForegroundColor Yellow

        $relaunchArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
        if ($KeepXbox) { $relaunchArgs += '-KeepXbox' }
        if ($SkipRestorePoint) { $relaunchArgs += '-SkipRestorePoint' }
        if ($Force) { $relaunchArgs += '-Force' }
        if ($WhatIfPreference) { $relaunchArgs += '-WhatIf' }

        # Determine if running in Windows PowerShell (v5) or PowerShell Core (v6+)
        $psExe = if ($PSVersionTable.PSVersion.Major -ge 6) { "pwsh.exe" } else { "powershell.exe" }

        try {
            Start-Process -FilePath $psExe -ArgumentList $relaunchArgs -Verb RunAs
            return # Stop executing in the current non-admin window
        } catch {
            Write-Warning "Elevation cancelled. You must grant Administrator permissions to run this script."
            return
        }
    }
    # --- END AUTO-ELEVATION LOGIC ---

    $bloatApps = @(
        "Clipchamp.Clipchamp",
        "Microsoft.BingNews",
        "Microsoft.BingWeather",
        "Microsoft.Todos",
        "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.YourPhone",
        "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo"
    )

    if (-not $KeepXbox) {
        $bloatApps += @(
            "Microsoft.GamingApp",
            "Microsoft.XboxGamingOverlay",
            "Microsoft.XboxApp",
            "Microsoft.Xbox.TCUI",
            "Microsoft.XboxSpeechToTextOverlay"
        )
    }

    $registryTweaks = @(
        @{ Name = "Copilot Disabled"; Path = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"; Key = "TurnOffWindowsCopilot"; Value = 1; Type = "DWord" },
        @{ Name = "Taskbar Widgets Disabled"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; Key = "AllowNewsAndInterests"; Value = 0; Type = "DWord" },
        @{ Name = "Sponsored Start Menu Pins Disabled"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Key = "DisableWindowsConsumerFeatures"; Value = 1; Type = "DWord" },
        @{ Name = "Start Menu Web Search Disabled"; Path = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"; Key = "DisableSearchBoxSuggestions"; Value = 1; Type = "DWord" }
    )

    # --- CONFIRMATION ---
    if (-not $Force -and -not $WhatIfPreference) {
        Write-Host "`nThis script will:" -ForegroundColor Yellow
        Write-Host " - Remove up to $($bloatApps.Count) inbox apps (if installed)" -ForegroundColor Yellow
        Write-Host " - Apply $($registryTweaks.Count) registry tweaks (Copilot, Widgets, Start menu ads/search)" -ForegroundColor Yellow
        Write-Host " - Disable OneDrive auto-startup" -ForegroundColor Yellow
        if (-not $SkipRestorePoint) {
            Write-Host " - Create a System Restore Point first" -ForegroundColor Yellow
        }
        $confirmation = Read-Host "`nContinue? (Y/N)"
        if ($confirmation -notmatch '^[Yy]') {
            Write-Host "Cancelled. No changes were made." -ForegroundColor Cyan
            return
        }
    }

    # --- SYSTEM RESTORE POINT ---
    if (-not $SkipRestorePoint) {
        if ($PSCmdlet.ShouldProcess("System", "Create System Restore Point")) {
            Write-Host "Creating a System Restore Point..." -ForegroundColor Cyan
            try {
                Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
                Checkpoint-Computer -Description "Pre-MSBloat-Removal" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
                Write-Host "Restore point created." -ForegroundColor Green
            } catch {
                Write-Warning "Could not create a System Restore Point: $($_.Exception.Message)"
                Write-Warning "Continuing without one. Use -SkipRestorePoint to suppress this attempt."
            }
        }
    }

    $removedApps = @()
    $failedApps = @()
    $appliedTweaks = @()
    $failedTweaks = @()

    Write-Host "`nScanning for and removing bloatware apps..." -ForegroundColor Cyan

    foreach ($app in $bloatApps) {
        if (-not $PSCmdlet.ShouldProcess($app, "Remove application")) { continue }

        $attempted = $false
        $errorMsg = $null

        # Check and remove for current user
        $installedApp = Get-AppxPackage -Name "*$app*" -AllUsers -ErrorAction SilentlyContinue
        if ($installedApp) {
            $attempted = $true
            try {
                $installedApp | Remove-AppxPackage -ErrorAction Stop
            } catch {
                $errorMsg = $_.Exception.Message
            }
        }

        # Check and remove from system provisioning (prevents reinstall for new users)
        $provisionedApp = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match $app }
        if ($provisionedApp) {
            $attempted = $true
            try {
                $provisionedApp | Remove-AppxProvisionedPackage -Online -ErrorAction Stop
            } catch {
                $errorMsg = $_.Exception.Message
            }
        }

        # Log the result if we actually tried to remove it
        if ($attempted) {
            if ($errorMsg) {
                $failedApps += [PSCustomObject]@{ Name = $app; Reason = $errorMsg }
            } else {
                $removedApps += $app
            }
        }
    }

    Write-Host "Applying System & UI Registry Tweaks..." -ForegroundColor Cyan

    foreach ($tweak in $registryTweaks) {
        if (-not $PSCmdlet.ShouldProcess($tweak.Path, "Set $($tweak.Key) = $($tweak.Value)")) { continue }

        try {
            if (!(Test-Path $tweak.Path)) { New-Item -Path $tweak.Path -Force -ErrorAction Stop | Out-Null }
            Set-ItemProperty -Path $tweak.Path -Name $tweak.Key -Value $tweak.Value -Type $tweak.Type -Force -ErrorAction Stop
            $appliedTweaks += $tweak.Name
        } catch {
            $failedTweaks += [PSCustomObject]@{ Name = $tweak.Name; Reason = $_.Exception.Message }
        }
    }

    # OneDrive Startup
    $oneDriveName = "OneDrive auto-startup disabled"
    $oneDriveRunPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    if ($PSCmdlet.ShouldProcess($oneDriveRunPath, "Remove OneDrive auto-startup entry")) {
        try {
            if (Get-ItemProperty -Path $oneDriveRunPath -Name "OneDrive" -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -Path $oneDriveRunPath -Name "OneDrive" -ErrorAction Stop
            }
            $appliedTweaks += $oneDriveName
        } catch {
            $failedTweaks += [PSCustomObject]@{ Name = $oneDriveName; Reason = $_.Exception.Message }
        }
    }

    if ($WhatIfPreference) { return }

    # --- RESULTS DASHBOARD ---
    Write-Host "`n========================================" -ForegroundColor Magenta
    Write-Host "          CLEANUP RESULTS               " -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta

    # Successful Apps
    if ($removedApps.Count -gt 0) {
        Write-Host "Apps successfully removed ($($removedApps.Count)):" -ForegroundColor Green
        foreach ($removed in $removedApps) { Write-Host " - $removed" -ForegroundColor DarkGray }
    } else {
        Write-Host "Apps removed: 0 (System was already clean)" -ForegroundColor Green
    }

    # Failed Apps
    if ($failedApps.Count -gt 0) {
        Write-Host "`nFailed to remove apps ($($failedApps.Count)):" -ForegroundColor Red
        foreach ($failed in $failedApps) {
            Write-Host " - $($failed.Name)" -ForegroundColor Red
            Write-Host "   Reason: $($failed.Reason)" -ForegroundColor DarkGray
        }
    }

    # Successful Tweaks
    Write-Host "`nSystem UI Tweaks Applied ($($appliedTweaks.Count)):" -ForegroundColor Green
    foreach ($tweak in $appliedTweaks) { Write-Host " - $tweak" -ForegroundColor DarkGray }

    # Failed Tweaks
    if ($failedTweaks.Count -gt 0) {
        Write-Host "`nFailed to apply tweaks ($($failedTweaks.Count)):" -ForegroundColor Red
        foreach ($failed in $failedTweaks) {
            Write-Host " - $($failed.Name)" -ForegroundColor Red
            Write-Host "   Reason: $($failed.Reason)" -ForegroundColor DarkGray
        }
    }

    Write-Host "========================================" -ForegroundColor Magenta
    if ($failedApps.Count -gt 0 -or $failedTweaks.Count -gt 0) {
        Write-Host "Process complete with some errors. Restart your computer to apply the successful changes." -ForegroundColor Yellow
    } else {
        Write-Host "Process complete! Restart your computer for registry changes to take effect." -ForegroundColor Cyan
    }

    if (-not $Force) {
        $restart = Read-Host "`nRestart now? (Y/N)"
        if ($restart -match '^[Yy]') {
            Restart-Computer -Confirm:$false
        }
    }
}

# Auto-run when this file is executed or piped into iex, but not when it is
# dot-sourced (". .\Remove-MSBloat.ps1") to import the function for reuse.
if ($MyInvocation.InvocationName -ne '.') {
    Remove-MSBloat @PSBoundParameters
}
