<#
.SYNOPSIS
    Windows Bloatware Removal Tool - graphical interface.

.DESCRIPTION
    A WinForms front end for MSBloat.Core.ps1. Lets you pick individual apps and
    registry tweaks with checkboxes, preview changes with a "Preview only" option,
    and checks GitHub for a newer version on launch.

    No installation required - just download and run it, or use the one-liner
    documented in the README. Requires a Windows desktop session (not for
    headless/remote use - see Remove-MSBloat.ps1 for a console-only alternative).

.PARAMETER FinishUpdate
    Internal parameter used by the self-update mechanism. Not intended for
    direct use: when set, this process copies itself over the given path before
    showing its window, completing an in-progress update.

.NOTES
    Modifies the Windows Registry and removes system-provisioned packages.
    Use at your own risk. A System Restore Point is created automatically
    unless "Skip System Restore Point" is checked.
#>

[CmdletBinding()]
param(
    [string]$FinishUpdate
)

$ScriptVersion = '1.0.0'
$RepoOwner = 'musicman0917'
$RepoName = 'Microsoft-Bloatware-Removal-PSModule'
$GuiAssetName = 'Remove-MSBloat-GUI.ps1'

# --- CORE LOADER ---
# Loads MSBloat.Core.ps1 from disk if it sits next to this script (repo clone /
# release zip), otherwise fetches it from GitHub pinned to this script's own
# release tag, so a single downloaded file still works.
$coreLoaded = $false
$script:CoreScriptText = $null
if ($PSScriptRoot) {
    $localCore = Join-Path $PSScriptRoot 'MSBloat.Core.ps1'
    if (Test-Path -LiteralPath $localCore) {
        $script:CoreScriptText = Get-Content -LiteralPath $localCore -Raw
        . ([scriptblock]::Create($script:CoreScriptText))
        $coreLoaded = $true
    }
}
if (-not $coreLoaded) {
    try {
        $coreUri = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/v$ScriptVersion/MSBloat.Core.ps1"
        $script:CoreScriptText = Invoke-RestMethod -Uri $coreUri -TimeoutSec 10 -ErrorAction Stop
        . ([scriptblock]::Create($script:CoreScriptText))
        $coreLoaded = $true
    } catch {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "Could not load required components. Check your internet connection and try again.`n`n$($_.Exception.Message)",
            "Microsoft Bloatware Removal Tool", 'OK', 'Error') | Out-Null
        exit 1
    }
}
# --- END CORE LOADER ---

# --- ELEVATE BEFORE SHOWING ANY WINDOW ---
if (-not (Test-MSBloatIsAdmin)) {
    if (-not $PSCommandPath) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "This tool must be run from a saved .ps1 file to request Administrator rights.`nDownload the file and run it directly instead of piping it into iex.",
            "Microsoft Bloatware Removal Tool", 'OK', 'Warning') | Out-Null
        exit 1
    }

    $relaunchArgs = @()
    if ($FinishUpdate) { $relaunchArgs += @('-FinishUpdate', $FinishUpdate) }

    try {
        Start-MSBloatElevation -ScriptPath $PSCommandPath -ArgumentList $relaunchArgs
    } catch {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "Administrator permissions are required to run this tool.",
            "Microsoft Bloatware Removal Tool", 'OK', 'Warning') | Out-Null
    }
    exit
}
# --- END ELEVATION ---

# --- COMPLETE A PENDING SELF-UPDATE (if launched with -FinishUpdate) ---
if ($FinishUpdate) {
    Complete-MSBloatUpdate -SourcePath $PSCommandPath -DestinationPath $FinishUpdate | Out-Null
}
# --- END UPDATE COMPLETION ---

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ============================================================================
# FORM CONSTRUCTION
# ============================================================================

$form = New-Object System.Windows.Forms.Form
$form.Text = "Microsoft Bloatware Removal Tool v$ScriptVersion"
$form.Size = New-Object System.Drawing.Size(780, 700)
$form.MinimumSize = New-Object System.Drawing.Size(700, 550)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

# --- Header ---
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Dock = 'Top'
$headerPanel.Height = 40

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "Microsoft Bloatware Removal Tool"
$titleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(10, 8)
$headerPanel.Controls.Add($titleLabel)

$updateButton = New-Object System.Windows.Forms.Button
$updateButton.Text = "Check for Updates"
$updateButton.Size = New-Object System.Drawing.Size(140, 26)
$updateButton.Anchor = 'Top,Right'
$updateButton.Location = New-Object System.Drawing.Point(620, 7)
$headerPanel.Controls.Add($updateButton)

# --- Apps / Tweaks lists (side by side) ---
$listsPanel = New-Object System.Windows.Forms.TableLayoutPanel
$listsPanel.Dock = 'Top'
$listsPanel.Height = 300
$listsPanel.ColumnCount = 2
$listsPanel.RowCount = 1
$listsPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 50))) | Out-Null
$listsPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 50))) | Out-Null

function New-MSBloatCatalogGroup {
    param([string]$Title, [array]$CatalogItems)

    $group = New-Object System.Windows.Forms.GroupBox
    $group.Text = $Title
    $group.Dock = 'Fill'

    $buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttonPanel.Dock = 'Top'
    $buttonPanel.Height = 30
    $buttonPanel.FlowDirection = 'LeftToRight'

    $btnAll = New-Object System.Windows.Forms.Button
    $btnAll.Text = 'All'
    $btnAll.Size = New-Object System.Drawing.Size(60, 24)
    $buttonPanel.Controls.Add($btnAll)

    $btnNone = New-Object System.Windows.Forms.Button
    $btnNone.Text = 'None'
    $btnNone.Size = New-Object System.Drawing.Size(60, 24)
    $buttonPanel.Controls.Add($btnNone)

    $btnRecommended = New-Object System.Windows.Forms.Button
    $btnRecommended.Text = 'Recommended'
    $btnRecommended.Size = New-Object System.Drawing.Size(100, 24)
    $buttonPanel.Controls.Add($btnRecommended)

    $listBox = New-Object System.Windows.Forms.CheckedListBox
    $listBox.Dock = 'Fill'
    $listBox.CheckOnClick = $true
    $listBox.IntegralHeight = $false

    foreach ($item in $CatalogItems) {
        $listBox.Items.Add($item.DisplayName) | Out-Null
    }

    $btnAll.Add_Click({ for ($i = 0; $i -lt $listBox.Items.Count; $i++) { $listBox.SetItemChecked($i, $true) } }.GetNewClosure())
    $btnNone.Add_Click({ for ($i = 0; $i -lt $listBox.Items.Count; $i++) { $listBox.SetItemChecked($i, $false) } }.GetNewClosure())
    $btnRecommended.Add_Click({
        for ($i = 0; $i -lt $CatalogItems.Count; $i++) { $listBox.SetItemChecked($i, [bool]$CatalogItems[$i].Recommended) }
    }.GetNewClosure())

    $group.Controls.Add($listBox)
    $group.Controls.Add($buttonPanel)

    [PSCustomObject]@{ Group = $group; ListBox = $listBox; Catalog = $CatalogItems }
}

$appsGroup = New-MSBloatCatalogGroup -Title 'Apps to Remove' -CatalogItems $script:MSBloatAppCatalog
$tweaksGroup = New-MSBloatCatalogGroup -Title 'System Tweaks' -CatalogItems $script:MSBloatTweakCatalog

# Pre-check recommended items by default
for ($i = 0; $i -lt $appsGroup.Catalog.Count; $i++) { $appsGroup.ListBox.SetItemChecked($i, [bool]$appsGroup.Catalog[$i].Recommended) }
for ($i = 0; $i -lt $tweaksGroup.Catalog.Count; $i++) { $tweaksGroup.ListBox.SetItemChecked($i, [bool]$tweaksGroup.Catalog[$i].Recommended) }

$listsPanel.Controls.Add($appsGroup.Group, 0, 0)
$listsPanel.Controls.Add($tweaksGroup.Group, 1, 0)

# --- Options row ---
$optionsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$optionsPanel.Dock = 'Top'
$optionsPanel.Height = 30
$optionsPanel.FlowDirection = 'LeftToRight'

$whatIfCheck = New-Object System.Windows.Forms.CheckBox
$whatIfCheck.Text = 'Preview only (no changes)'
$whatIfCheck.AutoSize = $true
$whatIfCheck.Margin = New-Object System.Windows.Forms.Padding(3, 6, 15, 3)
$optionsPanel.Controls.Add($whatIfCheck)

$skipRestoreCheck = New-Object System.Windows.Forms.CheckBox
$skipRestoreCheck.Text = 'Skip System Restore Point'
$skipRestoreCheck.AutoSize = $true
$skipRestoreCheck.Margin = New-Object System.Windows.Forms.Padding(3, 6, 15, 3)
$optionsPanel.Controls.Add($skipRestoreCheck)

$restartCheck = New-Object System.Windows.Forms.CheckBox
$restartCheck.Text = 'Restart automatically when finished'
$restartCheck.AutoSize = $true
$restartCheck.Margin = New-Object System.Windows.Forms.Padding(3, 6, 15, 3)
$optionsPanel.Controls.Add($restartCheck)

# --- Buttons row ---
$buttonsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$buttonsPanel.Dock = 'Top'
$buttonsPanel.Height = 40
$buttonsPanel.FlowDirection = 'LeftToRight'

$runButton = New-Object System.Windows.Forms.Button
$runButton.Text = 'Run'
$runButton.Size = New-Object System.Drawing.Size(100, 28)
$runButton.Margin = New-Object System.Windows.Forms.Padding(3, 5, 3, 3)
$buttonsPanel.Controls.Add($runButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = 'Cancel'
$cancelButton.Size = New-Object System.Drawing.Size(100, 28)
$cancelButton.Margin = New-Object System.Windows.Forms.Padding(3, 5, 3, 3)
$cancelButton.Enabled = $false
$buttonsPanel.Controls.Add($cancelButton)

$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Text = 'Exit'
$exitButton.Size = New-Object System.Drawing.Size(100, 28)
$exitButton.Margin = New-Object System.Windows.Forms.Padding(3, 5, 3, 3)
$buttonsPanel.Controls.Add($exitButton)

# --- Progress bar ---
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Dock = 'Top'
$progressBar.Height = 20
$progressBar.Style = 'Continuous'

# --- Log panel ---
$logBox = New-Object System.Windows.Forms.RichTextBox
$logBox.Dock = 'Fill'
$logBox.ReadOnly = $true
$logBox.BackColor = [System.Drawing.Color]::Black
$logBox.ForeColor = [System.Drawing.Color]::LightGray
$logBox.Font = New-Object System.Drawing.Font('Consolas', 9)

# --- Status bar ---
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = 'Idle'
$statusLabel.Spring = $true
$statusLabel.TextAlign = 'MiddleLeft'
$versionStatusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$versionStatusLabel.Text = "v$ScriptVersion"
$statusStrip.Items.Add($statusLabel) | Out-Null
$statusStrip.Items.Add($versionStatusLabel) | Out-Null

# --- Assemble form (reverse dock order matters) ---
$form.Controls.Add($logBox)
$form.Controls.Add($progressBar)
$form.Controls.Add($buttonsPanel)
$form.Controls.Add($optionsPanel)
$form.Controls.Add($listsPanel)
$form.Controls.Add($headerPanel)
$form.Controls.Add($statusStrip)

# ============================================================================
# LOGGING HELPERS
# ============================================================================

function Write-MSBloatLogLine {
    param([string]$Message, [string]$Color = 'LightGray')

    $logBox.SelectionStart = $logBox.TextLength
    $logBox.SelectionLength = 0
    $logBox.SelectionColor = [System.Drawing.Color]::$Color
    $logBox.AppendText("[$(Get-Date -Format 'HH:mm:ss')] $Message`n")
    $logBox.ScrollToCaret()
}

$colorMap = @{
    Cyan   = 'Cyan'
    Green  = 'LightGreen'
    Yellow = 'Yellow'
    Red    = 'Tomato'
    Gray   = 'Gray'
}

# ============================================================================
# BACKGROUND JOB HELPER (Runspace + ConcurrentQueue + Timer, UI thread only touches controls)
# ============================================================================

$script:LogQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
$script:BgPowerShell = $null
$script:BgAsyncResult = $null
$script:BgOnComplete = $null

function Start-MSBloatBackgroundJob {
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [Parameter(Mandatory)][scriptblock]$OnComplete
    )

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace

    # A fresh runspace doesn't see functions dot-sourced in the main runspace,
    # so replay the same Core source text this process already loaded.
    $ps.AddScript($script:CoreScriptText) | Out-Null
    $ps.AddScript($ScriptBlock) | Out-Null
    foreach ($arg in $ArgumentList) { $ps.AddArgument($arg) | Out-Null }

    $script:BgPowerShell = $ps
    $script:BgAsyncResult = $ps.BeginInvoke()
    $script:BgOnComplete = $OnComplete
}

$uiTimer = New-Object System.Windows.Forms.Timer
$uiTimer.Interval = 150
$uiTimer.Add_Tick({
    $evt = $null
    while ($script:LogQueue.TryDequeue([ref]$evt)) {
        if ($evt.Type -eq 'UpdateAvailable') {
            $versionStatusLabel.Text = "v$ScriptVersion -> $($evt.Release.tag_name) available"
            $script:PendingUpdateRelease = $evt.Release
            $updateButton.Text = "Install Update"
        } else {
            $color = if ($colorMap.ContainsKey($evt.Color)) { $colorMap[$evt.Color] } else { 'LightGray' }
            Write-MSBloatLogLine -Message $evt.Message -Color $color
            $statusLabel.Text = $evt.Message
        }
    }

    if ($script:BgAsyncResult -and $script:BgAsyncResult.IsCompleted) {
        $completedResult = $null
        $completedError = $null
        try {
            $completedResult = $script:BgPowerShell.EndInvoke($script:BgAsyncResult)
            if ($script:BgPowerShell.Streams.Error.Count -gt 0) {
                foreach ($e in $script:BgPowerShell.Streams.Error) {
                    Write-MSBloatLogLine -Message "ERROR: $e" -Color 'Tomato'
                }
            }
        } catch {
            $completedError = $_
            Write-MSBloatLogLine -Message "ERROR: $($_.Exception.Message)" -Color 'Tomato'
        } finally {
            $script:BgPowerShell.Dispose()
            $script:BgPowerShell = $null
            $script:BgAsyncResult = $null
        }

        $onComplete = $script:BgOnComplete
        $script:BgOnComplete = $null
        if ($onComplete) { & $onComplete $completedResult $completedError }
    }
})
$uiTimer.Start()

# ============================================================================
# RUN / CANCEL / EXIT
# ============================================================================

function Get-MSBloatCheckedIds {
    param($GroupInfo)
    $ids = @()
    for ($i = 0; $i -lt $GroupInfo.Catalog.Count; $i++) {
        if ($GroupInfo.ListBox.GetItemChecked($i)) { $ids += $GroupInfo.Catalog[$i].Id }
    }
    return $ids
}

$runButton.Add_Click({
    $appIds = Get-MSBloatCheckedIds -GroupInfo $appsGroup
    $tweakIds = Get-MSBloatCheckedIds -GroupInfo $tweaksGroup

    if ($appIds.Count -eq 0 -and $tweakIds.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Nothing is selected. Check at least one app or tweak.", "Nothing to do", 'OK', 'Information') | Out-Null
        return
    }

    $isWhatIf = $whatIfCheck.Checked
    $verb = if ($isWhatIf) { "preview" } else { "remove/change" }
    $confirmResult = [System.Windows.Forms.MessageBox]::Show(
        "This will $verb $($appIds.Count) app(s) and $($tweakIds.Count) tweak(s). Continue?",
        "Confirm", 'YesNo', 'Question')
    if ($confirmResult -ne 'Yes') { return }

    $logBox.Clear()
    $runButton.Enabled = $false
    $cancelButton.Enabled = $true
    $progressBar.Style = 'Marquee'
    $statusLabel.Text = 'Running...'

    Start-MSBloatBackgroundJob -ScriptBlock {
        param($AppIds, $TweakIds, $SkipRestorePoint, $IsWhatIf, $Queue)
        $log = { param($evt) $Queue.Enqueue($evt) }
        Invoke-MSBloatRemoval -AppIds $AppIds -TweakIds $TweakIds `
            -SkipRestorePoint:$SkipRestorePoint -WhatIf:$IsWhatIf -Confirm:$false -LogAction $log
    } -ArgumentList @($appIds, $tweakIds, [bool]$skipRestoreCheck.Checked, [bool]$isWhatIf, $script:LogQueue) -OnComplete {
        param($result, $errorRecord)

        $runButton.Enabled = $true
        $cancelButton.Enabled = $false
        $progressBar.Style = 'Continuous'
        $progressBar.Value = 0
        $statusLabel.Text = 'Idle'

        if ($errorRecord) {
            Write-MSBloatLogLine -Message "Run failed: $($errorRecord.Exception.Message)" -Color 'Tomato'
            return
        }
        if (-not $result) { return }

        Write-MSBloatLogLine -Message '========================================' -Color 'Yellow'
        Write-MSBloatLogLine -Message 'CLEANUP RESULTS' -Color 'Yellow'
        Write-MSBloatLogLine -Message '========================================' -Color 'Yellow'
        Write-MSBloatLogLine -Message "Apps removed: $($result.RemovedApps.Count)" -Color 'LightGreen'
        if ($result.FailedApps.Count -gt 0) {
            Write-MSBloatLogLine -Message "Apps failed: $($result.FailedApps.Count)" -Color 'Tomato'
        }
        Write-MSBloatLogLine -Message "Tweaks applied: $($result.AppliedTweaks.Count)" -Color 'LightGreen'
        if ($result.FailedTweaks.Count -gt 0) {
            Write-MSBloatLogLine -Message "Tweaks failed: $($result.FailedTweaks.Count)" -Color 'Tomato'
        }

        if (-not $result.WhatIf -and $restartCheck.Checked) {
            Write-MSBloatLogLine -Message 'Restarting...' -Color 'Yellow'
            Restart-Computer -Confirm:$false
        }
    }
})

$cancelButton.Add_Click({
    if ($script:BgPowerShell) {
        Write-MSBloatLogLine -Message 'Cancelling after the current item finishes...' -Color 'Yellow'
        $script:BgPowerShell.Stop()
    }
    $cancelButton.Enabled = $false
})

$exitButton.Add_Click({ $form.Close() })

# ============================================================================
# SELF-UPDATE
# ============================================================================

function Test-MSBloatUpdateAsync {
    Start-MSBloatBackgroundJob -ScriptBlock {
        param($CurrentVersion, $Queue)
        $release = Test-MSBloatUpdate -CurrentVersion $CurrentVersion
        if ($release) { $Queue.Enqueue([PSCustomObject]@{ Type = 'UpdateAvailable'; Release = $release }) }
    } -ArgumentList @($ScriptVersion, $script:LogQueue) -OnComplete {
        param($result, $errorRecord)
        # No-op: the queue-drain loop already handled the UpdateAvailable event, if any.
    }
}

$updateButton.Add_Click({
    if ($script:PendingUpdateRelease) {
        $confirmResult = [System.Windows.Forms.MessageBox]::Show(
            "Update $($script:PendingUpdateRelease.tag_name) is available. Download and install it now? The app will restart.",
            "Update Available", 'YesNo', 'Question')
        if ($confirmResult -ne 'Yes') { return }

        try {
            Install-MSBloatUpdate -Release $script:PendingUpdateRelease -AssetName $GuiAssetName -CurrentPath $PSCommandPath
            $form.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Update failed: $($_.Exception.Message)", "Update Failed", 'OK', 'Error') | Out-Null
        }
    } else {
        $statusLabel.Text = 'Checking for updates...'
        Test-MSBloatUpdateAsync
    }
})

$form.Add_Shown({ Test-MSBloatUpdateAsync })

[System.Windows.Forms.Application]::Run($form)
