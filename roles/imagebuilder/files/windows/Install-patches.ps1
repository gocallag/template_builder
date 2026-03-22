$VerbosePreference = "Continue"

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
      [scriptblock]$Condition,
      [int]$DebounceSeconds=15
    )
    process {
        $begin = [Windows]::GetUptime()
        do {
            Start-Sleep -Seconds 1
            try {
              $result = &$Condition
            } catch {
              $result = $false
            }
            if (-not $result) {
                $begin = [Windows]::GetUptime()
                continue
            }
        } while ((([Windows]::GetUptime()) - $begin).TotalSeconds -lt $DebounceSeconds)
    }
}

param(
    [string]$UpdatePath = "E:\patches"
)

if (-not (Test-Path -Path $UpdatePath)) {
    Write-Error "The specified update path '$UpdatePath' does not exist."
    return
}

# Get all updates
try {
    $Updates = Get-ChildItem -Path $UpdatePath -Recurse | Where-Object {$_.Name -like "win*"}
} catch {
    Write-Error "Failed to retrieve updates from $UpdatePath. Error: $_"
    return
}

if (-not $Updates) {
    Write-Verbose "No updates found in $UpdatePath. Exiting."
    return
}

# Iterate through each update
ForEach ($update in $Updates) {

    # Get the full file path to the update
    $UpdateFilePath = $update.FullName

    # Logging
    Write-Verbose "Installing update $update"


    # Install update - use start-process -wait so it doesnt launch the next installation until its done
    try {
        Start-Process -wait wusa -ArgumentList "/update $UpdateFilePath","/quiet","/norestart" -ErrorAction Stop
    } catch {
        Write-Error "Failed to install update $UpdateFilePath. Error: $_"
    }
}
Write-Verbose 'Waiting for the Windows Modules Installer to exit...'
Wait-Condition {(Get-Process -ErrorAction SilentlyContinue TiWorker | Measure-Object).Count -eq 0}

Write-Verbose "Early Patching done, sleeping 60 seconds for installer cleanup."
Start-Sleep -Seconds 60