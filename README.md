# tbcontentexplorer

PowerShell tool for exporting Microsoft Purview Content Explorer item-level data
across all tags and workloads. One row per file/email — file paths, names,
creators, sizes, etc.

## Prerequisites

- PowerShell 7+ (scripts declare `#Requires -Version 7.0` — they rely on member-access enumeration on pipelines, which doesn't work in PS 5.1).
- ExchangeOnlineManagement module: `Install-Module ExchangeOnlineManagement -Scope CurrentUser`
- Pester 5+ (only for offline unit tests): `Install-Module Pester -Scope CurrentUser -SkipPublisherCheck`
- Account with the **Content Explorer List Viewer** role group in Microsoft Purview.

## Quick start

```powershell
# 1. Connect interactively (one-time per session, ~1h token life).
Connect-IPPSSession

# 2. Dry-run to see the planned (TagType, TagName) list without exporting.
./Invoke-CESweep.ps1 -DryRun

# 3. Full SIT sweep — defaults to all SensitiveInformationTypes across all four workloads.
./Invoke-CESweep.ps1
```

## Common scenarios

```powershell
# Default is SensitiveInformationType only. Add more tag types explicitly:
./Invoke-CESweep.ps1 -TagTypes SensitiveInformationType,Sensitivity,Retention

# Narrow to one tag-name pattern.
./Invoke-CESweep.ps1 -NameLike 'Credit*'

# Sensitivity-label-only sweep.
./Invoke-CESweep.ps1 -TagTypes Sensitivity

# Re-run only failed/missing tags (default behaviour — skip-existing is on).
./Invoke-CESweep.ps1

# Force a complete re-export, overwriting existing CSVs.
./Invoke-CESweep.ps1 -Force

# Run the worker by hand for a single tag.
./Export-CEItems.ps1 -TagType SensitiveInformationType -TagName 'Credit Card Number'
```

## Output

- `output/items_<TagType>_<safe-name>.csv` — one per `(TagType, TagName)`.
  Columns include `TagType`, `TagName`, `Workload`, plus the file/email-level
  fields returned by `Export-ContentExplorerData` (file URL, name, sender,
  recipients, creator, modifier, size, etc. — schema varies by workload).
- `output/items_all.csv` — concatenation of all per-tag files (column-unioned
  so the SPO/ODB and EXO/Teams schemas coexist); the file you load into
  Excel / Power BI for analysis.
- `output/sweep.log` — append-only per-tag status log.

## Recovery

If a run is interrupted (Ctrl+C, session-token expiry, network blip), just re-run:

```powershell
./Invoke-CESweep.ps1
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

`docs/superpowers/specs/2026-04-30-content-explorer-aggregate-sweep-design.md` (original aggregate-mode design — superseded; see git history for the pivot to detail-mode).
