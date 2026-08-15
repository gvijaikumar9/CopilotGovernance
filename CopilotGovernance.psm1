# Root module. Dot-sources every function in Private/ then Public/, and exports
# only the Public ones. New cmdlets = drop a .ps1 in Public/ and add it to
# FunctionsToExport in the .psd1.

$Private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private\*.ps1') -ErrorAction SilentlyContinue)
$Public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public\*.ps1')  -ErrorAction SilentlyContinue)

foreach ($file in @($Private + $Public)) {
    try {
        . $file.FullName
    }
    catch {
        Write-Error "CopilotGovernance: failed to import $($file.FullName): $_"
    }
}

Export-ModuleMember -Function $Public.BaseName
