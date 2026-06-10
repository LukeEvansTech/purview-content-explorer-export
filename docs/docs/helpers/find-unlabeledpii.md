# Find-UnlabeledPII

Find items that a Purview classifier flagged as containing PII but that carry **no sensitivity label**. Part of the `PurviewContentExplorerHelpers` module — it reads the per-tag CSVs the exporter produced; it does not call any Purview cmdlet.

Everything is derived from row data, never from filenames:

- **Item identity** is `FileUrl` (SPO/ODB), falling back to `FileSourceUrl`+`FileName` (EXO/Teams). The cmdlet's `Location` column duplicates `Workload` and is not an item identity.
- An item is **labelled** when any of its rows carries a non-empty `SensitivityLabel` GUID (the exporter writes the applied label on every row, whatever was swept), or when it appears under a row whose `TagType` is `Sensitivity`.
- A row is a **PII hit** when its `TagName` matches one of `-PIIClassifier`.

An item is reported only when it appears under a PII classifier and is never seen labelled.

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
| `Workload` | `EXO` / `ODB` / `SPO` / `Teams` |
| `FileName` | Filename (SPO/ODB), email subject (EXO), or "Posted in #channel" (Teams) |
| `FileUrl` | Full path to the file (SPO/ODB only; empty for EXO/Teams) |
| `FileSourceUrl` | Site/mailbox URL — site root for SPO/ODB, the user's UPN for EXO/Teams |
| `LastModifiedTime` | UTC timestamp, as exported |

## Notes

- The `items_all.csv` roll-up is skipped (it duplicates every per-tag row) unless it is the only CSV in the folder. Files lacking a `TagType` column and rows with no derivable item identity are ignored.
- Item-identity matching is case-insensitive, so URL-casing drift between sweeps does not produce false positives.
- Because the per-row `SensitivityLabel` GUID marks labelled items, a Sensitivity sweep in the folder is not strictly required — but including one is still the most complete label signal.
- If no row matches the classifier(s), a warning is written and nothing is returned.
