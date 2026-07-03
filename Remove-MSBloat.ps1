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

    Prefer a graphical interface with individual app/tweak checkboxes? See
    Remove-MSBloat-GUI.ps1 in the same repo.

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

$ScriptVersion = '1.0.0'

# --- CORE LOADER ---
# Loads MSBloat.Core.ps1 from disk if it sits next to this script (repo clone /
# release zip), otherwise fetches it from GitHub pinned to this script's own
# release tag, so a single downloaded file (or "irm | iex") still works.
$coreLoaded = $false
if ($PSScriptRoot) {
    $localCore = Join-Path $PSScriptRoot 'MSBloat.Core.ps1'
    if (Test-Path -LiteralPath $localCore) {
        . $localCore
        $coreLoaded = $true
    }
}
if (-not $coreLoaded) {
    try {
        $coreUri = "https://raw.githubusercontent.com/musicman0917/Microsoft-Bloatware-Removal-PSModule/v$ScriptVersion/MSBloat.Core.ps1"
        $coreText = Invoke-RestMethod -Uri $coreUri -TimeoutSec 10 -ErrorAction Stop
        . ([scriptblock]::Create($coreText))
        $coreLoaded = $true
    } catch {
        Write-Warning "Could not load MSBloat.Core.ps1: $($_.Exception.Message)"
    }
}
if (-not $coreLoaded) {
    throw "Fatal: core library could not be loaded. Check your internet connection."
}
# --- END CORE LOADER ---

function Remove-MSBloat {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$KeepXbox,
        [switch]$SkipRestorePoint,
        [switch]$Force
    )

    # --- AUTO-ELEVATION LOGIC ---
    if (-not (Test-MSBloatIsAdmin)) {
        if (-not $PSCommandPath) {
            Write-Warning "Administrator privileges are required, but this script was run from a pipe (e.g. 'irm | iex')."
            Write-Warning "Open PowerShell 'as Administrator' and run the command again."
            return
        }

        Write-Host "Administrator privileges are required. Prompting for User Account Control (UAC) elevation..." -ForegroundColor Yellow

        $relaunchArgs = @()
        if ($KeepXbox) { $relaunchArgs += '-KeepXbox' }
        if ($SkipRestorePoint) { $relaunchArgs += '-SkipRestorePoint' }
        if ($Force) { $relaunchArgs += '-Force' }
        if ($WhatIfPreference) { $relaunchArgs += '-WhatIf' }

        try {
            Start-MSBloatElevation -ScriptPath $PSCommandPath -ArgumentList $relaunchArgs
            return # Stop executing in the current non-admin window
        } catch {
            Write-Warning "Elevation cancelled. You must grant Administrator permissions to run this script."
            return
        }
    }
    # --- END AUTO-ELEVATION LOGIC ---

    $appIds = $script:MSBloatAppCatalog |
        Where-Object { -not ($KeepXbox -and $_.Category -eq 'Xbox') } |
        Select-Object -ExpandProperty Id
    $tweakIds = $script:MSBloatTweakCatalog | Select-Object -ExpandProperty Id

    # --- CONFIRMATION ---
    if (-not $Force -and -not $WhatIfPreference) {
        Write-Host "`nThis script will:" -ForegroundColor Yellow
        Write-Host " - Remove up to $($appIds.Count) inbox apps (if installed)" -ForegroundColor Yellow
        Write-Host " - Apply $($tweakIds.Count) registry tweaks (Copilot, Widgets, Start menu ads/search, OneDrive)" -ForegroundColor Yellow
        if (-not $SkipRestorePoint) {
            Write-Host " - Create a System Restore Point first" -ForegroundColor Yellow
        }
        $confirmation = Read-Host "`nContinue? (Y/N)"
        if ($confirmation -notmatch '^[Yy]') {
            Write-Host "Cancelled. No changes were made." -ForegroundColor Cyan
            return
        }
    }

    $cliLog = { param($evt) Write-Host $evt.Message -ForegroundColor $evt.Color }

    $result = Invoke-MSBloatRemoval -AppIds $appIds -TweakIds $tweakIds `
        -SkipRestorePoint:$SkipRestorePoint -WhatIf:$WhatIfPreference -Confirm:$false `
        -LogAction $cliLog

    if ($WhatIfPreference) { return }

    # --- RESULTS DASHBOARD ---
    Write-Host "`n========================================" -ForegroundColor Magenta
    Write-Host "          CLEANUP RESULTS               " -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta

    if ($result.RemovedApps.Count -gt 0) {
        Write-Host "Apps successfully removed ($($result.RemovedApps.Count)):" -ForegroundColor Green
        foreach ($removed in $result.RemovedApps) { Write-Host " - $removed" -ForegroundColor DarkGray }
    } else {
        Write-Host "Apps removed: 0 (System was already clean)" -ForegroundColor Green
    }

    if ($result.FailedApps.Count -gt 0) {
        Write-Host "`nFailed to remove apps ($($result.FailedApps.Count)):" -ForegroundColor Red
        foreach ($failed in $result.FailedApps) {
            Write-Host " - $($failed.Name)" -ForegroundColor Red
            Write-Host "   Reason: $($failed.Reason)" -ForegroundColor DarkGray
        }
    }

    Write-Host "`nSystem UI Tweaks Applied ($($result.AppliedTweaks.Count)):" -ForegroundColor Green
    foreach ($tweak in $result.AppliedTweaks) { Write-Host " - $tweak" -ForegroundColor DarkGray }

    if ($result.FailedTweaks.Count -gt 0) {
        Write-Host "`nFailed to apply tweaks ($($result.FailedTweaks.Count)):" -ForegroundColor Red
        foreach ($failed in $result.FailedTweaks) {
            Write-Host " - $($failed.Name)" -ForegroundColor Red
            Write-Host "   Reason: $($failed.Reason)" -ForegroundColor DarkGray
        }
    }

    Write-Host "========================================" -ForegroundColor Magenta
    if ($result.FailedApps.Count -gt 0 -or $result.FailedTweaks.Count -gt 0) {
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
