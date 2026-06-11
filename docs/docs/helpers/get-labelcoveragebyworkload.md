# Get-LabelCoverageByWorkload

Compute sensitivity-label coverage per Microsoft 365 workload from a folder of per-tag CSV exports. Part of the `PurviewContentExplorerHelpers` module - it reads the exporter's CSV output and calls no Purview cmdlet.

Everything is derived from row data, never from filenames:

- **Item identity** is `FileUrl` (SPO/ODB), falling back to `FileSourceUrl`+`FileName` (EXO/Teams). The cmdlet's `Location` column duplicates `Workload` and is not an item identity.
- Items are de-duplicated per workload, so an item matching several tags is counted once.
- An item counts as **labelled** when any of its rows carries a non-empty `SensitivityLabel` GUID (the exporter writes the applied label on every row, whatever was swept) or appears under a row whose `TagType` is `Sensitivity`.

## Synopsis

```powershell
Get-LabelCoverageByWorkload
    -Path <string>
```

## Parameters

| Name | Type | Default | Notes |
|---|---|---|---|
| `-Path` | `string` | required | Folder of per-tag CSV files produced by `Invoke-CESweep.ps1` / `Export-CEItems.ps1` |

## Examples

```powershell
Import-Module ./helpers/src/PurviewContentExplorerHelpers.psd1

# Coverage table
Get-LabelCoverageByWorkload -Path ./output/ | Format-Table

# Sort by the least-covered workload first
Get-LabelCoverageByWorkload -Path ./output/ | Sort-Object CoveragePct
```

Example output:

```text
Workload TotalItems Labelled Unlabelled CoveragePct
-------- ---------- -------- ---------- -----------
EXO            1240      870        370        70.2
ODB             980      210        770        21.4
SPO             430      400         30        93.0
```

## Output

One `PSCustomObject` (type name `PurviewContentExplorerHelpers.LabelCoverage`) per workload:

| Property | Notes |
|---|---|
| `Workload` | `EXO` / `ODB` / `SPO` / `Teams` |
| `TotalItems` | Distinct items seen in that workload across all tags |
| `Labelled` | Distinct items with a `SensitivityLabel` GUID or a `Sensitivity` tag row |
| `Unlabelled` | `TotalItems - Labelled` |
| `CoveragePct` | `Labelled / TotalItems * 100`, rounded to one decimal place |

## Notes

- The denominator is every distinct item in the folder, so include whatever sweeps define "items worth labelling" - typically the SIT / classifier sweeps, with a Sensitivity sweep adding the most complete label signal.
- The `items_all.csv` roll-up is skipped (it duplicates every per-tag row) unless it is the only CSV in the folder. Files lacking the `TagType` / `Workload` columns and rows with no derivable item identity are ignored.
