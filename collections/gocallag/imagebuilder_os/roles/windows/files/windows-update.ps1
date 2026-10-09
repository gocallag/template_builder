# see Using the Windows Update Agent API | Searching, Downloading, and Installing Updates
#     at https://msdn.microsoft.com/en-us/library/windows/desktop/aa387102(v=vs.85).aspx
# see ISystemInformation interface
#     at https://msdn.microsoft.com/en-us/library/windows/desktop/aa386095(v=vs.85).aspx
# see IUpdateSession interface
#     at https://msdn.microsoft.com/en-us/library/windows/desktop/aa386854(v=vs.85).aspx
# see IUpdateSearcher interface
#     at https://msdn.microsoft.com/en-us/library/windows/desktop/aa386515(v=vs.85).aspx
# see IUpdateSearcher::Search method
#     at https://docs.microsoft.com/en-us/windows/desktop/api/wuapi/nf-wuapi-iupdatesearcher-search
# see IUpdateDownloader interface
#     at https://msdn.microsoft.com/en-us/library/windows/desktop/aa386131(v=vs.85).aspx
# see IUpdateCollection interface
#     at https://msdn.microsoft.com/en-us/library/windows/desktop/aa386107(v=vs.85).aspx
# see IUpdate interface
#     at https://msdn.microsoft.com/en-us/library/windows/desktop/aa386099(v=vs.85).aspx
# see xWindowsUpdateAgent DSC resource
#     at https://github.com/PowerShell/xWindowsUpdate/blob/dev/DscResources/MSFT_xWindowsUpdateAgent/MSFT_xWindowsUpdateAgent.psm1
# NB you can install common sets of updates with one of these settings:
#       | Name          | SearchCriteria                            | Filters       |
#       |---------------|-------------------------------------------|---------------|
#       | Important     | AutoSelectOnWebSites=1 and IsInstalled=0  | $true         |
#       | Recommended   | BrowseOnly=0 and IsInstalled=0            | $true         |
#       | All           | IsInstalled=0                             | $true         |
#       | Optional Only | AutoSelectOnWebSites=0 and IsInstalled=0  | $_.BrowseOnly |

param(
    [string]$SearchCriteria = 'BrowseOnly=0 and IsInstalled=0',
    [string[]]$Filters = @('include:$true'),
    [int]$UpdateLimit = 1000,
    [switch]$OnlyCheckForRebootRequired = $false,
	[string]$LogPath = 'C:\Windows\Temp\windows-update.log'
)

$logDirectory = Split-Path -Parent $LogPath

if ($logDirectory -and !(Test-Path -LiteralPath $logDirectory)) {
    New-Item `
        -ItemType Directory `
        -Path $logDirectory `
        -Force |
        Out-Null
}

Start-Transcript `
    -Path $LogPath `
    -Append `
    -Force |
    Out-Null

Write-Output ''
Write-Output '============================================================'
Write-Output "Windows Update pass started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff K')"
Write-Output "Computer: $env:COMPUTERNAME"
Write-Output "PID: $PID"
Write-Output "Search criteria: $SearchCriteria"
Write-Output '============================================================'
$mock = $false

function ExitWithCode($exitCode) {
    try {
        Stop-Transcript | Out-Null
    }
    catch {
        # Ignore if no transcript is active.
    }

    $host.SetShouldExit($exitCode)
    exit $exitCode
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
trap {
    Write-Output "ERROR: $_"
    Write-Output (($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1')
    Write-Output (($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1')
    ExitWithCode 1
}

if ($mock) {
    $mockWindowsUpdatePath = 'C:\Windows\Temp\windows-update-count-mock.txt'
    if (!(Test-Path $mockWindowsUpdatePath)) {
        Set-Content $mockWindowsUpdatePath 10
    }
    $count = [int]::Parse((Get-Content $mockWindowsUpdatePath).Trim())
    if ($count) {
        Write-Output "Synthetic reboot countdown counter is at $count"
        Set-Content $mockWindowsUpdatePath (--$count)
        ExitWithCode 101
    }
    Write-Output 'No Windows updates found'
    ExitWithCode 0
}

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class Windows
{
    [DllImport("kernel32", SetLastError=true)]
    public static extern UInt64 GetTickCount64();

    public static TimeSpan GetUptime()
    {
        return TimeSpan.FromMilliseconds(GetTickCount64());
    }
}
'@

function Wait-Condition {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Condition,

        [int]$DebounceSeconds = 15,

        [int]$TimeoutSeconds = 300
    )

    $started = [Windows]::GetUptime()
    $satisfiedSince = $null

    while ($true) {
        $now = [Windows]::GetUptime()

        if (($now - $started).TotalSeconds -ge $TimeoutSeconds) {
            return $false
        }

        try {
            $result = & $Condition
        }
        catch {
            $result = $false
        }

        if ($result) {
            if ($null -eq $satisfiedSince) {
                $satisfiedSince = $now
            }

            if (
                ($now - $satisfiedSince).TotalSeconds -ge
                $DebounceSeconds
            ) {
                return $true
            }
        }
        else {
            $satisfiedSince = $null
        }

        Start-Sleep -Seconds 1
    }
}

$operationResultCodes = @{
    0 = "NotStarted";
    1 = "InProgress";
    2 = "Succeeded";
    3 = "SucceededWithErrors";
    4 = "Failed";
    5 = "Aborted"
}

function LookupOperationResultCode($code) {
    if ($operationResultCodes.ContainsKey($code)) {
        return $operationResultCodes[$code]
    }
    return "Unknown Code $code"
}

function ExitWhenRebootRequired {
    param(
        [bool]$rebootRequired = $false
    )

    # Check for pending Windows Updates.
    if (!$rebootRequired) {
        $systemInformation = New-Object -ComObject 'Microsoft.Update.SystemInfo'
        $rebootRequired = [bool]$systemInformation.RebootRequired
    }

    # Check for pending Windows Features / CBS packages.
    if (!$rebootRequired) {
        $pendingPackagesKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending'

        $pendingPackagesCount = (
            Get-ChildItem `
                -LiteralPath $pendingPackagesKey `
                -ErrorAction SilentlyContinue |
            Measure-Object
        ).Count

        $rebootRequired = $pendingPackagesCount -gt 0
    }

    if (!$rebootRequired) {
        return
    }

    Write-Output 'Waiting for the Windows Modules Installer to exit...'

	$cbsLogPath = Join-Path $env:SystemRoot 'Logs\CBS\CBS.log'
	$cbsIdleSeconds = 120

	$cbsLastLength = $null
	$cbsLastWriteTimeUtc = $null
	$cbsLastActivity = [Windows]::GetUptime()

	if (Test-Path -LiteralPath $cbsLogPath) {
		$cbsLog = Get-Item -LiteralPath $cbsLogPath

		$cbsLastLength = $cbsLog.Length
		$cbsLastWriteTimeUtc = $cbsLog.LastWriteTimeUtc
	}

	$settled = Wait-Condition `
		-Condition {
			#
			# Normal case: TiWorker exited.
			#
			$tiWorker = Get-Process `
				-Name TiWorker `
				-ErrorAction SilentlyContinue

			if (!$tiWorker) {
				Write-Output 'TiWorker has exited.'
				return $true
			}

			#
			# TiWorker still exists. Check for observable CBS progress.
			#
			if (Test-Path -LiteralPath $cbsLogPath) {
				$cbsLog = Get-Item -LiteralPath $cbsLogPath

				if (
					$cbsLog.Length -ne $cbsLastLength -or
					$cbsLog.LastWriteTimeUtc -ne $cbsLastWriteTimeUtc
				) {
					$cbsLastLength = $cbsLog.Length
					$cbsLastWriteTimeUtc = $cbsLog.LastWriteTimeUtc
					$cbsLastActivity = [Windows]::GetUptime()

					return $false
				}

				$cbsIdleFor = (
					[Windows]::GetUptime() - $cbsLastActivity
				).TotalSeconds

				if ($cbsIdleFor -ge $cbsIdleSeconds) {
					Write-Output (
						"TiWorker is still running but CBS.log has not " +
						"changed for $([int]$cbsIdleFor) seconds."
					)

					return $true
				}
			}

			return $false
		} `
		-DebounceSeconds 15 `
		-TimeoutSeconds 1800
		# $settled = Wait-Condition `
		# 	-Condition {
		# 		(
		# 			Get-Process `
		# 				-Name TiWorker `
		# 				-ErrorAction SilentlyContinue |
		# 			Measure-Object
		# 		).Count -eq 0
		# 	} `
		# 	-DebounceSeconds 15 `
		# 	-TimeoutSeconds 1800

    if ($settled) {
        Write-Output 'Windows Modules Installer has exited.'
    }
    else {
        Write-Output (
            'Windows Modules Installer did not exit within 1800 seconds. ' +
            'Proceeding with the required reboot.'
        )
    }

    ExitWithCode 101
}

ExitWhenRebootRequired

if ($OnlyCheckForRebootRequired) {
    Write-Output "$env:COMPUTERNAME restarted."
    ExitWithCode 0
}

$updateFilters = $Filters | ForEach-Object {
    $action, $expression = $_ -split ':',2
    New-Object PSObject -Property @{
        Action = $action
        Expression = [ScriptBlock]::Create($expression)
    }
}

function Test-IncludeUpdate($filters, $update) {
    foreach ($filter in $filters) {
        if (Where-Object -InputObject $update $filter.Expression) {
            return $filter.Action -eq 'include'
        }
    }
    return $false
}


$updatesession =  [activator]::CreateInstance([type]::GetTypeFromProgID("Microsoft.Update.Session",$env:COMPUTERNAME))
$updatesearcher = $updatesession.CreateUpdateSearcher()
try{
$searchresult = $updatesearcher.Search("IsInstalled=1")
} Catch {}
if(!$searchresult){
    stop-service wuauserv -force
    Start-Service wuauserv
    start-sleep -s 60

    $updatesession =  [activator]::CreateInstance([type]::GetTypeFromProgID("Microsoft.Update.Session",$env:COMPUTERNAME))
    $updatesearcher = $updatesession.CreateUpdateSearcher()
    $searchresult = $updatesearcher.Search("IsInstalled=1")

}


$windowsOsVersion = [System.Environment]::OSVersion.Version

Write-Output 'Searching for Windows updates...'
$updatesToDownloadSize = 0
$updatesToDownload = New-Object -ComObject 'Microsoft.Update.UpdateColl'
$updatesToInstall = New-Object -ComObject 'Microsoft.Update.UpdateColl'
while ($true) {
    try {
        $updateSession = New-Object -ComObject 'Microsoft.Update.Session'
        $updateSession.ClientApplicationID = 'builder-windows-update'
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $searchResult = $updateSearcher.Search($SearchCriteria)
        if ($searchResult.ResultCode -eq 2) {
            break
        }
        $searchStatus = LookupOperationResultCode($searchResult.ResultCode)
    } catch {
        $searchStatus = $_.ToString()
    }
    Write-Output "Search for Windows updates failed with '$searchStatus'. Retrying..."
    Start-Sleep -Seconds 5
}
$rebootRequired = $false
for ($i = 0; $i -lt $searchResult.Updates.Count; ++$i) {
    $update = $searchResult.Updates.Item($i)
    $updateDate = $update.LastDeploymentChangeTime.ToString('yyyy-MM-dd')
    $updateSize = ($update.MaxDownloadSize/1024/1024).ToString('0.##')
    $updateTitle = $update.Title
    $updateSummary = "Windows update ($updateDate; $updateSize MB): $updateTitle"

    if (!(Test-IncludeUpdate $updateFilters $update)) {
        Write-Output "Skipped (filter) $updateSummary"
        continue
    }

    if ($update.InstallationBehavior.CanRequestUserInput) {
        Write-Output "Warning The update '$updateTitle' has the CanRequestUserInput flag set (if the install hangs, you might need to exclude it with the filter 'exclude:`$_.InstallationBehavior.CanRequestUserInput' or 'exclude:`$_.Title -like '*$updateTitle*'')"
    }

    Write-Output "Found $updateSummary"

    $update.AcceptEula() | Out-Null

    $updatesToDownloadSize += $update.MaxDownloadSize
    $updatesToDownload.Add($update) | Out-Null

    $updatesToInstall.Add($update) | Out-Null
    if ($updatesToInstall.Count -ge $UpdateLimit) {
        $rebootRequired = $true
        break
    }
}

if ($updatesToDownload.Count) {
    $updateSize = ($updatesToDownloadSize/1024/1024).ToString('0.##')
    Write-Output "Downloading Windows updates ($($updatesToDownload.Count) updates; $updateSize MB)..."
    $updateDownloader = $updateSession.CreateUpdateDownloader()
    # https://docs.microsoft.com/en-us/windows/desktop/api/winnt/ns-winnt-_osversioninfoexa#remarks
    if (($windowsOsVersion.Major -eq 6 -and $windowsOsVersion.Minor -gt 1) -or ($windowsOsVersion.Major -gt 6)) {
        $updateDownloader.Priority = 4 # 1 (dpLow), 2 (dpNormal), 3 (dpHigh), 4 (dpExtraHigh).
    } else {
        # For versions lower then 6.2 highest prioirty is 3
        $updateDownloader.Priority = 3 # 1 (dpLow), 2 (dpNormal), 3 (dpHigh).
    }
    $updateDownloader.Updates = $updatesToDownload
    while ($true) {
        $downloadResult = $updateDownloader.Download()
        if ($downloadResult.ResultCode -eq 2) {
            break
        }
        if ($downloadResult.ResultCode -eq 3) {
            Write-Output "Download Windows updates succeeded with errors. Will retry after the next reboot."
            $rebootRequired = $true
            break
        }
        $downloadStatus = LookupOperationResultCode($downloadResult.ResultCode)
        Write-Output "Download Windows updates failed with $downloadStatus. Retrying..."
        Start-Sleep -Seconds 5
    }
}

if ($updatesToInstall.Count) {
    Write-Output 'Installing Windows updates...'
    $updateInstaller = $updateSession.CreateUpdateInstaller()
    $updateInstaller.Updates = $updatesToInstall

    $installRebootRequired = $false
    try {
        $installResult = $updateInstaller.Install()
        $installRebootRequired = $installResult.RebootRequired
    } catch {
        Write-Warning "Windows update installation failed with error:"
        Write-Warning $_.Exception.ToString()

        # Windows update install failed for some reason
        # restart the machine and try again
        $rebootRequired = $true
    }
    ExitWhenRebootRequired ($installRebootRequired -or $rebootRequired)
} else {
    ExitWhenRebootRequired $rebootRequired
    Write-Output 'No Windows updates found'
}