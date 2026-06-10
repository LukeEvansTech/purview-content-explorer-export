# Find-UnlabeledPII

Find items that a Purview classifier flagged as containing PII but that carry **no sensitivity label**. Part of the `PurviewContentExplorerHelpers` module — it reads the per-tag CSVs the exporter produced; it does not call any Purview cmdlet.

A row is treated as a **label** when its `TagType` is `Sensitivity`, and as a **PII hit** when its `TagName` matches one of `-PIIClassifier`. An item (keyed by `Location`) is reported only when it appears under a PII classifier and never under a sensitivity label.

## Synopsis

```powershell
Find-UnlabeledPII
    -Path <string>
    [-PIIClassifier <string[]>]
```

## Parameters

| Name | Type | Default | Notes |
|---|---|---|---|
| `-Path` | `string` | required | Folder of per-tag CSV files (one CSV per tag) produced by `Invoke-CESweep.ps1` / `Export-CEItems.ps1` |
| `-PIIClassifier` | `string[]` | common built-ins | Classifier names to treat as PII, matched against each row's `TagName` with `-like` (so `'*Social Security*'` works) |

The default `-PIIClassifier` list is `All Full Names`, `EU Debit Card Number`, `U.S. Social Security Number (SSN)`, `EU Driver's License Number`, and `PII (default - All)`. Override it to match the classifiers you actually swept.

## Examples

```powershell
Import-Module ./helpers/src/PurviewContentExplorerHelpers.psd1

# Default classifiers
Find-UnlabeledPII -Path ./output/

# A specific classifier, with a wildcard
Find-UnlabeledPII -Path ./output/ -PIIClassifier '*Social Security*'

# Triage the worst offenders into a CSV
Find-UnlabeledPII -Path ./output/ | Sort-Object Workload | Export-Csv ./unlabeled-pii.csv -NoTypeInformation
```

## Output

One `PSCustomObject` (type name `PurviewContentExplorerHelpers.UnlabeledPII`) per distinct unlabelled item:

| Property | Notes |
|---|---|
| `Classifier` | The matching PII classifier name(s), comma-separated when an item matched more than one |
| `Location` | The item identity / path (the join key) |
| `Workload` | `EXO` / `ODB` / `SPO` / `Teams` |
| `ItemSize` | As exported (string) |
| `Modified` | As exported (string) |

## Notes

- For the result to mean anything, the folder must contain **both** the sensitivity-label sweep (`-TagTypes Sensitivity`) and the PII-classifier sweeps — otherwise there are no `Sensitivity` rows to exclude against and every PII hit looks unlabelled.
- Rows without a `Location` value are ignored. If no row matches the classifier(s), a warning is written and nothing is returned.
