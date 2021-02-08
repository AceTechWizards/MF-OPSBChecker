function script:DoStuff([string[]]$config) {

    foreach ($line in $config) {
        Write-Host "Next Line: $line"
    }

}


[string[]]$config = Get-Content -Path "C:\WINDOWS\SysWow64\Macromed\Flash\mms.cfg"

foreach ($line in $config) {
    Write-Host "Line: $line"
}


DoStuff $config