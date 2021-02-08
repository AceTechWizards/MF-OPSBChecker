function script:AddRow([string]$Browser, [string]$Installed, [string]$Version) {
        [System.Data.DataRow]$myRow = $Script:Data.NewRow();
        $myRow.Browser = $Browser
        $myRow.Installed = $Installed
        $myRow.Version = $Version

        $Script:Data.Rows.Add($myRow)
}

#
# Table for results
#

[System.Data.DataTable]$Script:Data = New-Object System.Data.DataTable;
    
#
# Columns
#

[System.Data.DataColumn]$col1 = New-Object System.Data.DataColumn "Browser",([String]);
[System.Data.DataColumn]$col2 = New-Object System.Data.DataColumn "Installed",([String]);
[System.Data.DataColumn]$col3 = New-Object System.Data.DataColumn "Version",([string]);

$Script:Data.Columns.Add($col1);
$Script:Data.Columns.Add($col2);
$Script:Data.Columns.Add($col3);
    
$browsers = (Get-ItemProperty -Path HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | where {$_.DisplayName -like "Mozilla Firefox*" -or $_.DisplayName -like "Google Chrome*"})

foreach($item in $browsers) {
    [string]$browserName = $item.DisplayName
    [string]$browserVersion = $item.DisplayVersion
    [string]$browserLocation = $item.InstallLocation
    
    AddRow $browserName "Yes" $browserVersion

    Write-Host ""
    Write-Host "$browserName is installed - Version: $browserVersion"

    if ($browserLocation.Length -gt 0) {
        Write-Host "`tInstall Path: $browserLocation"
    }
}

$ie = Get-Item -Path "HKLM:\Software\Microsoft\Internet Explorer" -ErrorAction SilentlyContinue

if ($ie -ne $null) {
    [string]$ieVersion = Get-ItemPropertyValue -Path "HKLM:\Software\Microsoft\Internet Explorer" -Name svcVersion -ErrorAction SilentlyContinue

    if ($ieVersion -eq $null) {
        $ieVersion = Get-ItemPropertyValue -Path "HKLM:\Software\Microsoft\Internet Explorer" -Name Version -ErrorAction SilentlyContinue
    }

    Write-Host "Internet Explorer is installed - Version: $ieVersion"
    AddRow "Internet Explorer" "Yes" $ieVersion
}
else {
    AddRow "Internet Explorer" "No" "N/A"
}

[string]$edgeVersion = (Get-AppxPackage -ErrorAction SilentlyContinue Microsoft.MicrosoftEdge).Version

if ($edgeVersion -ne $null) {
    Write-Host "Edge is installed - Version: $edgeVersion"
    AddRow "Edge" "Yes" $edgeVersion
}
else {
    AddRow "Edge" "No" "N/A"
}

$script:Data | Format-Table