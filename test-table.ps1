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
# Display results in a table for ease
#

[System.Data.DataTable]$Data = New-Object System.Data.DataTable
    
#
# Columns
#

[string]$script:col1Name = "Item Name"
[string]$script:col2Name = "Present"
[string]$script:col3Name = "Required Value"
[string]$script:col4Name = "Actual Value"
[string]$script:col5Name = "Notes"

[System.Data.DataColumn]$col1 = New-Object System.Data.DataColumn $script:col1Name,([String])
[System.Data.DataColumn]$col2 = New-Object System.Data.DataColumn $script:col2Name,([String])
[System.Data.DataColumn]$col3 = New-Object System.Data.DataColumn $script:col3Name,([string])
[System.Data.DataColumn]$col4 = New-Object System.Data.DataColumn $script:col4Name,([string])
[System.Data.DataColumn]$col5 = New-Object System.Data.DataColumn $script:col5Name,([string])

$Data.Columns.Add($col1)
$Data.Columns.Add($col2)
$Data.Columns.Add($col3)
$Data.Columns.Add($col4)
$Data.Columns.Add($col5)

[System.Data.DataRow]$myRow = $Data.NewRow()
$myRow.$col1Name = "A"
$myRow.$col2Name = "A1"
$myRow.$col3Name = "A2"
$myRow.$col4Name = "A3"
$myRow.$col5Name = "No"

$Data.Rows.Add($myRow)

[System.Data.DataRow]$myRow = $Data.NewRow()
$myRow.$col1Name = "B"
$myRow.$col2Name = "B1"
$myRow.$col3Name = "B2"
$myRow.$col4Name = "B3"
$myRow.$col5Name = "Yes - Do something"

$Data.Rows.Add($myRow)

$Data | Format-Table | Format-Color @{'\bYes\b' = 'Green';'\bNo\b' = 'Yellow'}

