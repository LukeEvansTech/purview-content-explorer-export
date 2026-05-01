# Content Explorer Aggregate Sweep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a two-script PowerShell tool (worker + orchestrator) that produces a tenant-wide aggregate inventory from Microsoft Purview Content Explorer via `Export-ContentExplorerData -Aggregate`.

**Architecture:** `Export-CEAggregate.ps1` handles one `(TagType, TagName)` across one or more workloads with pagination and writes a per-tag CSV. `Invoke-CEAggregateSweep.ps1` connects to S&C PowerShell, enumerates tags via the matching `Get-*` cmdlets, applies include/exclude filters, dispatches to the worker, and produces a merged roll-up CSV.

**Tech Stack:** PowerShell 7+ (works on 5.1 if available), Exchange Online Management module (`Connect-IPPSSession`), Pester 5+ for offline unit tests. Manual smoke tests against a real tenant per spec §Testing Approach.

**Spec:** `docs/superpowers/specs/2026-04-30-content-explorer-aggregate-sweep-design.md`

---

## File Structure

```
tbcontentexplorer/
  Export-CEAggregate.ps1            # worker
  Invoke-CEAggregateSweep.ps1       # orchestrator
  lib/
    CEHelpers.psm1                  # pure helpers (safe-name, filters, enumeration map)
  tests/
    CEHelpers.Tests.ps1             # Pester tests for pure helpers
  output/                           # gitignored, created at runtime
  README.md
  .gitignore
```

`CEHelpers.psm1` exists so the pure-logic functions are dot-sourced into both scripts and into Pester. Cmdlet-calling code stays in the two top-level scripts and is tested manually per spec.

---

### Task 1: Repo scaffolding

**Files:**
- Create: `.gitignore`
- Create: `README.md`
- Create: `lib/CEHelpers.psm1` (empty module shell)
- Create: `tests/CEHelpers.Tests.ps1` (empty test shell)

- [ ] **Step 1: Create `.gitignore`**

```
output/
*.log
.vscode/
```

- [ ] **Step 2: Create `README.md` skeleton**

```markdown
# tbcontentexplorer

PowerShell tool for sweeping Microsoft Purview Content Explorer aggregate data
across all tags and workloads.

## Quick start

```powershell
# Connect interactively (one-time per session)
Connect-IPPSSession

# Dry-run to see what would be swept
./Invoke-CEAggregateSweep.ps1 -DryRun

# Full sweep with defaults
./Invoke-CEAggregateSweep.ps1

# Narrow to one tag type
./Invoke-CEAggregateSweep.ps1 -TagTypes SensitiveInformationType -NameLike 'Credit*'
```

See `docs/superpowers/specs/` for the design.
```

- [ ] **Step 3: Create empty module file `lib/CEHelpers.psm1`**

```powershell
# CEHelpers.psm1 — pure helper functions for Content Explorer sweep scripts.
# Cmdlet-calling logic lives in the top-level scripts; this module is offline-testable.
```

- [ ] **Step 4: Create empty test file `tests/CEHelpers.Tests.ps1`**

```powershell
# Run with: Invoke-Pester ./tests/CEHelpers.Tests.ps1
BeforeAll {
    Import-Module "$PSScriptRoot/../lib/CEHelpers.psm1" -Force
}
```

- [ ] **Step 5: Verify Pester runs (empty pass)**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/CEHelpers.Tests.ps1 -CI"`
Expected: `Tests Passed: 0` (no failures, exit 0)

If Pester is missing, install with: `Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck`

- [ ] **Step 6: Commit**

```bash
git init
git add .gitignore README.md lib/CEHelpers.psm1 tests/CEHelpers.Tests.ps1
git commit -m "chore: scaffold tbcontentexplorer repo"
```

---

### Task 2: Safe-name helper

**Files:**
- Modify: `tests/CEHelpers.Tests.ps1`
- Modify: `lib/CEHelpers.psm1`

- [ ] **Step 1: Write the failing tests**

Append to `tests/CEHelpers.Tests.ps1`:

```powershell
Describe 'Get-CESafeName' {
    It 'leaves alphanumeric, dot, underscore, hyphen unchanged' {
        Get-CESafeName 'Credit-Card_v2.0' | Should -Be 'Credit-Card_v2.0'
    }
    It 'replaces spaces with underscores' {
        Get-CESafeName 'Credit Card Number' | Should -Be 'Credit_Card_Number'
    }
    It 'replaces forward slash with underscore' {
        Get-CESafeName 'Credit/Debit Card' | Should -Be 'Credit_Debit_Card'
    }
    It 'replaces multiple unsafe chars individually (no collapsing)' {
        Get-CESafeName 'A  B' | Should -Be 'A__B'
    }
    It 'handles unicode by replacing with underscore' {
        Get-CESafeName 'Café' | Should -Be 'Caf_'
    }
    It 'returns empty string for empty input' {
        Get-CESafeName '' | Should -Be ''
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/CEHelpers.Tests.ps1 -CI"`
Expected: 6 failures, all "The term 'Get-CESafeName' is not recognized"

- [ ] **Step 3: Implement `Get-CESafeName`**

Append to `lib/CEHelpers.psm1`:

```powershell
function Get-CESafeName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [AllowEmptyString()]
        [string]$Name
    )
    return [regex]::Replace($Name, '[^A-Za-z0-9._-]', '_')
}

Export-ModuleMember -Function Get-CESafeName
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/CEHelpers.Tests.ps1 -CI"`
Expected: `Tests Passed: 6`

- [ ] **Step 5: Commit**

```bash
git add lib/CEHelpers.psm1 tests/CEHelpers.Tests.ps1
git commit -m "feat: add Get-CESafeName helper for filename normalization"
```

---

### Task 3: Tag name filter helper

**Files:**
- Modify: `tests/CEHelpers.Tests.ps1`
- Modify: `lib/CEHelpers.psm1`

- [ ] **Step 1: Write the failing tests**

Append to `tests/CEHelpers.Tests.ps1`:

```powershell
Describe 'Test-CETagNameFilter' {
    It 'returns true when NameLike matches and NameNotLike empty' {
        Test-CETagNameFilter -Name 'Credit Card' -NameLike @('Credit*') -NameNotLike @() | Should -BeTrue
    }
    It 'returns false when no NameLike pattern matches' {
        Test-CETagNameFilter -Name 'Credit Card' -NameLike @('SSN*') -NameNotLike @() | Should -BeFalse
    }
    It 'returns false when any NameNotLike pattern matches' {
        Test-CETagNameFilter -Name 'Credit Card' -NameLike @('*') -NameNotLike @('Credit*') | Should -BeFalse
    }
    It 'matches when ANY NameLike pattern matches (OR semantics)' {
        Test-CETagNameFilter -Name 'SSN' -NameLike @('Credit*','SSN*') -NameNotLike @() | Should -BeTrue
    }
    It 'is case-insensitive for include' {
        Test-CETagNameFilter -Name 'CREDIT CARD' -NameLike @('credit*') -NameNotLike @() | Should -BeTrue
    }
    It 'is case-insensitive for exclude' {
        Test-CETagNameFilter -Name 'credit card' -NameLike @('*') -NameNotLike @('CREDIT*') | Should -BeFalse
    }
    It 'defaults to match-all when NameLike is empty array' {
        Test-CETagNameFilter -Name 'anything' -NameLike @() -NameNotLike @() | Should -BeTrue
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/CEHelpers.Tests.ps1 -CI"`
Expected: 7 new failures for `Test-CETagNameFilter`.

- [ ] **Step 3: Implement `Test-CETagNameFilter`**

Append to `lib/CEHelpers.psm1` (before `Export-ModuleMember`, then update the export):

```powershell
function Test-CETagNameFilter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$NameLike,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$NameNotLike
    )
    $included = ($NameLike.Count -eq 0) -or ($NameLike | Where-Object { $Name -like $_ }).Count -gt 0
    if (-not $included) { return $false }
    $excluded = ($NameNotLike | Where-Object { $Name -like $_ }).Count -gt 0
    return -not $excluded
}
```

Replace the `Export-ModuleMember` line with:

```powershell
Export-ModuleMember -Function Get-CESafeName, Test-CETagNameFilter
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/CEHelpers.Tests.ps1 -CI"`
Expected: `Tests Passed: 13`

- [ ] **Step 5: Commit**

```bash
git add lib/CEHelpers.psm1 tests/CEHelpers.Tests.ps1
git commit -m "feat: add Test-CETagNameFilter for include/exclude wildcard logic"
```

---

### Task 4: Tag-type enumeration map

**Files:**
- Modify: `tests/CEHelpers.Tests.ps1`
- Modify: `lib/CEHelpers.psm1`

- [ ] **Step 1: Write the failing tests**

Append to `tests/CEHelpers.Tests.ps1`:

```powershell
Describe 'Get-CETagTypeEnumeration' {
    It 'returns SensitiveInformationType mapping' {
        $m = Get-CETagTypeEnumeration -TagType SensitiveInformationType
        $m.Cmdlet | Should -Be 'Get-DlpSensitiveInformationType'
        $m.NameProperty | Should -Be 'Name'
    }
    It 'returns Sensitivity mapping' {
        $m = Get-CETagTypeEnumeration -TagType Sensitivity
        $m.Cmdlet | Should -Be 'Get-Label'
        $m.NameProperty | Should -Be 'DisplayName'
    }
    It 'returns Retention mapping' {
        $m = Get-CETagTypeEnumeration -TagType Retention
        $m.Cmdlet | Should -Be 'Get-ComplianceTag'
        $m.NameProperty | Should -Be 'Name'
    }
    It 'returns TrainableClassifier mapping' {
        $m = Get-CETagTypeEnumeration -TagType TrainableClassifier
        $m.Cmdlet | Should -Be 'Get-DlpTrainableClassifier'
        $m.NameProperty | Should -Be 'Name'
    }
    It 'throws on unknown TagType' {
        { Get-CETagTypeEnumeration -TagType 'Bogus' } | Should -Throw
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/CEHelpers.Tests.ps1 -CI"`
Expected: 5 new failures.

- [ ] **Step 3: Implement `Get-CETagTypeEnumeration`**

Append to `lib/CEHelpers.psm1` (before `Export-ModuleMember`):

```powershell
function Get-CETagTypeEnumeration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Retention','SensitiveInformationType','Sensitivity','TrainableClassifier')]
        [string]$TagType
    )
    switch ($TagType) {
        'SensitiveInformationType' { @{ Cmdlet = 'Get-DlpSensitiveInformationType'; NameProperty = 'Name' } }
        'Sensitivity'              { @{ Cmdlet = 'Get-Label';                       NameProperty = 'DisplayName' } }
        'Retention'                { @{ Cmdlet = 'Get-ComplianceTag';               NameProperty = 'Name' } }
        'TrainableClassifier'      { @{ Cmdlet = 'Get-DlpTrainableClassifier';      NameProperty = 'Name' } }
    }
}
```

Update the export line:

```powershell
Export-ModuleMember -Function Get-CESafeName, Test-CETagNameFilter, Get-CETagTypeEnumeration
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/CEHelpers.Tests.ps1 -CI"`
Expected: `Tests Passed: 18`

- [ ] **Step 5: Commit**

```bash
git add lib/CEHelpers.psm1 tests/CEHelpers.Tests.ps1
git commit -m "feat: add Get-CETagTypeEnumeration mapping for tag-type cmdlets"
```

---

### Task 5: Worker — parameter block + skip-existing short-circuit

**Files:**
- Create: `Export-CEAggregate.ps1`

- [ ] **Step 1: Create the worker with param block, skip-existing logic, and a stub call**

```powershell
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
```

- [ ] **Step 2: Verify the param block parses (manual)**

Run: `pwsh -NoProfile -File ./Export-CEAggregate.ps1 -TagType SensitiveInformationType -TagName 'Credit Card'`
Expected: throws "Not implemented yet — Task 6 wires up the export call."

- [ ] **Step 3: Verify skip-existing short-circuits before the throw**

Run:
```powershell
mkdir -p output
echo "stub" > output/aggregate_SensitiveInformationType_Credit_Card.csv
pwsh -NoProfile -File ./Export-CEAggregate.ps1 -TagType SensitiveInformationType -TagName 'Credit Card'
```
Expected: prints `skip (exists): .../aggregate_SensitiveInformationType_Credit_Card.csv` and exits 0.

Cleanup: `rm output/aggregate_SensitiveInformationType_Credit_Card.csv`

- [ ] **Step 4: Commit**

```bash
git add Export-CEAggregate.ps1
git commit -m "feat: scaffold worker script with skip-existing short-circuit"
```

---

### Task 6: Worker — single-workload pagination loop

**Files:**
- Modify: `Export-CEAggregate.ps1`

- [ ] **Step 1: Replace the `throw` line with a per-workload pagination loop**

Replace the line `throw "Not implemented yet — Task 6 wires up the export call."` with:

```powershell
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
```

- [ ] **Step 2: Manual smoke test against the tenant**

Pre-req: run `Connect-IPPSSession` in the same PowerShell session you'll use to invoke the worker.

Run: `./Export-CEAggregate.ps1 -TagType SensitiveInformationType -TagName 'Credit Card Number' -Workloads EXO -PageSize 1000 -Force`

Expected:
- Prints `  workload=EXO`
- Prints `wrote N row(s) to .../aggregate_SensitiveInformationType_Credit_Card_Number.csv` (N may be 0)
- File exists with at minimum a header row containing `TagType,TagName,Workload,...`

If you don't have access to a tenant right now, mark this step as deferred and continue — the orchestrator's `-DryRun` path can be exercised without a tenant. Wire up a tenant smoke run before merging.

- [ ] **Step 3: Commit**

```bash
git add Export-CEAggregate.ps1
git commit -m "feat: implement worker pagination loop with TagType/TagName/Workload columns"
```

---

### Task 7: Worker — multi-workload exercise

**Files:** none changed (verification task)

- [ ] **Step 1: Manual smoke test across all four workloads**

Pre-req: `Connect-IPPSSession` in the current session.

Run: `./Export-CEAggregate.ps1 -TagType SensitiveInformationType -TagName 'Credit Card Number' -Force`

Expected:
- Prints `  workload=EXO`, `  workload=ODB`, `  workload=SPO`, `  workload=Teams` in order.
- Final CSV has rows tagged with each workload value (or zero rows if the tenant has no matches — that's OK).
- Per-workload errors print as `WARNING:` and do not stop the others.

- [ ] **Step 2: Sanity-check skip-existing on re-run**

Run the same command again **without** `-Force`. Expected: `skip (exists): ...` and the file is not modified (`Get-FileHash` unchanged).

- [ ] **Step 3: No code commit** — verification only.

---

### Task 8: Orchestrator — parameter block, connection check, DryRun stub

**Files:**
- Create: `Invoke-CEAggregateSweep.ps1`

- [ ] **Step 1: Create the orchestrator with param block, connection check, and DryRun stub**

```powershell
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
```

- [ ] **Step 2: Verify DryRun path runs offline**

Run: `pwsh -NoProfile -File ./Invoke-CEAggregateSweep.ps1 -DryRun`
Expected: prints the `DryRun=True ...` line and the stub message; exit 0.

- [ ] **Step 3: Verify non-DryRun connection check**

Run (without an active S&C session): `pwsh -NoProfile -File ./Invoke-CEAggregateSweep.ps1`
Expected: prints `Not connected to Security & Compliance PowerShell — running Connect-IPPSSession...`. (Cancel the auth prompt if you don't want to actually connect.)

- [ ] **Step 4: Commit**

```bash
git add Invoke-CEAggregateSweep.ps1
git commit -m "feat: scaffold orchestrator with connection check and DryRun stub"
```

---

### Task 9: Orchestrator — tag enumeration

**Files:**
- Modify: `Invoke-CEAggregateSweep.ps1`

- [ ] **Step 1: Replace the stub block with real enumeration**

Replace the last 2 lines of `Invoke-CEAggregateSweep.ps1` (the two `Write-Host` calls under `--- Enumeration, filtering, dispatch, roll-up ...`) with:

```powershell
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
            Write-Warning "$tt: cmdlet '$cmdlet' not available in this session. Skipping. (For TrainableClassifier, supply names via -NameLike against a known list, or omit this TagType.)"
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
```

- [ ] **Step 2: Manual test (DryRun, against tenant)**

Pre-req: `Connect-IPPSSession`.

Run: `./Invoke-CEAggregateSweep.ps1 -TagTypes SensitiveInformationType -NameLike 'Credit*' -DryRun`

Expected:
- Prints `enumerating SensitiveInformationType via Get-DlpSensitiveInformationType...`
- Prints `found N tag(s)` with at least one row.
- Prints a table of the matched `(TagType, TagName)` rows.

- [ ] **Step 3: Manual test — TrainableClassifier missing-cmdlet path**

Run: `./Invoke-CEAggregateSweep.ps1 -TagTypes TrainableClassifier -DryRun`

Expected: either it enumerates successfully (cmdlet exists in this tenant) **or** prints the explicit warning about supplying names via `-NameLike` and skips the TagType. No hard error.

- [ ] **Step 4: Commit**

```bash
git add Invoke-CEAggregateSweep.ps1
git commit -m "feat: enumerate tags via per-TagType cmdlet with filters and missing-cmdlet fallback"
```

---

### Task 10: Orchestrator — dispatch loop with sweep.log

**Files:**
- Modify: `Invoke-CEAggregateSweep.ps1`

- [ ] **Step 1: Replace the dispatch stub with a real loop**

Replace `Write-Host 'Stub — dispatch loop not implemented yet.'` with:

```powershell
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

# --- Roll-up + final summary come in Task 11 ---
Write-Host ('processed={0} succeeded={1} skipped={2} failed={3}' -f $counts.processed, $counts.succeeded, $counts.skipped, $counts.failed)
```

- [ ] **Step 2: Manual narrow-sweep test**

Pre-req: `Connect-IPPSSession`.

Run: `./Invoke-CEAggregateSweep.ps1 -TagTypes SensitiveInformationType -NameLike 'Credit*' -Force`

Expected:
- One log line per matched tag: `<ts>  ok      SensitiveInformationType   "Credit Card Number"   rows=N`
- `output/sweep.log` contains those same lines.
- `processed=X succeeded=X skipped=0 failed=0` summary.

- [ ] **Step 3: Manual resumability test**

Run the same command **without** `-Force`. Expected: every line is `skip` with detail `exists`; `succeeded=0 skipped=X`.

- [ ] **Step 4: Commit**

```bash
git add Invoke-CEAggregateSweep.ps1
git commit -m "feat: dispatch worker per tag and append per-tag status to sweep.log"
```

---

### Task 11: Orchestrator — roll-up + final exit code

**Files:**
- Modify: `Invoke-CEAggregateSweep.ps1`

- [ ] **Step 1: Replace the final summary line with roll-up + exit code**

Replace the last `Write-Host 'processed=...'` line with:

```powershell
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
        $rollupRows | Export-Csv -Path $rollupFile -Encoding UTF8 -NoTypeInformation
    } else {
        # All per-tag files were empty (header-only). Write an empty roll-up.
        Set-Content -Path $rollupFile -Value '' -Encoding UTF8
    }
} else {
    Write-Host 'no per-tag files found; roll-up not generated.'
}

Write-Host ('processed={0} succeeded={1} skipped={2} failed={3}' -f $counts.processed, $counts.succeeded, $counts.skipped, $counts.failed)

if ($counts.failed -gt 0) { exit 1 } else { exit 0 }
```

- [ ] **Step 2: Manual test — narrow sweep produces roll-up**

Pre-req: `Connect-IPPSSession`.

Run: `./Invoke-CEAggregateSweep.ps1 -TagTypes SensitiveInformationType -NameLike 'Credit*' -Force; echo "exit=$LASTEXITCODE"`

Expected:
- `rolling up N per-tag file(s)...` line.
- `output/aggregate_all.csv` exists.
- It contains the union of rows from `output/aggregate_SensitiveInformationType_*.csv` (verify with `Import-Csv ./output/aggregate_all.csv | Group-Object TagName | ForEach-Object { "{0,-40} {1}" -f $_.Name, $_.Count }`).
- `exit=0`.

- [ ] **Step 3: Manual test — failure path exits 1**

Force a failure (e.g. specify a TagName that doesn't exist by passing it via direct worker call **inside** a sweep) — easiest path: pass `-NameLike 'Nonexistent_Tag_XYZZY'` and verify behaviour. If filtering produces zero tags, `processed=0 failed=0` and exit=0 (correct). To exercise the fail path, you can temporarily edit one per-tag file to be unreadable, then re-run with `-Force` — the worker write step will fail.

This step is best-effort. If the failure path can't be easily exercised in the tenant, mark deferred.

- [ ] **Step 4: Commit**

```bash
git add Invoke-CEAggregateSweep.ps1
git commit -m "feat: roll up per-tag CSVs into aggregate_all.csv and set exit code"
```

---

### Task 12: README usage docs

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Expand the README with concrete usage**

Replace `README.md` with:

```markdown
# tbcontentexplorer

PowerShell tool for sweeping Microsoft Purview Content Explorer aggregate data
across all tags and workloads.

## Prerequisites

- PowerShell 7+ (5.1 should also work).
- ExchangeOnlineManagement module: `Install-Module ExchangeOnlineManagement -Scope CurrentUser`
- Pester 5+ (only for offline unit tests): `Install-Module Pester -Scope CurrentUser -SkipPublisherCheck`
- Account with the **Content Explorer List Viewer** role group in Microsoft Purview.

## Quick start

```powershell
# 1. Connect interactively (one-time per session, ~1h token life).
Connect-IPPSSession

# 2. Dry-run to see the planned (TagType, TagName) list without exporting.
./Invoke-CEAggregateSweep.ps1 -DryRun

# 3. Full sweep — defaults to all four TagTypes and all four workloads.
./Invoke-CEAggregateSweep.ps1
```

## Common scenarios

```powershell
# Sweep just Sensitive Information Types whose name starts with "Credit".
./Invoke-CEAggregateSweep.ps1 -TagTypes SensitiveInformationType -NameLike 'Credit*'

# Sweep everything except built-in default Sensitivity labels.
./Invoke-CEAggregateSweep.ps1 -NameNotLike 'Default *','General','Public'

# Re-run only failed/missing tags (default behaviour — skip-existing is on).
./Invoke-CEAggregateSweep.ps1

# Force a complete re-export, overwriting existing CSVs.
./Invoke-CEAggregateSweep.ps1 -Force

# Run the worker by hand for a single tag.
./Export-CEAggregate.ps1 -TagType SensitiveInformationType -TagName 'Credit Card Number'
```

## Output

- `output/aggregate_<TagType>_<safe-name>.csv` — one per `(TagType, TagName)`.
  Columns include `TagType`, `TagName`, `Workload`, plus the folder/site/UPN
  identifier and item count returned by `Export-ContentExplorerData -Aggregate`.
- `output/aggregate_all.csv` — concatenation of all per-tag files; the file you
  load into Excel / Power BI for analysis.
- `output/sweep.log` — append-only per-tag status log.

## Recovery

If a run is interrupted (Ctrl+C, session-token expiry, network blip), just re-run:

```powershell
./Invoke-CEAggregateSweep.ps1
```

Tags whose per-tag CSV already exists are skipped, so the sweep picks up where
it left off. Use `-Force` to re-export from scratch.

## Tests

```powershell
Invoke-Pester ./tests/CEHelpers.Tests.ps1 -CI
```

Only pure-logic helpers (`Get-CESafeName`, `Test-CETagNameFilter`,
`Get-CETagTypeEnumeration`) are unit-tested. Cmdlet integration is covered by
the manual smoke checklist in the spec.

## Spec

`docs/superpowers/specs/2026-04-30-content-explorer-aggregate-sweep-design.md`
```

- [ ] **Step 2: Verify the README renders sensibly**

Run: `cat README.md`
Expected: looks right; no leftover `<...>` placeholders.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: expand README with usage, recovery, and output layout"
```

---

### Task 13: Final smoke checklist (manual)

**Files:** none (verification gate).

This task is the manual checklist from spec §Testing Approach. Run sequentially.

- [ ] **Step 1: Pester unit tests green**

Run: `pwsh -NoProfile -Command "Invoke-Pester ./tests/CEHelpers.Tests.ps1 -CI"`
Expected: all 18 tests pass; exit 0.

- [ ] **Step 2: DryRun smoke against tenant**

Pre-req: `Connect-IPPSSession`.
Run: `./Invoke-CEAggregateSweep.ps1 -DryRun`
Expected: enumerates all four TagTypes (or warns about TrainableClassifier and skips), prints a table of tag counts, exits 0.

- [ ] **Step 3: Single-tag worker smoke**

Run: `./Export-CEAggregate.ps1 -TagType SensitiveInformationType -TagName 'Credit Card Number' -Workloads EXO -Force`
Expected: writes `output/aggregate_SensitiveInformationType_Credit_Card_Number.csv` with `TagType,TagName,Workload,...` header.

- [ ] **Step 4: Narrow sweep**

Run: `./Invoke-CEAggregateSweep.ps1 -TagTypes SensitiveInformationType -NameLike 'Credit*' -Force`
Expected: per-tag CSVs + `aggregate_all.csv` + `sweep.log`; `failed=0`; exit 0.

- [ ] **Step 5: Resumability**

Run the previous command again **without** `-Force`. Expected: every status line is `skip`; existing CSV mtimes unchanged.

- [ ] **Step 6: Full sweep**

Run: `./Invoke-CEAggregateSweep.ps1`
Expected: completes in reasonable time (aggregate mode is fast); roll-up file present; `failed=0`. If the session token expires mid-flight, some tags will fail — re-running picks up only the missing ones.

- [ ] **Step 7: No commit** — verification only. If any step fails, file a follow-up task and address before declaring complete.
