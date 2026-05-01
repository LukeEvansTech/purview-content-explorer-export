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
