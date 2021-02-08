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

            Write-Host "$browserName V$browserVersion"
        }

}