<#
.SYNOPSIS
Exports Microsoft Purview Content Explorer aggregate data for one (TagType, TagName) across one or more workloads.

.EXAMPLE
./Export-CEAggregate.ps1 -TagType SensitiveInformationType -TagName 'Credit Card Number'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Retention','SensitiveInformationType','Sensitivity','TrainableClassifier')]
    [string]$TagType,

    [Parameter(Mandatory)]
    [string]$TagName,

    [ValidateSet('EXO','ODB','SPO','Teams')]
    [string[]]$Workloads = @('EXO','ODB','SPO','Teams'),

    [string]$OutDir = (Join-Path $PSScriptRoot 'output'),

    [switch]$Force,

    [ValidateRange(1, 10000)]
    [int]$PageSize = 1000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib/CEHelpers.psm1') -Force

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

$safeName = Get-CESafeName $TagName
$outFile = Join-Path $OutDir ("aggregate_{0}_{1}.csv" -f $TagType, $safeName)

if ((Test-Path $outFile) -and -not $Force) {
    Write-Host "skip (exists): $outFile"
    return
}

# Pagination + per-workload loop comes in Task 6.
throw "Not implemented yet — Task 6 wires up the export call."
