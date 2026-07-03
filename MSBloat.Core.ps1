<#
.SYNOPSIS
    Shared library for the Microsoft Bloatware Removal Tool.

.DESCRIPTION
    Defines the app/tweak catalogs and the functions that both Remove-MSBloat.ps1
    (CLI) and Remove-MSBloat-GUI.ps1 (GUI) use to do the actual work. This file has
    no side effects when dot-sourced - it only defines data and functions.
#>

$script:MSBloatAppCatalog = @(
    [PSCustomObject]@{ Id = 'Clipchamp.Clipchamp';                    DisplayName = 'Clipchamp';                        Category = 'Bloat'; Recommended = $true }
    [PSCustomObject]@{ Id = 'Microsoft.BingNews';                     DisplayName = 'News (Bing News)';                 Category = 'Bloat'; Recommended = $true }
    [PSCustomObject]@{ Id = 'Microsoft.BingWeather';                  DisplayName = 'Weather';                          Category = 'Bloat'; Recommended = $true }
    [PSCustomObject]@{ Id = 'Microsoft.Todos';                        DisplayName = 'Microsoft To Do';                  Category = 'Bloat'; Recommended = $true }
    [PSCustomObject]@{ Id = 'Microsoft.MicrosoftSolitaireCollection'; DisplayName = 'Solitaire Collection';             Category = 'Bloat'; Recommended = $true }
    [PSCustomObject]@{ Id = 'Microsoft.YourPhone';                    DisplayName = 'Phone Link';                       Category = 'Bloat'; Recommended = $true }
    [PSCustomObject]@{ Id = 'Microsoft.ZuneMusic';                    DisplayName = 'Media Player (Zune Music)';        Category = 'Bloat'; Recommended = $true }
    [PSCustomObject]@{ Id = 'Microsoft.ZuneVideo';                    DisplayName = 'Movies & TV (Zune Video)';         Category = 'Bloat'; Recommended = $true }
    [PSCustomObject]@{ Id = 'Microsoft.GamingApp';                    DisplayName = 'Xbox App';                         Category = 'Xbox';  Recommended = $true }
    [PSCustomObject]@{ Id = 'Microsoft.XboxGamingOverlay';            DisplayName = 'Xbox Game Bar';                    Category = 'Xbox';  Recommended = $true }
    [PSCustomObject]@{ Id = 'Microsoft.XboxApp';                      DisplayName = 'Xbox (legacy)';                    Category = 'Xbox';  Recommended = $true }
    [PSCustomObject]@{ Id = 'Microsoft.Xbox.TCUI';                    DisplayName = 'Xbox TCUI';                        Category = 'Xbox';  Recommended = $true }
    [PSCustomObject]@{ Id = 'Microsoft.XboxSpeechToTextOverlay';      DisplayName = 'Xbox Speech-to-Text Overlay';      Category = 'Xbox';  Recommended = $true }
)

$script:MSBloatTweakCatalog = @(
    [PSCustomObject]@{ Id = 'CopilotDisabled';  DisplayName = 'Disable Windows Copilot';           Path = 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot'; Key = 'TurnOffWindowsCopilot';        Value = 1; Type = 'DWord'; Recommended = $true }
    [PSCustomObject]@{ Id = 'WidgetsDisabled';  DisplayName = 'Disable Taskbar Widgets';           Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh';                     Key = 'AllowNewsAndInterests';         Value = 0; Type = 'DWord'; Recommended = $true }
    [PSCustomObject]@{ Id = 'SponsoredPinsOff'; DisplayName = 'Disable Sponsored Start Menu Pins'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent';   Key = 'DisableWindowsConsumerFeatures'; Value = 1; Type = 'DWord'; Recommended = $true }
    [PSCustomObject]@{ Id = 'StartSearchOff';   DisplayName = 'Disable Start Menu Web Search';     Path = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer';       Key = 'DisableSearchBoxSuggestions';   Value = 1; Type = 'DWord'; Recommended = $true }
    [PSCustomObject]@{ Id = 'OneDriveStartup';  DisplayName = 'Disable OneDrive Auto-Startup';     Special = 'OneDriveRunKey';                                                                                          Recommended = $true }
)

function Test-MSBloatIsAdmin {
    [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent().IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-MSBloatElevation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$ArgumentList = @()
    )

    $psExe = if ($PSVersionTable.PSVersion.Major -ge 6) { "pwsh.exe" } else { "powershell.exe" }
    $fullArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + $ArgumentList
    Start-Process -FilePath $psExe -ArgumentList $fullArgs -Verb RunAs
}

function New-MSBloatRestorePoint {
    [CmdletBinding()]
    param(
        [scriptblock]$LogAction = { param($evt) Write-Host $evt.Message -ForegroundColor $evt.Color }
    )

    & $LogAction ([PSCustomObject]@{ Type = 'Info'; Message = 'Creating a System Restore Point...'; Color = 'Cyan' })
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "Pre-MSBloat-Removal" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        & $LogAction ([PSCustomObject]@{ Type = 'Success'; Message = 'Restore point created.'; Color = 'Green' })
        return $true
    } catch {
        & $LogAction ([PSCustomObject]@{ Type = 'Warning'; Message = "Could not create a System Restore Point: $($_.Exception.Message)"; Color = 'Yellow' })
        return $false
    }
}

function Set-MSBloatTweak {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Tweak
    )

    if ($Tweak.Special -eq 'OneDriveRunKey') {
        if (-not $PSCmdlet.ShouldProcess('HKCU:\...\Run\OneDrive', 'Remove OneDrive auto-startup entry')) { return }
        $oneDriveRunPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        if (Get-ItemProperty -Path $oneDriveRunPath -Name "OneDrive" -ErrorAction SilentlyContinue) {
            Remove-ItemProperty -Path $oneDriveRunPath -Name "OneDrive" -ErrorAction Stop
        }
        return
    }

    if (-not $PSCmdlet.ShouldProcess($Tweak.Path, "Set $($Tweak.Key) = $($Tweak.Value)")) { return }
    if (!(Test-Path $Tweak.Path)) { New-Item -Path $Tweak.Path -Force -ErrorAction Stop | Out-Null }
    Set-ItemProperty -Path $Tweak.Path -Name $Tweak.Key -Value $Tweak.Value -Type $Tweak.Type -Force -ErrorAction Stop
}

function Invoke-MSBloatRemoval {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string[]]$AppIds = @(),
        [string[]]$TweakIds = @(),
        [switch]$SkipRestorePoint,
        [scriptblock]$LogAction = { param($evt) Write-Host $evt.Message -ForegroundColor $evt.Color }
    )

    $removedApps = @()
    $failedApps = @()
    $appliedTweaks = @()
    $failedTweaks = @()

    if (-not $SkipRestorePoint) {
        if ($PSCmdlet.ShouldProcess('System', 'Create System Restore Point')) {
            New-MSBloatRestorePoint -LogAction $LogAction | Out-Null
        }
    }

    & $LogAction ([PSCustomObject]@{ Type = 'Info'; Message = 'Scanning for and removing bloatware apps...'; Color = 'Cyan' })

    foreach ($appId in $AppIds) {
        if (-not $PSCmdlet.ShouldProcess($appId, 'Remove application')) { continue }

        & $LogAction ([PSCustomObject]@{ Type = 'Progress'; Message = "Removing $appId..."; Color = 'Gray' })

        $attempted = $false
        $errorMsg = $null

        $installedApp = Get-AppxPackage -Name "*$appId*" -AllUsers -ErrorAction SilentlyContinue
        if ($installedApp) {
            $attempted = $true
            try {
                $installedApp | Remove-AppxPackage -ErrorAction Stop
            } catch {
                $errorMsg = $_.Exception.Message
            }
        }

        $provisionedApp = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match $appId }
        if ($provisionedApp) {
            $attempted = $true
            try {
                $provisionedApp | Remove-AppxProvisionedPackage -Online -ErrorAction Stop
            } catch {
                $errorMsg = $_.Exception.Message
            }
        }

        if ($attempted) {
            if ($errorMsg) {
                $failedApps += [PSCustomObject]@{ Name = $appId; Reason = $errorMsg }
                & $LogAction ([PSCustomObject]@{ Type = 'Fail'; Message = "FAILED: $appId - $errorMsg"; Color = 'Red' })
            } else {
                $removedApps += $appId
                & $LogAction ([PSCustomObject]@{ Type = 'Success'; Message = "Removed: $appId"; Color = 'Green' })
            }
        }
    }

    & $LogAction ([PSCustomObject]@{ Type = 'Info'; Message = 'Applying System & UI Registry Tweaks...'; Color = 'Cyan' })

    foreach ($tweakId in $TweakIds) {
        $tweak = $script:MSBloatTweakCatalog | Where-Object { $_.Id -eq $tweakId }
        if (-not $tweak) { continue }

        & $LogAction ([PSCustomObject]@{ Type = 'Progress'; Message = "Applying: $($tweak.DisplayName)..."; Color = 'Gray' })

        try {
            Set-MSBloatTweak -Tweak $tweak -WhatIf:$WhatIfPreference -Confirm:$false
            if (-not $WhatIfPreference) {
                $appliedTweaks += $tweak.DisplayName
                & $LogAction ([PSCustomObject]@{ Type = 'Success'; Message = "Applied: $($tweak.DisplayName)"; Color = 'Green' })
            }
        } catch {
            $failedTweaks += [PSCustomObject]@{ Name = $tweak.DisplayName; Reason = $_.Exception.Message }
            & $LogAction ([PSCustomObject]@{ Type = 'Fail'; Message = "FAILED: $($tweak.DisplayName) - $($_.Exception.Message)"; Color = 'Red' })
        }
    }

    [PSCustomObject]@{
        RemovedApps   = $removedApps
        FailedApps    = $failedApps
        AppliedTweaks = $appliedTweaks
        FailedTweaks  = $failedTweaks
        WhatIf        = [bool]$WhatIfPreference
    }
}

function Test-MSBloatUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CurrentVersion
    )

    try {
        $headers = @{ 'User-Agent' = 'MSBloat-Removal-Tool'; 'Accept' = 'application/vnd.github+json' }
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/musicman0917/Microsoft-Bloatware-Removal-PSModule/releases/latest' `
            -Headers $headers -TimeoutSec 5 -ErrorAction Stop

        $latest = [version]($release.tag_name.TrimStart('v'))
        $current = [version]$CurrentVersion

        if ($latest -gt $current) { return $release }
        return $null
    } catch {
        return $null
    }
}

function Install-MSBloatUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Release,
        [Parameter(Mandatory)][string]$AssetName,
        [Parameter(Mandatory)][string]$CurrentPath
    )

    $asset = $Release.assets | Where-Object { $_.name -eq $AssetName }
    if (-not $asset) {
        throw "Release $($Release.tag_name) has no asset named '$AssetName'."
    }

    $tempPath = Join-Path $env:TEMP "$([IO.Path]::GetFileNameWithoutExtension($AssetName)).$($Release.tag_name).ps1"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempPath -UseBasicParsing -ErrorAction Stop

    $psExe = if ($PSVersionTable.PSVersion.Major -ge 6) { "pwsh.exe" } else { "powershell.exe" }
    $relaunchArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tempPath, '-FinishUpdate', $CurrentPath)
    Start-Process -FilePath $psExe -ArgumentList $relaunchArgs -Verb RunAs
}

function Complete-MSBloatUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    for ($i = 0; $i -lt 5; $i++) {
        try {
            Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force -ErrorAction Stop
            return $true
        } catch {
            Start-Sleep -Milliseconds 200
        }
    }
    return $false
}
