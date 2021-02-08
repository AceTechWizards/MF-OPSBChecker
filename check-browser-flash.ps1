<#
.SYNOPSIS
Script to check Adobe Flash settings in Browsers

.DESCRIPTION
This script checks to see if Adbobe Flash is installed and configured for use with older versions of Micro Focus products (such as OBM (OMi)/APM)

.PARAMETER URL
Optional parameter used to specify the top level URL that is used to connect to the application (so that it can be checked for inclusion settings)

.NOTES
Version:  1.0
Author:   Andy Doran (andy.doran@MicroFocus.com)
Created:  27-November-2020
Reason:   For Flash verification

.EXAMPLE

.\flashplayer-checks.ps1


Runs the checks on the local system

.EXAMPLE

.\flashplayer-checks.ps1 -URL https://obmserver.com/omi


Runs the checks on the local system, checking to see if the URL is present in the Flash configuration file
#>

param(
    [parameter(position = 0)]
    [ValidateSet('IE', 'FireFox')]
    [string]$Browser = "IE"
)

function script:Check-Flash-IE([ref]$isEnabled) {
    [bool]$flashEnabled = $false

    [string]$keyName = "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Ext\Settings\$script:IE_FlashCLSID"
    $key = Get-Item -Path "Registry::$keyName" -ErrorAction SilentlyContinue

    if (!($key -eq $null)) {
        $key
        $flashEnabled = $false
    }
    else {
        $flashEnabled = $true
    }

    $isEnabled.Value = $flashEnabled
}

[string]$script:IE_FlashCLSID = "{D27CDB6E-AE6D-11CF-96B8-444553540000}"
[bool]$FlashEnabled = $false
[string]$BrowserName = "Internet Explorer"

if ($Browser.ToUpper() -eq "IE") {
    Check-Flash-IE ([ref]$FlashEnabled)
}

if ($FlashEnabled) {
    Write-Host "$BrowserName is enabled for Flash"
}
else {
    Write-Host "$BrowserName is not enabled for Flash"
}