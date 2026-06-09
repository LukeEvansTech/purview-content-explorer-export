#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$publicFunctions = Get-ChildItem -Path "$PSScriptRoot/Public" -Filter '*.ps1' -ErrorAction SilentlyContinue
foreach ($file in $publicFunctions) {
    . $file.FullName
}

Export-ModuleMember -Function @(
    'Find-UnlabeledPII',
    'Get-LabelCoverageByWorkload',
    'Compare-ExportDelta'
)
