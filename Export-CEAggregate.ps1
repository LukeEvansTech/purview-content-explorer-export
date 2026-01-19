#Requires -Version 7.0
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

$allRecords = New-Object System.Collections.Generic.List[object]

foreach ($workload in $Workloads) {
    Write-Host "  workload=$workload"
    try {
        $pageCookie = $null
        do {
            $params = @{
                TagType   = $TagType
                TagName   = $TagName
                Workload  = $workload
                PageSize  = $PageSize
                Aggregate = $true
            }
            if ($pageCookie) { $params.PageCookie = $pageCookie }

            $response = Export-ContentExplorerData @params

            # Response is an array: index 0 is metadata, indices 1..RecordsReturned are records.
            $meta = $response[0]
            $recordsReturned = [int]$meta.RecordsReturned
            $morePages = [bool]$meta.MorePagesAvailable
            $pageCookie = if ($morePages) { [string]$meta.PageCookie } else { $null }

            if ($recordsReturned -gt 0) {
                foreach ($rec in $response[1..$recordsReturned]) {
                    # Convert PSCustomObject to a hashtable we can extend, then emit a new object
                    # so TagType/TagName/Workload land in the CSV columns.
                    $row = [ordered]@{
                        TagType  = $TagType
                        TagName  = $TagName
                        Workload = $workload
                    }
                    foreach ($prop in $rec.PSObject.Properties) {
                        $row[$prop.Name] = $prop.Value
                    }
                    $allRecords.Add([pscustomobject]$row)
                }
            }
        } while ($morePages)
    }
    catch {
        Write-Warning "    workload=$workload failed: $($_.Exception.Message)"
    }
}

if ($allRecords.Count -gt 0) {
    $allRecords | Export-Csv -Path $outFile -Encoding UTF8 -NoTypeInformation
    Write-Host "wrote $($allRecords.Count) row(s) to $outFile"
} else {
    # Write a header-only file so skip-existing behaves correctly on re-runs of empty tags.
    [pscustomobject]@{ TagType = $TagType; TagName = $TagName; Workload = ''; } |
        Export-Csv -Path $outFile -Encoding UTF8 -NoTypeInformation
    # Trim the placeholder row, keeping only the header.
    (Get-Content $outFile -TotalCount 1) | Set-Content $outFile -Encoding UTF8
    Write-Host "wrote 0 row(s) (empty result) to $outFile"
}
