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

# --- Dispatch + roll-up come in later tasks ---
Write-Host 'Stub — dispatch loop not implemented yet.'
