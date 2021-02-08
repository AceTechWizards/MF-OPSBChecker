<#
.SYNOPSIS
Script to check Adobe Flash settings in Browsers

.DESCRIPTION
This script checks to see if Adobe Flash is installed and configured for use with older versions of Micro Focus products (such as OBM (OMi)/APM)

.PARAMETER URL
Optional parameter used to specify the top level URL that is used to connect to the application (so that it can be checked for inclusion settings)

.PARAMETER FirefoxPortable
Optional parameter (short name is FFP). Use to specify location of Fire Fox Portable configuration

.Parameter CheckAllBrowsers
If the -FirefoxPortable parameter is used, then only Firefox Portable checks are made. All other browsers will be ignored. Use this switch to override that behaviour

.Parameter StopNoFlash
Optional switch - stop further checks if Flash Player is not installed

.Parameter HideCurrentURLList
Optional switch - by default, the full list of URLs that are currently defined in the white/allow list will be displayed. This can be suppressed using this switch (which has an alias of -HCL)

.NOTES
Version:  1.11
Author:   Andy Doran (andy.doran@MicroFocus.com)
Created:  27-November-2020 (this update: 18-December-2020)
Reason:   For Flash verification

.EXAMPLE

.\flashplayer-checks.ps1


Runs the checks on the local system

.EXAMPLE

.\flashplayer-checks.ps1 -URL https://obmserver.com/omi


Runs the checks on the local system, checking to see if the URL is present in the Flash configuration file

.EXAMPLE

.\flashplayer-checks.ps1 -FFP H:\


Runs checks for Firefox Portable, specifying the location of the Firefox Portable configuraiton files as H:\
#>

#
# Inputs
#

param(
    [parameter(position=0)]
    [string]$URL,

    [parameter(position=1)]
    [alias('FFP')]
    [string]$FirefoxPortable,

    [parameter(position=2)]
    [switch]$CheckAllBrowsers,

    [parameter(position=3)]
    [alias('StopNoFlash')]
    [switch]$StopIfFlashNotInstalled,

    [parameter(position=4)]
    [alias('HCL')]
    [switch]$HideCurrentURLList,

    [parameter(position=5)]
    [switch]$Help
)

#
# Verify the URL and return only the host part for checks
#

function script:Check-URL([string]$inputURL, [ref]$isURL, [ref]$newURL) {
    [bool]$inputIsURL = $false
    [string]$new = $inputURL

    $uri = $inputURL -as [System.Uri]

    if ($uri.AbsoluteURI -ne $null) {
        [string]$scheme = $uri.Scheme
        [string]$host = $uri.DnsSafeHost  

        $new = $scheme + "://$host"
        
        if($scheme -match "http" -or $schem -match "https") {
            $inputIsURL = $true
        }

    }

    $newURL.Value = $new
    $isURL.Value = $inputIsURL
}

#
# Check for the HotFix that completely disables flash
#

function script:Has-Hotfx([string]$HotFixID, [ref]$isInstalled) {
    [bool]$found = $false

    (Get-WmiObject -Class Win32_QuickFixEngineering) | ForEach-Object {
        [string]$HF = $_.HotfixID
        Write-Verbose "Update: $HF - checking $HotFixID" 


        if ($HF -match $HotFixID) {
            $found = $true
            #break
        }
    }

    $isInstalled.Value = $found
}

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
# Save on code - add row to browser table
#

function script:Add-To-Browser-Table([string]$browserName, [string]$browserVersion) {
    [System.Data.DataRow]$newRow = $script:browserTable.NewRow()
    $newRow.$script:browserCol1 = $browserName
    $newRow.$script:browserCol2 = $browserVersion
    $script:browserTable.Rows.Add($newRow)
}

#
# Get the list of browsers and also Adobe Flash
#

function script:Get-Checklist() {
    
    if ($FirefoxPortable.Length -eq 0 -or ($FirefoxPortable.Length -gt 0 -and $CheckAllBrowsers)) {
        #
        # Check 32 and 64 bit registry
        #

        [bool]$foundEdge = $false

        Write-Host "`nChecking installed applications ..."

        (Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" ) + (Get-ChildItem "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall") | ForEach-Object {
            [string]$appDisplayName = ""
            [string]$keyName = $_.Name

            $keyName = $keyName.Replace("HKEY_LOCAL_MACHINE", "HKLM:")

            #
            # Not everything has a Display Name so do this in a try/catch block
            #

            try {
                $data = Get-ItemProperty -Path "$keyName" -Name "DisplayName" -ErrorAction SilentlyContinue
                $appDisplayName = $data.DisplayName
            }
            catch {
                $appDisplayName = ""
            }


            if ($appDisplayName.Length -gt 0 -and $appDisplayName -match "Google Chrome" -or $appDisplayName -match "Mozilla Firefox" -or $appDisplayName -match "Adobe Flash Player 32 NPAPI" -or ($appDisplayName -match "Edge" -and $appDisplayName -notmatch "Update")) {
                $data = Get-ItemProperty -Path "$keyName" -Name "DisplayVersion"
                [string]$appVersion = $data.DisplayVersion
            
                Write-Verbose "Found in registry: $appDisplayName ($appVersion)"

                if ($appDisplayName -notmatch "Adobe") {
                    #
                    # This is a browser
                    #

                    Add-To-Browser-Table $appDisplayName $appVersion

                    if ($appDisplayName -match "Chrome") {$script:chromInstalled = $true}
                    if ($appDisplayName -match "FireFox") {$script:firefoxInstalled = $true}
                
                    if ($appDisplayName -match "Edge") {
                        $script:edgeInstalled = $true
                        $foundEdge = $true
                    }

                }
                else {
                    #
                    # Found Flash
                    #

                    Write-Host "$appDisplayName V$appVersion is installed" -ForegroundColor Green
                    $script:flashInstalled = $true
                }
             
            }

        }

        #
        # Windows and IE are as one so handle that differently
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

            Write-Verbose "IE V$ieVersion"

            Add-To-Browser-Table "Microsoft Internet Explorer" $ieVersion
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
                    Write-Verbose "Found Edge V$edgeVersion"

                    Add-To-Browser-Table "Microsoft Edge" $edgeVersion
                }
            }
            catch {
                Write-Verbose "Older Edge not found"
            }

        }

    }

    #
    # Now check that the Portable Fire Fox is present
    #

    if ($FirefoxPortable.Length -gt 0) {
        #
        # Make sure we can see the file FirefoxPortable.exe
        #

        [string]$portableExe = $FirefoxPortable + "App\Firefox\Firefox.exe" # we already made sure this ends with a \ even if not provided

        if (!(Test-Path -Path $portableExe -PathType Leaf)) {
            Write-Host "***** Firefox Portable could not be verified at the specified location: $FirefoxPortable" -ForegroundColor Yellow
            Write-Verbose "Checked: $portableExe"
        }
        else {
            #
            # Get the version
            #

            [string]$portableVersion = (Get-Item $portableExe).VersionInfo.FileVersion
            Write-Verbose "Firefox Portable V$portableVersion"
            $script:ffportableInstalled = $true

            Add-To-Browser-Table "Firefox Portable" $portableVersion
        }

    }

}

#
# SHow what the file contents should be
#

function script:File-Contents() {
    [string]$whiteListPatternText = "WhiteListUrlPattern"
    [string]$allowListPatternText = "AllowListUrlPattern"
        
    foreach($required in $script:flashConfigRequired) {
        Write-Host "`t$required" -ForegroundColor Yellow
    }

    [string]$urlText = "<URL>"
    if ($URL.Length -gt 0) {$urlText = $URL}

    Write-Host "`nAdditionally, the URL(s) to be accessed must be added in the form:`n`n`t$whiteListPatternText=$urlText`n`t$allowListPatternText=$urlText`n`nWith each URL on a separate line" -ForegroundColor Yellow

    #
    # Give some "real" examples
    #

    if ($URL.Length -eq 0) {
        Write-Host "`nExamples:" -ForegroundColor Yellow

        foreach ($example in $script:exampleURL) {
            Write-Host "`n`t$whiteListPatternText=$example" -ForegroundColor Yellow
            Write-Host "`t$allowListPatternText=$example" -ForegroundColor Yellow
        }

    }

}

#
# Loop through the config file data to see if we have a match
#

function script:Check-For-Item([string[]]$configData, [string]$requiredItem, [string]$requiredValue, [ref]$itemFound, [ref]$itemCorrect, [ref]$itemValue) {
    [bool]$found = $false
    [bool]$correct = $false
    [string]$foundValue = ""

    foreach($line in $configData) {
        
        if ($line.Length -gt 0 -and $line.Contains("=")) {
            #
            # Only process lines with information and the format of x=y
            #

            [string[]]$lineArray = $line.Split("=")
            [string]$foundItem = $lineArray[0]
            $foundValue = $lineArray[1]

            if ($foundItem.ToUpper() -eq $requiredItem.ToUpper()) {
                $found = $true

                if ($foundValue.ToUpper() -eq $requiredValue.ToUpper()) {
                    $correct = $true
                }

                break
            }

        }

    }

    $itemFound.Value = $found
    $itemValue.Value = $foundValue
    $itemCorrect.Value = $correct
}

#
# Check the Flash config file either in the Windows System or portable location
#

function script:Check-Config-Flash([bool]$portable) {
    [string]$configFile = $script:WindowsSys + "\MacroMed\Flash\mms.cfg" # - potable still uses the local system file, not $FirefoxPortable + "Data\plugins\mms.cfg"
    [string]$msgInfo = "portable config"
    [string]$whiteListPatternText = "WhiteListUrlPattern"
    [string]$allowListPatternText = "AllowListUrlPattern"
    [int]$whiteListPattern = 0
    [int]$allowListPattern = 0
    [bool]$checkUrl = ($URL.Length -gt 0)
    [bool]$urlInWhiteList = $false
    [bool]$urlInAllowList = $false

    [string]$allowList = ""
    [string]$whiteList = ""
                    
    if (!$portable) {
        #$configFile = $script:WindowsSys + "\MacroMed\Flash\mms.cfg"
        $msgInfo = "config"
    }

    Write-Host "`nChecking the Flash $msgInfo file $configFile ..."

    if (!(Test-Path -Path $configFile -PathType Leaf)) {
        Write-Host "***** The $msgInfo file is missing. It should be placed in this location:`n`n$configFile`n`nand contain the following information:`n" -ForegroundColor Yellow
        File-Contents
        return
    }

    #
    # Use a table for the output
    #

    [string]$configCol1 = "Item Name"
    [string]$configCol2 = "Current Value"
    [string]$configCol3 = "Expected Value"
    [string]$configCol4 = "Notes"

    [System.Data.DataTable]$configTable = New-Object System.Data.DataTable

    [System.Data.DataColumn]$cCol1 = New-Object System.Data.DataColumn $configCol1, ([string])
    [System.Data.DataColumn]$cCol2 = New-Object System.Data.DataColumn $configCol2, ([string])
    [System.Data.DataColumn]$cCol3 = New-Object System.Data.DataColumn $configCol3, ([string])
    [System.Data.DataColumn]$cCol4 = New-Object System.Data.DataColumn $configCol4, ([string])

    $configTable.Columns.Add($cCol1)
    $configTable.Columns.Add($cCol2)
    $configTable.Columns.Add($cCol3)
    $configTable.Columns.Add($cCol4)

    #
    # Now look at the file contents
    #

    [string[]]$configContents = Get-Content -Path $configFile

    #
    # Loop through the required contents and check each exists
    #

    foreach($requiredLine in $script:flashConfigRequired) {
        #
        # This is in the format X = y 
        #

        [string[]]$requiredArray = $requiredLine.Split("=")
        [string]$requiredItem = $requiredArray[0]
        [string]$requiredValue = $requiredArray[1]

        #
        # Now loop through the file contents top see if we have a match
        #

        [bool]$match = $false
        [string]$foundValue = ""
        [bool]$correct = $false
        [string]$notes = ""

        Check-For-Item $configContents $requiredItem $requiredValue ([ref]$match) ([ref]$correct) ([ref]$foundValue)

        if ($match) {
            
            if ($correct) {
                $notes = "No action required"
            }
            else {
                $notes = "Modify line to read: $requiredItem=$requiredValue"
            }

        }
        else {
            $foundValue = "*missing*"
            $notes = "Add new line: $requiredItem=$requiredValue"
        }

        #
        # Add this information
        #

        [System.Data.DataRow]$newRow = $configTable.NewRow()
        $newRow.$configCol1 = $requiredItem
        $newRow.$configCol2 = $foundValue
        $newRow.$configCol3 = $requiredValue
        $newRow.$configCol4 = $notes
        $configTable.Rows.Add($newRow)
    }

    #
    # Go through the config file now looking for whitelist and allowlist - different sort of processing so process here
    #

    foreach ($line in $configContents) {

        if ($line.Length -gt 0 -and ($line -match $allowListPatternText -or $line -match $whiteListPatternText)) {
            [string[]]$lineArray = $line.Split("=")
            [string]$itemName = $lineArray[0]
            [string]$itemValue = $lineArray[1]


            if ($itemName.ToUpper() -eq $allowListPatternText.ToUpper()) {
                $allowListPattern +=1

                #
                # To display what is currently there
                #

                if ($allowList.Length -eq 0) {
                    $allowList = "`t$line"
                }
                else {
                    $allowList += "`n`t$line"
                }

                #
                # If we are looking for the Url then see if it is found
                #

                if ($checkUrl -and $itemValue.ToUpper().Contains($URL.ToUpper())) {
                    $urlInAllowList = $true
                }

            }

            if ($itemName.ToUpper() -eq $whiteListPatternText.ToUpper()) {
                $whiteListPattern +=1

                #
                # To display what is currently there
                #

                if ($whiteList.Length -eq 0) {
                    $whiteList = "`t$line"
                }
                else {
                    $whiteList += "`n`t$line"
                }

                #
                # If we are looking for the Url then see if it is found
                #

                if ($checkUrl -and $itemValue.ToUpper().Contains($URL.ToUpper())) {
                    $urlInWhiteList = $true
                }

            }

        }

    }
    
    $configTable | Format-Table -AutoSize | Format-Color @{"\bAdd\b" = 'Yellow'; "\bModify\b" = 'Yellow'; "\bNo Action\b" = 'Green'}

    #
    # If we have white/allow list - show here
    #

    if (($whiteList.Length -gt 0 -or $allowList.Length -gt 0) -and !$HideCurrentURLList) {

        if ($whiteList.Length -gt 0) {
            Write-Host "`nCurrent White List:`n`n$whiteList"
        }

        if ($allowList.Length -gt 0) {
            Write-Host "`nCurrent Allow List:`n`n$allowList"
        }

        Write-Host "" # Reason for extra "if" ... just for formatting
    }
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
            # If both are defgined, all is good
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
    [string]$flashVersion = ""

    [string]$keyName = "HKLM\SOFTWARE\MozillaPlugins\@adobe.com/FlashPlayer"
    $key = Get-Item -Path "Registry::$keyName" -ErrorAction SilentlyContinue

    if ($key -eq $null) {
        $flashEnabled = $false
    }
    else {
        $flashEnabled = $true
        $version = Get-ItemProperty -Path "Registry::$keyName" -Name "Version"
        $flashVersion = $version.Version
    }

    #
    # Now check if it is enabled for us
    #

    if ($isEnabled) {
        [string]$dataFile = $env:APPDATA + "\Mozilla\Firefox\Profiles\iph5surx.default\prefs.js"
        if ($isPortable) {$dataFile = $FirefoxPortable + "Data\profile\prefs.js"}

        if (Test-Path -Path $dataFile -PathType Leaf) {
            [string]$contents = Get-Content -Path $dataFile
            
            $flashEnabled = !$contents.Contains("user_pref(`"plugin.state.flash`", 0);")
            

        }

    }

    $versionInstalled.Value = $flashVersion
    $isEnabled.Value = $flashEnabled
}

#
# Check each discovered browser
#

function script:BrowserChecks() {
    Write-Host "`nChecking Flash Support in browsers ..."
    [string]$future = "Ends:"
    [string]$past = "Ended:"
    [string]$Yes = "Yes"
    [string]$No = "No"

    foreach($row in $script:browserTable.Rows) {
        [string]$enabledText = $No
        [string]$browserName = $row.Item($script:browserCol1)
        [string]$browserVersion = $row.Item($script:browserCol2)

        Write-Verbose "Check Browser: $browserName"
        Write-Verbose "Version: $browserVersion"

        [bool]$flashEnabled = $false
        [string]$notes = ""
        [string]$support = ""

        #
        # IE and Edge
        #

        if ($browserName -match "Microsoft") {
            #
            # Edge or IE
            #

            if ((Get-Date) -lt (Get-Date $script:msSupportEndDate)) {
                $support = "$future $script:msSupportEndDateDisplay"
            }
            else {
                $support = "$past $script:msSupportEndDateDisplay"
            }

            if ($browserName -notmatch "Edge") {
                Check-Flash-IE ([ref]$flashEnabled)

                if ($flashEnabled) {
                    $enabledText = $Yes
                    $notes = ""
                }
                else {
                    $enabledText = $No
                    $notes = "Go to `"Manage AddOns`" to enable Flash for Internet Explorer"
                }

            }
            else {
                $enabledText = "N/A"
                $notes = "Edge is not supported for use with Flash"
            }

        }

        #
        # Chrome
        #

        if ($browserName -match "Chrome") {

            if ((Get-Date) -lt (Get-Date $script:chromeSupportEndDate)) {
                $support = "$future $script:chromeSupportEndDateDisplay"
            }
            else {
                $support = "$past $script:chromeSupportEndDateDisplay"                
            }

            $enabledText = "N/A"
            $notes = "Chrome is not supported for use with Flash"
        }

        #
        # Firefox
        #

        if ($browserName -match "FireFox") {
            [bool]$portable = $false
            if ($browserName -match "Portable") {$portable = $true}

            if ((Get-Date) -lt (Get-Date $script:ffSupportEndDate)) {
                $support = "$future $script:ffSupportEndDateDisplay"
            }
            else {
                $support = "$past $script:ffSupportEndDateDisplay"                
            }

            $installedVersion = ""

            Check-Flash-FF ([ref]$flashEnabled) ([ref]$installedVersion) $portable

            if ($flashEnabled) {
                $enabledText = $Yes
                $notes = ""

                if (!($installedVersion.Length -gt 0 -and $installedVersion -ge $script:FlashVersionFF)) {

                    if ($installedVersion.Length -gt 0) {
                        $notes += "Flash V$installedVersion should be updated to V$script:FlashVersionFF"
                    }
                    else {
                        $notes += "Version unknown - it should be updated to V$script:FlashVersionFF"
                    }

                }

            }
            else {
                $enabledText = $No
                $notes = "Go to `"Addons`" then `"Plugins`" to enable Flash"
            }

            #
            # If FF is greater than 84 then it disables flash anyway
            #

            if ($browserVersion -ge $script:FlashDisabledFFVersion) {
                $enabledText = "N/A"
                $notes = "The Firefox browser release $browserVersion disables Flash - if no other browsers supporting Flash are installed, try using Firefox Portable release 78.5"

                if ($FirefoxPortable.Length -eq 0) {
                    $script:FinalMessage = $notes
                }

            }

        }

        $row.Item($script:browserCol3) = $enabledText
        #$row.Item($script:browserCol4) = $support
        #$row.Item($script:browserCol5) = $notes
    }

    $script:browserTable | Format-Table -AutoSize | Format-Color @{'\bEnded:\b' = 'Red'; "\b$Yes\b" = 'Green'; "\b$No\b" = 'Yellow'; "\bupdated\b" = 'Yellow'}
}

#
# Main Routine
#

function script:Main() {
    #
    # Make sure the URL is valid
    #

    [bool]$isOK = $false
    [string]$newURL = ""

    if ($URL.Length -gt 0) {
        Check-URL $URL ([ref]$isOK) ([ref]$newURL)

        if ($isOK) {
            #
            # Set the URL to be the host part as the top level is what will be registered
            #

            $URL = $newURL
        }
        else {
            #
            # Invalid URL given so ignore
            #

            write-host "***** Invalid URL specified, this will be ignored ($URL)" -ForegroundColor Yellow
            $URL = ""
        }

    }

    #
    # If the KB that disables flash permanently is installed, all bets are off
    #

    [bool]$kbInstalled = $false
    Has-Hotfx $script:FlashIsGoneKBID ([ref]$kbInstalled)

    if ($kbInstalled) {
        Write-Host "`nThe Microsoft Update for $script:FlashIsGoneKBID has been installed. This disables the Flash Player for Microsoft products" -ForegroundColor Yellow
    }

    #
    # Start by getting the installed browsers and apps we need to process
    #

    Get-Checklist

    if (!$script:flashInstalled -and ($FirefoxPortable.Length -eq 0 -or $CheckAllBrowsers)) {
        #
        # Message speaks for itself
        #

        if ($StopIfFlashNotInstalled) {
            Write-Host "***** Adobe Flash is not installed - no further checks will be made as this means that any browsers installed will not support Flash" -ForegroundColor Yellow
            return
        }
        else {
            Write-Host "Adobe Flash player is not installed - checks will only be for the browser plugin"
        }

    }

    #
    # Before checking the browers, check the Macromedia config file
    #

    if ($script:ffportableInstalled) {
        Check-Config-Flash $true
    }

    if (!$script:ffportableInstalled) { # only check once no matter waht the option -or ($script:ffportableInstalled -and $CheckAllBrowsers)) {
        Check-Config-Flash $false
    }

    #
    # Check Browser Flash Support
    #

    BrowserChecks

    if ($script:FinalMessage.Length -gt 0) {
        Write-Host $script:FinalMessage
    }

}

# **************************************************************************************************************************************************************************
# Entry point
# **************************************************************************************************************************************************************************

[string]$script:myVersion = "1.2"
[string]$script:FlashIsGoneKBID = "KB4577586"

[datetime]$script:ffSupportEndDate = "31-Dec-2020 23:59:59"
[string]$script:ffSupportEndDateDisplay = "31-Dec-2020"
[datetime]$script:chromeSupportEndDate ="31-Dec-2020 23:59:59"
[string]$script:chromeSupportEndDateDisplay = "31-Dec-2020"
[datetime]$script:msSupportEndDate = "31-Dec-2020 23:59:59"
[string]$script:msSupportEndDateDisplay = "31-Dec-2020"
[datetime]$script:FlashRemoval = "30-Jun-2021 23:59:59"
[string]$script:FlashRemovalDisplay = "30-Jun-2021"

[bool]$script:flashInstalled = $false
[bool]$script:ieInstalled = $false
[bool]$script:chromInstalled = $false
[bool]$script:edgeInstalled = $false
[bool]$script:firefoxInstalled = $false
[bool]$script:ffportableInstalled = $false

[string]$script:FinalMessage = ""

#
# The CLSID for Flash add-on for IE
#

[string]$script:IE_FlashCLSID = "{D27CDB6E-AE6D-11CF-96B8-444553540000}"

#
# For Fire Fox - the minimum Flash version required (lower versions will prompt for upgrade when used)
#

[string]$script:FlashVersionFF = "32.0.0.453"
[string]$script:FlashDisabledFFVersion = "84.0"

#
# For the browser list
#

[string]$script:browserCol1 = "Browser"
[string]$script:browserCol2 = "Version"
[string]$script:browserCol3 = "Flash Enabled"
#[string]$script:browserCol4 = "Support"
#[string]$script:browserCol5 = "Notes"

[System.Data.DataTable]$script:browserTable = New-Object System.Data.DataTable

[System.Data.DataColumn]$bCol1 = New-Object System.Data.DataColumn $script:browserCol1, ([string])
[System.Data.DataColumn]$bCol2 = New-Object System.Data.DataColumn $script:browserCol2, ([string])
[System.Data.DataColumn]$bCol3 = New-Object System.Data.DataColumn $script:browserCol3, ([string])
#[System.Data.DataColumn]$bCol4 = New-Object System.Data.DataColumn $script:browserCol4, ([string])
#[System.Data.DataColumn]$bCol5 = New-Object System.Data.DataColumn $script:browserCol5, ([string])

$script:browserTable.Columns.Add($bCol1)
$script:browserTable.Columns.Add($bCol2)
$script:browserTable.Columns.Add($bCol3)
#$script:browserTable.Columns.Add($bCol4)
#$script:browserTable.Columns.Add($bCol5)

#
# Make sure the input for poratable ends with a \
#

if ($FirefoxPortable.Length -gt 0) {
    
    if (!$FirefoxPortable.EndsWith("\")) {
        $FirefoxPortable += "\"
    }

}

#
# Flash config file - entries that we require, plus example URL information
#

[string[]]$script:flashConfigRequired = "SilentAutoUpdateEnable=0", "AutoUpdateDisable=1", "EOLUninstallDisable=1", "TraceOutputEcho=1", "EnableWhitelist=1", "WhitelistPreview=0", "EnableAllowList=1", "AllowListPreview=0"
[string[]]$script:exampleURL = "https://obmgateway.thiscorp.com/","https://apmserver.thiscorp.com"

#
# Need to look in 32 bit location, so on a 64 bit server use SysWow64
#

[string]$script:WindowsSys = $env:windir + "\SysWow64"

if (!(Test-Path -Path $script:WindowsSys -PathType Container)) {
    $script:WindowsSys = $env:windir + "\System32"
}

#
# URLs
#

[string]$script:urlFireFox = "https://blog.mozilla.org/futurereleases/2020/11/17/ending-firefox-support-for-flash/"
[string]$script:urlMS = "https://blogs.windows.com/msedgedev/2020/09/04/update-adobe-flash-end-support/"
[string]$script:urlGeneral = "https://blogs.sap.com/2020/12/10/how-to-keep-enterprise-flash-applications-accessible-in-2021/"
[string]$script:urlAdobe = "https://www.adobe.com/content/dam/acom/en/devnet/flashplayer/articles/flash_player_admin_guide/pdf/latest/flash_player_32_0_admin_guide.pdf"
[string]$script:urlChrome = "https://www.chromium.org/flash-roadmap#TOC-Flash-Player-blocked-as-out-of-date-Target:-All-Chrome-versions---Jan-2021-"

#
# Call the main routine
#

[string]$textVersion = "Micro Focus: Browser and Flash check tool V$script:myVersion"
[string]$header = $textVersion + "`n" + ("=" * $textVersion.Length)
Write-Host @"

**********************************************************************************************************
$header

This utility checks on the currently installed browsers and whether they have been enabled for use with 
Adobe Flash for older installations of Micro Focus products such as OBM (OMi) and APM. 

The latest versions of these products have been updated and do not require the Flash Player, but where 
the upgrade has not yet taken place the Flash Player is still required for some interfaces.

Note: The results shown by this utility are not a guarantee that this system can use Flash to access older 
Micro Focus products in the future. The configuration of this system may change and invalidate the current 
set of results. 

Consider upgrading your Micro Focus products to current versions to take advantage of new features and 
functionality in addition to Flash Independent operation.

The following links provide more information relating to the removal of Flash from browsers:

Adobe Admin Guide (configuring Flash):
	$script:urlAdobe
	
Microsoft (Internet Explorer and Edge): 
	$script:urlMS

Firefox: 
	$script:urlFireFox

Chrome:
	$script:urlChrome
	
Instructions on keeping Flash support in browsers beyond the information in the above links can be found
in several blogs on the internet, for example:

	$script:urlGeneral
	
"@

#[string]$lastMessage = "`nPlease be fully aware that Microsoft %1 for the Flash player on Windows on $script:msSupportEndDateDisplay. See `nthe article:`n`n`thttps://blogs.windows.com/msedgedev/2020/09/04/update-adobe-flash-end-support/`n"

#if ((Get-Date) -lt (Get-Date $script:msSupportEndDate)) {
#    $lastMessage = $lastMessage.Replace("%1", "will end support")
#}
#else {
#    $lastMessage = $lastMessage.Replace("%1", "ended support")
#}

# Write-Host "$lastMessage"
write-Host "**********************************************************************************************************"


if ($Help) {
	Write-Host @"

This script supports standard PowerShell "Get-Help". To see usage information, use:

	Get-Help .\flashplayer-checks.ps1
	
or

	Get-Help .\flashplayer-checks.ps1 -full
	
from the PowerShell prompt.
"@
}
else {
	Main
}

Write-Host ""