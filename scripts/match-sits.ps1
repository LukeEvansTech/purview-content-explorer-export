#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
Suggest canonical tenant SIT names for a CSV of SIT names that may use
non-canonical naming (case differences, "Germany" vs "German", "Luxemburg"
vs "Luxembourg", etc.).

.DESCRIPTION
Connects to Security & Compliance PowerShell, dumps the full SIT list,
then for each name in the input CSV tries:
  1. Normalized-exact match (case-insensitive, no punctuation)
  2. Substring containment in either direction
  3. Levenshtein distance (≤ 30% of name length)

Results are printed and exported to /tmp/sit_mappings.csv with a Suggested
column you can review and apply manually.

.EXAMPLE
./match-sits.ps1 -NamesFile ./my-sits.csv
#>
param(
    [Parameter(Mandatory)]
    [string]$NamesFile,
    [string]$NamesColumn = 'Name',
    [string]$OutFile = '/tmp/sit_mappings.csv'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Connect if needed
$connected = $false
try {
    $info = Get-ConnectionInformation -ErrorAction Stop
    if ($info | Where-Object { $_.State -eq 'Connected' -and $_.ConnectionUri -match 'compliance|protection' }) {
        $connected = $true
    }
} catch {}
if (-not $connected) { Connect-IPPSSession -ShowBanner:$false | Out-Null }

# All tenant SIT names
$tenant = @(Get-DlpSensitiveInformationType | Select-Object -ExpandProperty Name)
Write-Host "tenant has $($tenant.Count) SIT(s)"
$tenant | Set-Content /tmp/tenant_sits.txt

function Get-Normalized([string]$s) { ($s -replace '[^A-Za-z0-9]', '').ToLower() }

function Get-LevenshteinDistance([string]$a, [string]$b) {
    $la = $a.Length; $lb = $b.Length
    if ($la -eq 0) { return $lb }
    if ($lb -eq 0) { return $la }
    # Two-row dynamic programming.
    $prev = 0..$lb
    $curr = New-Object 'int[]' ($lb + 1)
    for ($i = 1; $i -le $la; $i++) {
        $curr[0] = $i
        for ($j = 1; $j -le $lb; $j++) {
            $cost = if ($a[$i-1] -eq $b[$j-1]) { 0 } else { 1 }
            $curr[$j] = [Math]::Min(
                [Math]::Min($curr[$j-1] + 1, $prev[$j] + 1),
                $prev[$j-1] + $cost
            )
        }
        $tmp = $prev; $prev = $curr; $curr = $tmp
    }
    return $prev[$lb]
}

# Build normalized -> canonical map
$tenantMap = @{}
foreach ($t in $tenant) { $tenantMap[(Get-Normalized $t)] = $t }

# Read user CSV (handling the '#' header issue same way the orchestrator does)
$rawLines = Get-Content -Path $NamesFile
$headers = $rawLines[0].Split(',') | ForEach-Object { ($_ -replace '^"|"$', '').Trim() }
$rows = $rawLines | Select-Object -Skip 1 | ConvertFrom-Csv -Header $headers

# Match each row's name
$mappings = New-Object System.Collections.Generic.List[object]
foreach ($row in $rows) {
    $name = $row.$NamesColumn
    if (-not $name) { continue }
    $norm = Get-Normalized $name

    if ($tenantMap.ContainsKey($norm)) {
        $canonical = $tenantMap[$norm]
        $type = if ($canonical -eq $name) { 'exact' } else { 'normalized-exact' }
        $mappings.Add([pscustomobject]@{ Source = $name; Suggested = $canonical; Type = $type })
        continue
    }

    # Substring containment fallback
    $candidates = @($tenantMap.GetEnumerator() | Where-Object { $_.Key.Contains($norm) -or $norm.Contains($_.Key) })
    if ($candidates.Count -gt 0) {
        $best = $candidates | Sort-Object { [Math]::Abs($_.Key.Length - $norm.Length) } | Select-Object -First 1
        $mappings.Add([pscustomobject]@{ Source = $name; Suggested = $best.Value; Type = 'substring' })
        continue
    }

    # Levenshtein-distance fallback (works on normalized strings, catches Germany↔German etc.)
    $bestDist = [int]::MaxValue
    $bestMatch = $null
    foreach ($k in $tenantMap.Keys) {
        $d = Get-LevenshteinDistance $norm $k
        if ($d -lt $bestDist) {
            $bestDist = $d
            $bestMatch = $tenantMap[$k]
        }
    }
    # Accept only when the fuzzy match is "close enough" relative to source length.
    # Threshold: distance ≤ 30% of source length (caps at ~6 chars for typical SIT names).
    $threshold = [Math]::Max(3, [int]([Math]::Ceiling($norm.Length * 0.3)))
    if ($bestMatch -and $bestDist -le $threshold) {
        $mappings.Add([pscustomobject]@{ Source = $name; Suggested = $bestMatch; Type = "levenshtein-$bestDist" })
    } else {
        $mappings.Add([pscustomobject]@{ Source = $name; Suggested = '<<NO MATCH>>'; Type = 'none' })
    }
}

# Print only the non-exact matches (those needing changes)
Write-Host "`n=== mappings needing change ==="
$mappings | Where-Object { $_.Type -ne 'exact' } | Format-Table -AutoSize -Wrap
$mappings | Where-Object { $_.Type -ne 'exact' } | Export-Csv $OutFile -NoTypeInformation -Encoding UTF8
Write-Host "exported to $OutFile"
