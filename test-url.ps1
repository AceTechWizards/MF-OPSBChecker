param(
    [parameter(position=0)]
    [string]$URL
)

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

[bool]$isUrl = $false
[string]$new = ""
Check-URL $URL ([ref]$isUrl) ([ref]$new)


if ($isUrl) {
    Write-Host "Yes: $URL, New: $new"
}
else {
    Write-Host "No: $URL"
}