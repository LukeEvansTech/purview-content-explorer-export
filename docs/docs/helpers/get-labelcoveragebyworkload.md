# Get-LabelCoverageByWorkload

Compute sensitivity-label coverage per Microsoft 365 workload from a folder of per-tag CSV exports. Part of the `PurviewContentExplorerHelpers` module — it reads the exporter's CSV output and calls no Purview cmdlet.

Items are de-duplicated by `(Workload, Location)`, so an item that matches several tags is counted once. An item counts as **labelled** when it appears in any row whose `TagType` is `Sensitivity`.

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
| `Labelled` | Distinct items that appear under a `Sensitivity` tag |
| `Unlabelled` | `TotalItems - Labelled` |
| `CoveragePct` | `Labelled / TotalItems * 100`, rounded to one decimal place |

## Notes

- The denominator is every distinct item in the folder, so the export must contain the tags you want counted — typically the sensitivity-label sweep (`-TagTypes Sensitivity`) plus whatever SIT / classifier sweeps define "items worth labelling".
- Rows without a `Workload` or `Location` value (for example a header-only empty export) are ignored.
