#Requires -Version 3.0

# Configure a Windows host from Autounattend.xml to get it ready for Ansible Management
# --------------------------------------------------------------------------------------
#
# Support -Verbose option
[CmdletBinding()]

Param (
    [string]$SubjectName = $env:COMPUTERNAME,
    [int]$CertValidityDays = 1095,
    [switch]$SkipNetworkProfileCheck,
    $CreateSelfSignedCert = $true,
    [switch]$ForceNewSSLCert,
    [switch]$GlobalHttpFirewallAccess,
    [switch]$DisableBasicAuth = $false,
    [switch]$EnableCredSSP
)
$Logfile = "C:\Windows\Temp\auto.log"

function WriteLog
{
Param ([string]$LogString)
$Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
$LogMessage = "$Stamp $LogString"
Add-content $LogFile -value $LogMessage
Write-Verbose $LogMessage
}

# Setup error handling.
Trap
{
    $_
    Exit 1
}
$ErrorActionPreference = "Stop"

# Get the ID and security principal of the current user account
$myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)

# Get the security principal for the Administrator role
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator

# Check to see if we are currently running "as Administrator"
if (-Not $myWindowsPrincipal.IsInRole($adminRole))
{
    Write-Output "ERROR: You need elevated Administrator privileges in order to run this script."
    Write-Output "       Start Windows PowerShell by using the Run as Administrator option."
    Exit 2
}

# Detect PowerShell version.
If ($PSVersionTable.PSVersion.Major -lt 3)
{
    Write-Log "PowerShell version 3 or higher is required."
    Throw "PowerShell version 3 or higher is required."
}

 WriteLog "Run the ansible.ps1 script to enable WinRM etc"
 $cmdOutput = ( & $PSScriptRoot\ConfigureRemotingForAnsible.ps1 -EnableCredSSP -CertValidityDays 3650 -Verbose) | Out-String
 WriteLog $cmdOutput

 WriteLog "Stop WinRM until rebooted"
 $cmdOutput = ( Stop-Service -force winrm ) | Out-String
 WriteLog $cmdOutput

 WriteLog "Set winrm to delayed start"
 $cmdOutput = (& cmd.exe /c sc.exe config winrm start= delayed-auto) | Out-String
 WriteLog $cmdOutput


 WriteLog "Set Firewall Profile"
 $cmdOutput = (Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled false) | Out-String
 WriteLog $cmdOutput

 WriteLog "Open TCP 5985"
 $cmdOutput = (& cmd.exe /c netsh advfirewall firewall add rule name="WinRM 5985" protocol=TCP dir=in localport=5985 action=allow) | Out-String
 WriteLog $cmdOutput

 WriteLog "Open TCP 5986"
 $cmdOutput = (& cmd.exe /c netsh advfirewall firewall add rule name="WinRM 5986" protocol=TCP dir=in localport=5986 action=allow) | Out-String
 WriteLog $cmdOutput

 WriteLog "Run the VMTools install script "
 $cmdOutput = ( & $PSScriptRoot\Install-VMWareTools.ps1) | Out-String
 WriteLog $cmdOutput

 WriteLog "Make {{ env_ansible_user }} user non-expiring "
 $cmdOutput = ( & cmd /C wmic useraccount where "name='{{ env_ansible_user }}'" set PasswordExpires=FALSE) | Out-String
 WriteLog $cmdOutput

 WriteLog "done"
