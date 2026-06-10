#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$privateFunctions = @(Get-ChildItem -Path "$PSScriptRoot/Private" -Filter '*.ps1' -ErrorAction SilentlyContinue)
$publicFunctions  = @(Get-ChildItem -Path "$PSScriptRoot/Public"  -Filter '*.ps1' -ErrorAction SilentlyContinue)
foreach ($file in ($privateFunctions + $publicFunctions)) {
    . $file.FullName
}

# Export exactly the Public/ functions; the psd1 FunctionsToExport stays the explicit
# allowlist for Gallery metadata, this derives the psm1 side from the files just loaded.
$exportNames = @(foreach ($file in $publicFunctions) { $file.BaseName })
Export-ModuleMember -Function $exportNames
