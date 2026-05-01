#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
Exports Microsoft Purview Content Explorer item-level data for one (TagType, TagName) across one or more workloads.

Returns one row per item — file/email-level detail with paths, names, creators, etc.

.EXAMPLE
./Export-CEItems.ps1 -TagType SensitiveInformationType -TagName 'Credit Card Number'
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
$outFile = Join-Path $OutDir ("items_{0}_{1}.csv" -f $TagType, $safeName)

if ((Test-Path $outFile) -and -not $Force) {
    Write-Host "skip (exists): $outFile"
    return
}

$allRecords = New-Object System.Collections.Generic.List[object]
$workloadsAttempted = 0
$workloadsErrored = 0

foreach ($workload in $Workloads) {
    $workloadsAttempted++
    Write-Host "  workload=$workload"
    try {
        $pageCookie = $null
        do {
            $params = @{
                TagType     = $TagType
                TagName     = $TagName
                Workload    = $workload
                PageSize    = $PageSize
                ErrorAction = 'Stop'
            }
            if ($pageCookie) { $params.PageCookie = $pageCookie }

            $response = Export-ContentExplorerData @params

            # Defensive: if the cmdlet emits Write-Error but doesn't terminate (we've seen
            # this with "A server side error has occurred"), $response may be $null. Surface
            # a clearer message than "Cannot index into a null array" via the catch below.
            if ($null -eq $response -or @($response).Count -eq 0) {
                throw 'Export-ContentExplorerData returned no response (likely a server-side error the cmdlet did not throw).'
            }

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
        $workloadsErrored++
        Write-Warning "    workload=$workload failed: $($_.Exception.Message)"
    }
}

# If every attempted workload errored, surface this as a failure so the orchestrator marks
# the tag as failed rather than reporting a misleading "succeeded with 0 rows".
if ($workloadsAttempted -gt 0 -and $workloadsErrored -eq $workloadsAttempted) {
    throw "all $workloadsAttempted workload(s) errored — see warnings above"
}

$partialNote = if ($workloadsErrored -gt 0) { " ($workloadsErrored of $workloadsAttempted workload(s) errored)" } else { '' }

if ($allRecords.Count -gt 0) {
    $allRecords | Export-Csv -Path $outFile -Encoding UTF8 -NoTypeInformation
    Write-Host "wrote $($allRecords.Count) row(s)$partialNote to $outFile"
} else {
    # Write a header-only file so skip-existing behaves correctly on re-runs of empty tags.
    [pscustomobject]@{ TagType = $TagType; TagName = $TagName; Workload = ''; } |
        Export-Csv -Path $outFile -Encoding UTF8 -NoTypeInformation
    # Trim the placeholder row, keeping only the header.
    (Get-Content $outFile -TotalCount 1) | Set-Content $outFile -Encoding UTF8
    Write-Host "wrote 0 row(s) (empty result)$partialNote to $outFile"
}
