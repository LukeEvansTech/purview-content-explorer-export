#Requires -Version 7.0
<#
.SYNOPSIS
Sweeps Content Explorer aggregate data across all (or filtered) tags and workloads.

.EXAMPLE
./Invoke-CEAggregateSweep.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [ValidateSet('Retention','SensitiveInformationType','Sensitivity','TrainableClassifier')]
    [string[]]$TagTypes = @('Retention','SensitiveInformationType','Sensitivity','TrainableClassifier'),

    [string[]]$NameLike = @('*'),
    [string[]]$NameNotLike = @(),

    [ValidateSet('EXO','ODB','SPO','Teams')]
    [string[]]$Workloads = @('EXO','ODB','SPO','Teams'),

    [string]$OutDir = (Join-Path $PSScriptRoot 'output'),

    [switch]$Force,

    [ValidateRange(1, 10000)]
    [int]$PageSize = 1000,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib/CEHelpers.psm1') -Force

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

# --- Connection check ---
function Test-CEConnected {
    try {
        # Get-Label is a cheap S&C cmdlet that fails fast when not connected.
        Get-Label -ResultSize 1 -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

if (-not $DryRun) {
    if (-not (Test-CEConnected)) {
        Write-Host 'Not connected to Security & Compliance PowerShell — running Connect-IPPSSession...'
        Connect-IPPSSession | Out-Null
        if (-not (Test-CEConnected)) {
            throw 'Connect-IPPSSession appeared to succeed but Get-Label is still failing. Aborting.'
        }
    }
}

function Get-CETagInventory {
    param(
        [string[]]$TagTypes,
        [string[]]$NameLike,
        [string[]]$NameNotLike
    )
    $inventory = New-Object System.Collections.Generic.List[object]

    foreach ($tt in $TagTypes) {
        $map = Get-CETagTypeEnumeration -TagType $tt
        $cmdlet = $map.Cmdlet
        $nameProp = $map.NameProperty

        if (-not (Get-Command $cmdlet -ErrorAction SilentlyContinue)) {
            Write-Warning "${tt}: cmdlet '$cmdlet' not available in this session. Skipping. (For TrainableClassifier, supply names via -NameLike against a known list, or omit this TagType.)"
            continue
        }

        Write-Host "enumerating $tt via $cmdlet..."
        try {
            $items = & $cmdlet -ErrorAction Stop
        } catch {
            Write-Warning "$tt enumeration failed: $($_.Exception.Message)"
            continue
        }

        foreach ($item in $items) {
            $name = $item.$nameProp
            if (-not $name) { continue }
            if (-not (Test-CETagNameFilter -Name $name -NameLike $NameLike -NameNotLike $NameNotLike)) { continue }
            $inventory.Add([pscustomobject]@{ TagType = $tt; TagName = $name })
        }
    }
    return ,$inventory.ToArray()
}

$inventory = Get-CETagInventory -TagTypes $TagTypes -NameLike $NameLike -NameNotLike $NameNotLike
Write-Host ("found {0} tag(s) after filtering:" -f $inventory.Count)
$inventory | Group-Object TagType | ForEach-Object {
    Write-Host ("  {0}: {1}" -f $_.Name, $_.Count)
}

if ($DryRun) {
    $inventory | Format-Table -AutoSize | Out-String | Write-Host
    return
}

$logFile = Join-Path $OutDir 'sweep.log'
$workerScript = Join-Path $PSScriptRoot 'Export-CEAggregate.ps1'

$counts = @{ processed = 0; succeeded = 0; skipped = 0; failed = 0 }

function Write-SweepLog {
    param([string]$Status, [string]$TagType, [string]$TagName, [string]$Detail)
    $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $line = "{0}  {1,-7} {2,-26} {3,-50} {4}" -f $ts, $Status, $TagType, ('"' + $TagName + '"'), $Detail
    Add-Content -Path $logFile -Value $line
    Write-Host $line
}

foreach ($tag in $inventory) {
    $counts.processed++
    $safeName = Get-CESafeName $tag.TagName
    $expectedFile = Join-Path $OutDir ("aggregate_{0}_{1}.csv" -f $tag.TagType, $safeName)

    if ((Test-Path $expectedFile) -and -not $Force) {
        Write-SweepLog -Status 'skip' -TagType $tag.TagType -TagName $tag.TagName -Detail 'exists'
        $counts.skipped++
        continue
    }

    try {
        & $workerScript `
            -TagType $tag.TagType `
            -TagName $tag.TagName `
            -Workloads $Workloads `
            -OutDir $OutDir `
            -PageSize $PageSize `
            -Force:$Force

        $rowCount = 0
        if (Test-Path $expectedFile) {
            # Subtract 1 for the header row.
            $rowCount = [Math]::Max(0, (Get-Content $expectedFile | Measure-Object -Line).Lines - 1)
        }
        Write-SweepLog -Status 'ok' -TagType $tag.TagType -TagName $tag.TagName -Detail "rows=$rowCount"
        $counts.succeeded++
    }
    catch {
        Write-SweepLog -Status 'fail' -TagType $tag.TagType -TagName $tag.TagName -Detail $_.Exception.Message
        $counts.failed++
    }
}

# --- Roll-up: concatenate all per-tag CSVs into aggregate_all.csv ---
$rollupFile = Join-Path $OutDir 'aggregate_all.csv'
$perTagFiles = Get-ChildItem -Path $OutDir -Filter 'aggregate_*.csv' |
    Where-Object { $_.Name -ne 'aggregate_all.csv' }

if ($perTagFiles.Count -gt 0) {
    Write-Host "rolling up $($perTagFiles.Count) per-tag file(s) into $rollupFile..."
    $rollupRows = foreach ($f in $perTagFiles) {
        Import-Csv -Path $f.FullName
    }
    if ($rollupRows) {
        # Column union: collect every property name across all rows before re-emitting.
        # Without this, Import-Csv | Export-Csv adopts the first object's schema and silently
        # drops columns that exist on later objects — e.g. SPO's SiteUrl when EXO files
        # (which have UserPrincipalName instead) sort first.
        $allColumns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($row in $rollupRows) {
            foreach ($prop in $row.PSObject.Properties) { [void]$allColumns.Add($prop.Name) }
        }
        $rollupRows |
            Select-Object -Property ([string[]]$allColumns) |
            Export-Csv -Path $rollupFile -Encoding UTF8 -NoTypeInformation
    } else {
        # All per-tag files were empty (header-only). Write an empty roll-up.
        Set-Content -Path $rollupFile -Value '' -Encoding UTF8
    }
} else {
    Write-Host 'no per-tag files found; roll-up not generated.'
}

Write-Host ('processed={0} succeeded={1} skipped={2} failed={3}' -f $counts.processed, $counts.succeeded, $counts.skipped, $counts.failed)

if ($counts.failed -gt 0) { exit 1 } else { exit 0 }
