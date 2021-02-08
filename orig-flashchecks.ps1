<#
.SYNOPSIS
Script to check Adobe Flash settings in Browsers

.DESCRIPTION
This script checks to see if Adbobe Flash is installed and configured for use with older versions of Micro Focus products (such as OBM (OMi)/APM)

.PARAMETER URL
Optional parameter used to specify the top level URL that is used to connect to the application (so that it can be checked for inclusion settings)

.PARAMETER FirefoxPortable
Optional parameter (short name is FFP). Use to specify location of Fire Fox Portable configuration

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
    [string]$URL,

    [parameter(position=1)]
    [alias('FFP')]
    [string]$FirefoxPortable
)

#
# Function to color the table output. From here: https://www.bgreco.net/powershell/format-color/
#

function script:Format-Color([hashtable] $Colors = @{}, [switch] $SimpleMatch) {
	$lines = ($input | Out-String) -replace "`r", "" -split "`n"

	foreach($line in $lines) {
		$color = ''

		foreach($pattern in $Colors.Keys){
			if(!$SimpleMatch -and $line -match $pattern) { $color = $Colors[$pattern] }
			elseif ($SimpleMatch -and $line -like $pattern) { $color = $Colors[$pattern] }
		}

		if($color) {
			Write-Host -ForegroundColor $color $line
		} else {
			Write-Host $line
		}

	}

}

#
# IE Specific check
#

function script:Check-Flash-IE([ref]$isEnabled) {
    [bool]$flashEnabled = $false

    [string]$keyName = "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Ext\Settings\$script:IE_FlashCLSID"
    $key = Get-Item -Path "Registry::$keyName" -ErrorAction SilentlyContinue

    #
    # If the key is found then Flash is disabled
    #

    if (!($key -eq $null)) {
        $flashEnabled = $false
    }
    else {
        $flashEnabled = $true
    }

    $isEnabled.Value = $flashEnabled
}

#
# Fire fox specific checks. Check it is there but also return the version as there is a minimum supportd version for FF
#

function script:Check-Flash-FF([ref]$isEnabled, [ref]$versionInstalled, [bool]$isPortable) {
    [bool]$flashEnabled = $false

    [string]$keyName = "HKLM\SOFTWARE\MozillaPlugins\@adobe.com/FlashPlayer"
    $key = Get-Item -Path "Registry::$keyName" -ErrorAction SilentlyContinue

    if ($key -eq $null) {
        $flashEnabled = $false
    }
    else {
        $flashEnabled = $true
        $version = Get-ItemProperty -Path "Registry::$keyName" -Name "Version"
        $versionInstalled.Value = $version.Version
    }

    #
    # Now check if it is enabled for us
    #

    if ($isEnabled) {
        [string]$dataFile = $env:APPDATA + "\Mozilla\Firefox\Profiles\iph5surx.default\prefs.js"

        if (Test-Path -Path $dataFile -PathType Leaf) {
            [string]$contents = Get-Content -Path $dataFile
            
            $flashEnabled = !$contents.Contains("user_pref(`"plugin.state.flash`", 0);")
            

        }

    }

    $isEnabled.Value = $flashEnabled
}

#
# Find and check installed Browsers (currently IE, FF, Chrome, Edge
#

function script:BrowserChecks() {

    Write-Host "`nChecking which browsers are installed and configured..."

    #
    # Treat IE seperately as it ought to be installed, so doesn;t appear in the "Uninstall" section
    #

    $ie = Get-Item -Path "HKLM:\Software\Microsoft\Internet Explorer" -ErrorAction SilentlyContinue

    if ($ie -ne $null) {
        $ieInfo = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Internet Explorer" -Name svcVersion -ErrorAction SilentlyContinue
        [string]$ieVersion = ""

        if ($ieInfo -eq $null) {
            $ieInfo = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Internet Explorer" -Name Version -ErrorAction SilentlyContinue
            $ieVersion = $ieInfo.Version
        }
        else {
            $ieVersion = $ieInfo.svcVersion
        }

        Write-Host "`nInternet Explorer V$ieVersion is installed`n`tSupport for Flash $script:tense on $script:flashEndText (use of Flash will be disabled in June 2021)"
        
        #
        # See if flash is enabled or not
        #

        [bool]$ieFlash = $false
        Check-Flash-IE ([ref]$ieFlash) 

        if ($ieFlash) {
            Write-Host "`tFlash is enabled for use in Internet Explorer"
        }
        else {
            Write-Host "`tFlash is not enabled for use in Internet Explorer. Go to `"Manage add-ins`" in the IE settings to enable it" -ForegroundColor Yellow
        }
    }

    #
    # If Fire Fox Portable is being used
    #

    if ($FirefoxPortable.Length -gt 0) {
        #
        # Do Firefox checks
        #

        [bool]$ffFlash = $false
        [string]$ffVersion = ""

        Check-Flash-FF ([ref]$ffFlash) ([ref]$ffVersion) $true

        if (!$ffFlash) {
            #
            # Not enabled
            #

            Write-Host "`tFlash is not enabled in Fore Fox. Go to `Add-ons Manager`" to enable it" -ForegroundColor Yellow
        }
        else {
            #
            # Needs to be a minimum version
            #

            if ($ffVersion -ge $script:FlashVersionFF) {
                Write-Host "`tFlash is enabled in Fire Fox and is at the correct version or higher ($ffVersion)"
            }
            else {
                Write-Host "`tFlash is enabled in Fire Fox but is V$ffVersion. It must be updated to V$script:FlashVersionFF or higher" -ForegroundColor Yellow
            }
        }

    
    }

    [bool]$foundEdge = $false

    (Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" ) + (Get-ChildItem "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall") | ForEach-Object {
        $regInfo = $_ 
        [string]$keyName = $_.Name

            $keyName = $keyName.Replace("HKEY_LOCAL_MACHINE", "HKLM:")
        
            #
            # Some don;t have the DisplayName
            #

            [string]$browserName = ""

            try {
                $data = Get-ItemProperty -Path "$keyName" -Name "DisplayName" -ErrorAction SilentlyContinue
                #$data
                $browserName = $data.DisplayName
            }
            catch {
                $browserName = ""
            }

            if ($browserName -match "Google Chrome" -or $browserName -match "Mozilla Firefox" -or ($browserName -match "Edge" -and $browserName -notmatch "Update")) {
                $data = Get-ItemProperty -Path "$keyName" -Name "DisplayVersion"
                [string]$browserVersion = $data.DisplayVersion 

                Write-Host "`n$browserName V$browserVersion is installed"

                if ($browserName -match "Chrome" -or $browserName -match "Edge") {
                    if ($browserName -match "Edge") {$foundEdge = $true}
                    Write-Host "`tSupport for Flash $script:tense on $script:flashEndText"
                    if ($browserName -match "Edge") {$foundEdge = $true}
                }


            if ($browserName.Contains("Firefox")) {
                #
                # Do Firefox checks
                #

                [bool]$ffFlash = $false
                [string]$ffVersion = ""

                Check-Flash-FF ([ref]$ffFlash) ([ref]$ffVersion) $false

                if (!$ffFlash) {
                    #
                    # Not enabled
                    #

                    Write-Host "`tFlash is not enabled in Fore Fox. Go to `Add-ons Manager`" to enable it" -ForegroundColor Yellow
                }
                else {
                    #
                    # Needs to be a minimum version
                    #

                    if ($ffVersion -ge $script:FlashVersionFF) {
                        Write-Host "`tFlash is enabled in Fire Fox and is at the correct version or higher ($ffVersion)"
                    }
                    else {
                        Write-Host "`tFlash is enabled in Fire Fox but is V$ffVersion. It must be updated to V$script:FlashVersionFF or higher" -ForegroundColor Yellow
                    }
                }
        
                Write-Host "`tIt is suggested that Fire Fox ESR Portable be used to configure the browser for use with Flash"

            }
                  
        }

    }

    #
    # Old versions of Edge are in the "uninistall" - new versions picked up by Get-AppxPackage
    #

    if (!$foundEdge) {
        #
        # Older versions not on Control Panel
        #

        try {
            [string]$edgeVersion = (Get-AppxPackage -ErrorAction SilentlyContinue Microsoft.MicrosoftEdge).Version

            if ($edgeVersion -ne $null -and $edgeVersion.Length -gt 0) {
                Write-Host "`nMicrosoft Edge is V$edgeVersion is installed"
                Write-Host "`tSupport for Flash $script:tense on $script:flashEndText"
            }
        }
        catch {
            [string]$dummy = ""
        }

    }

}

#
# SHow what the file contents should be
#

function script:File-Contents() {

    [string]$whiteListPatternText = "WhiteListUrlPattern"
    [string]$allowListPatternText = "AllowListUrlPattern"
        
    Write-Host "`nThe Flash configuration file should be located at:`n`n`t$script:flashcfg`n`nand contain the lines:`n"

    foreach($required in $script:flashConfigRequired) {
        Write-Host "`t$required"
    }

    [string]$urlText = "<URL>"
    if ($URL.Length -gt 0) {$urlText = $URL}

    Write-Host "`nAdditionally, the URL(s) to be accessed must be added in the form:`n`n`t$whiteListPatternText=$urlText`n`t$allowListPatternText=$urlText`n`nWith each URL on a separate line"

    #
    # Give some "real" examples
    #

    if ($URL.Length -eq 0) {
        Write-Host "`nExamples:"

        foreach ($example in $script:exampleURL) {
            Write-Host "`n`t$whiteListPatternText=$example"
            Write-Host "`t$allowListPatternText=$example"
        }

    }

}

#
# Check the contents of the Flash Config file
#

function script:CheckConfigContents([string[]]$config) {
    #
    # Use a list for the generic items, but check specifically for whitelist items
    #

    Write-Verbose "Process the config: `n`n$config`n`n"
    [int]$whiteListPattern = 0
    [int]$allowListPattern = 0
    [bool]$checkUrl = ($URL.Length -gt 0)
    [bool]$urlInWhiteList = $false
    [bool]$urlInAllowList = $false

    Write-Host "Checking Flash configuration file: $script:flashcfg ..."

    #
    # Display results in a table for ease
    #

    [System.Data.DataTable]$Data = New-Object System.Data.DataTable
    
    #
    # Columns
    #

    [string]$col1Name = "Item Name"
    [string]$col2Name = "Present"
    [string]$col3Name = "Required Value"
    [string]$col4Name = "Actual Value"
    [string]$col5Name = "Needs Attention"

    [System.Data.DataColumn]$col1 = New-Object System.Data.DataColumn $col1Name,([String])
    [System.Data.DataColumn]$col2 = New-Object System.Data.DataColumn $col2Name,([String])
    [System.Data.DataColumn]$col3 = New-Object System.Data.DataColumn $col3Name,([string])
    [System.Data.DataColumn]$col4 = New-Object System.Data.DataColumn $col4Name,([string])
    [System.Data.DataColumn]$col5 = New-Object System.Data.DataColumn $col5Name,([string])

    $Data.Columns.Add($col1)
    #$Data.Columns.Add($col2)
    $Data.Columns.Add($col3)
    $Data.Columns.Add($col4)
    $Data.Columns.Add($col5)

    foreach($required in $script:flashConfigRequired) {
        [string]$present = "No"
        [string]$actual = "N/A"
        [string]$needsAttention = "Yes"
        [string]$foundValue = ""

        #
        # Should be x=y, but config file may have x = y so read the elements 
        #

        [string[]]$requiredArray = $required.Split("=")
        [string]$requiredItem = $requiredArray[0].Trim()
        [string]$requiredValue = $requiredArray[1].Trim()
        [bool]$foundIt = $false

        #
        # Check Whitelist/allowlist
        #

        [string]$whiteListPatternText = "WhiteListUrlPattern"
        [string]$allowListPatternText = "AllowListUrlPattern"

        #for ($i = 0; $i -eq $config.Length; $i ++) {
        foreach ($line in $config) {
            #[string]$line = "" 
            
            #try {
            #    $line = $config[$i]
            #}
            #catch {
            #    $line = ""
            #}

            Write-Verbose "Process line $i : $line"

            if ($line -ne $null -and $line.Length -gt 0 -and $line.Contains("=")) {           
                [string[]]$foundArray = $line.Split("=")
                [string]$foundItem = $foundArray[0].Trim()
                $foundValue = $foundArray[1].Trim()

                Write-Verbose "    Item: $foundItem"
                Write-Verbose "    Value: $foundValue"

                if ($foundValue -eq $null) {$foundValue = ""}

                if ($foundItem.ToUpper() -eq $allowListPatternText.ToUpper()) {
                    $allowListPattern +=1

                    #
                    # If we are looking for the Url then see if it is found
                    #

                    if ($checkUrl -and $foundValue.ToUpper().Contains($URL.ToUpper())) {
                        $urlInAllowList = $true
                    }

                }

                if ($foundItem.ToUpper() -eq $whiteListPatternText.ToUpper()) {
                    $whiteListPattern +=1

                    #
                    # If we are looking for the Url then see if it is found
                    #

                    if ($checkUrl -and $foundValue.ToUpper().Contains($URL.ToUpper())) {
                        $urlInWhiteList = $true
                    }

                }

                #Write-Host "Compare: $required with $foundItem"

                if ($foundItem.ToUpper() -eq $requiredItem.ToUpper()) {
                    #
                    # Compare
                    #

                    $foundIt = $true

                    if ($foundValue.ToUpper() -ne $requiredValue.ToUpper()) {
                        #
                        # Not a match
                        #

                        $needsAttention += " (modify line to read: $required)"
                    }
                    else {
                        $needsAttention = "No"
                    }

                    #break
                }

            }

        }

        if ($foundIt) {
            $present = "Yes"
        }
        else {
            $needsAttention += " (add line: $required)"
        }

        #
        # Add the resukts to the Data table
        #

        [System.Data.DataRow]$myRow = $Data.NewRow()
        $myRow.$col1Name = $requiredItem
        #$myRow.$col2Name = $present
        $myRow.$col3Name = $requiredValue
        $myRow.$col4Name = $foundValue
        $myRow.$col5Name = $needsAttention

        $Data.Rows.Add($myRow)
    }

    $Data | Format-Table -AutoSize | Format-Color @{'Yes' = 'Yellow'; 'No' = 'Green'}

    #
    # Check whitelist and allowlist
    #

    if ($checkUrl) {
        #
        # See if our Url is defined or not... needs to be in both
        #

        if (!$urlInWhiteList -and !$urlInAllowList) {
            #
            # Neither defined
            #

            Write-Host "***** The URL $URL is not in the white list or allow list. Add these lines to the config file:`n`n`t$whiteListPatternText=$URL`n`t$allowListPatternText=$URL" -ForegroundColor Yellow
        }
        else {
            #
            # If bith are defgined, all is good
            #

            if ($urlInWhiteList -and $urlInAllowList) {
                Write-Host "The URL $URL is correctly defined in the white list and allow list"
            }
            else {
                
                if (!$urlInWhiteList) {
                    Write-Host "***** The URL $URL is not in the white list. Add this line to the config file:`n`n`t$whiteListPatternText=$URL" -ForegroundColor Yellow
                }

                if (!$urlInAllowList) {
                    Write-Host "***** The URL $URL is not in the allow list. Add this line to the config file:`n`n`t$allowListPatternText=$URL" -ForegroundColor Yellow
                }

            } # both

        } # Neither found

    } # Check URL
    else {

        if ($whiteListPattern -eq 0 -and $allowListPattern -eq 0) {
            #
            # Nothing defined so warn they are both required
            #

            Write-Host "***** There are no URLs on the white list or allow list. The top level application URL(s) must be added in the form:`n`n`t$whiteListPatternText=<URL>`n`t$allowListPatternText=<URL>`n`nWith each URL on a separate line" -ForegroundColor Yellow
        }
        else {
        
            if ($whiteListPattern -gt 0 -and $allowListPattern -gt 0) {
                #
                # Both defined - but we cannot know if the OBM Urls are there
                #

                Write-Host "The white list ($whiteListPatternText) and allow list ($allowListPatternText) entries are present, make sure the application top level URLs are included)" -ForegroundColor Yellow
            }
            else {

                if ($whiteListPattern -eq 0) {
                    #
                    # No white list
                    #

                    Write-Host "***** There are no URLs on the white list. The top level application URL(s) must be added in the form:`n`n`t$whiteListPatternText=<URL>`n`nWith each URL on a separate line" -ForegroundColor Yellow
                    Write-Host "`nExamples:"
                }
                else {
                    #
                    # Present but we cannot know which
                    #

                    Write-Host "The white list ($whiteListPatternText) entries are present, make sure the application top level URLs are included)"
                }

                if ($allowListPattern -eq 0) {
                    #
                    # No allow list
                    #

                    Write-Host "***** There are no URLs on the allow list. The application top level URL(s) must be added in the form:`n`n`t$allowListPatternText=<URL>`n`nWith each URL on a separate line" -ForegroundColor Yellow
                }
                else {
                    #
                    # Present but we cannot know which
                    #

                    Write-Host "The allow list ($allowListPatternText) entries are present, make sure the application top level URLs are included)"
                }

            } # Check both > 0

        } # Check both = 0

        Write-Host "`nExamples:"

        foreach ($example in $script:exampleURL) {
            Write-Host "`n`t$whiteListPatternText=$example"
            Write-Host "`t$allowListPatternText=$example"
        }


    } # Check url
}

##########################################################################################################################################
# Start here
##########################################################################################################################################

#
# Global variables/constants
#

#
# The CLSID for Flash add-on for IE
#

[string]$script:IE_FlashCLSID = "{D27CDB6E-AE6D-11CF-96B8-444553540000}"

#
# Flash config file - entries that we require, plus example URL information
#

[string[]]$script:flashConfigRequired = "SilentAutoUpdateEnable=0", "AutoUpdateDisable=1", "EOLUninstallDisable=1", "TraceOutputEcho=1", "EnableWhitelist=1", "WhitelistPreview=0", "EnableAllowList=1", "AllowListPreview=0"
[string[]]$script:exampleURL = "https://obmgateway.thiscorp.com/omi","https://apmserver.thiscorp.com/HPBSM"

#
# Default System32 - on 64 bit systems it needs to be the 32 bit directory. Will flip it later if this is 32 bit
#

[string]$script:WindowsSys = $env:windir + "\SysWow64"

#
# Date information for checks later
#

[datetime]$flashEnd = "31-Dec-2020 23:59:59"
[string]$script:flashEndText = "31st December 2020"
[bool]$script:pastDate = $false
[string]$script:tense = "will end" 

#
# For Fire Fox - the minimum Flash version required (lower versions will prompt for upgrade when used)
#

[string]$script:FlashVersionFF = "32.0.0.453"

#
# For the text - this could be running after the Flash support ends
#

if ((Get-Date) -gt (Get-Date $flashEnd)) {
    $script:pastDate = $true
    $script:tense = "ended"
}

#
# Hello
#

[string]$myVersion = "1.1"

Write-Host @"

**********************************************************************************************************
Micro Focus: Browser and Flash check tool V$myVersion

This utility checks on the currently installed browsers and whether they have been enabled for use with 
Adobe Flash for older installations of Micro Focus products such as OBM (OMi) and APM. The current
versions of these producs have been updated and do not require the Flash Player, but where the upgrade has
not yet taken place the Flash Player is still required for some interfaces.
**********************************************************************************************************

"@

#
# Need to look in 32 bit location, so on a 64 bit server use SysWow64
#

if (!(Test-Path -Path $script:WindowsSys -PathType Container)) {
    $script:WindowsSys = $env:windir + "\System32"
}

#
# See if Macromedia exists
#

[string]$script:macroDir = $script:WindowsSys + "\Macromed"
[string]$script:flashDir = $script:macroDir + "\Flash"
[string]$script:flashcfg = $script:flashDir + "\mms.cfg"
[bool]$showContentHelp = $true

[string]$flashNotFound = "directory not found, this system cannot use the Flash player with older versions of Micro Focus `nproducts such as OBM (OMi) or APM. Install the Adobe Flash Player or consider upgrading to the latest `nMicro Focus product versions."

#
# If "portable" is specified then replace everything with that
#

if ($FirefoxPortable.Length -gt 0) {
    Write-Host "Checking for configuration with Fire Fox Portable"

    $script:macroDir = $FirefoxPortable
    $script:flashDir = $script:macroDir + "\Data\plugins"
    $script:flashcfg = $script:flashDir + "\mms.cfg"
}


if (!(Test-Path -Path $script:macroDir -PathType Container)) {
    Write-Host "Macromedia $flashNotFound" -ForegroundColor Yellow
}
else {
    #
    # Check Flash
    #

    if (!(Test-Path -Path $script:flashDir -PathType Container)) {
        Write-Host "Flash $flashNotFound" -ForegroundColor Yellow
    }
    else {
        #
        # See if the container is there
        #

        if (!(Test-Path -Path $script:flashcfg -PathType Leaf)) {
            Write-Host "Flash configuration file is not present. This must be configured in order to continue to use Flash plugins with older versions of Micro Focus products such as OBM (OMi)" -ForegroundColor Yellow
        }
        else {
            $showContentHelp = $false
            [string[]]$configContents = Get-Content -Path $script:flashcfg

            CheckConfigContents $configContents
        }

    }
}

if ($showContentHelp) {
    File-Contents
}

BrowserChecks

Write-Host @"


Note: 

The results shown by this utility are not a guarantee that this system can use Flash to access older Micro Focus 
products in the future. The configuration of this system may change and invalidate the current set of results. Please check 
the document located here:

https://softwaresupport.softwaregrp.com/doc/KM03763436  

for up to date information.
"@
Write-Host ""