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

# --- Enumeration, filtering, dispatch, roll-up come in later tasks ---
Write-Host "DryRun=$DryRun TagTypes=$($TagTypes -join ',') Workloads=$($Workloads -join ',')"
Write-Host 'Stub — enumeration not implemented yet.'
