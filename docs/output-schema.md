# Output schema

## Per-tag CSV — `items_<TagType>_<safe-name>.csv`

One per `(TagType, TagName)` combination that had at least one hit. Filename uses a safe-name transform (any character outside `[A-Za-z0-9._-]` is replaced with `_`) so e.g. `Credit Card Number` → `items_SensitiveInformationType_Credit_Card_Number.csv`.

### Columns

| Column | Source | Notes |
|---|---|---|
| `TagType` | added by worker | One of `SensitiveInformationType`, `Sensitivity`, `Retention`, `TrainableClassifier` |
| `TagName` | added by worker | The full label/SIT name |
| `Workload` | added by worker | `EXO`, `ODB`, `SPO`, or `Teams` |
| `Location` | from cmdlet | Same as `Workload` (Microsoft includes both) |
| `FileSourceUrl` | from cmdlet | Site/mailbox URL — for SPO/ODB this is the site root, for EXO/Teams it's the user's UPN |
| `FileUrl` | from cmdlet | Full path to the file (SPO/ODB only). Empty for EXO/Teams |
| `FileName` | from cmdlet | File name (SPO/ODB), email subject (EXO), or "Posted in #channel" (Teams) |
| `SensitiveInfoTypes` | from cmdlet | Comma-separated GUIDs of all SITs detected in this item |
| `SensitivityLabel` | from cmdlet | GUID of the sensitivity label applied (if any) |
| `RetentionLabel` | from cmdlet | Retention label name (if any) |
| `TrainableClassifiers` | from cmdlet | Comma-separated GUIDs of trainable classifiers that fired |
| `UserCreated` | from cmdlet | Display name of the creator |
| `UserModified` | from cmdlet | Display name of the last modifier |
| `LastModifiedTime` | from cmdlet | UTC timestamp |
| `SensitiveInfoTypesData` | from cmdlet | JSON array — see below |

### `SensitiveInfoTypesData` JSON

For each detected SIT, this column contains a confidence-level breakdown:

```json
[
  {
    "Id": "50842eb5-1a3c-44a2-8aa4-1ae3a5e92c10",
    "LowConfidenceMatch": 0,
    "MediumConfidenceMatch": 3,
    "HighConfidenceMatch": 1
  }
]
```

The `Id` matches one of the GUIDs in the `SensitiveInfoTypes` column. Numbers are match counts at each confidence level — useful for ranking or filtering ("show me only files with at least one high-confidence Credit Card match").

## Roll-up — `items_all.csv`

Concatenation of every per-tag `items_*.csv` (excluding `items_all.csv` itself). Schemas can vary across workloads (SPO/ODB rows have a real `FileUrl`, EXO rows don't), so the roll-up **column-unions** all per-tag files: it collects every property name across all rows and re-emits each row with that full column set, leaving missing fields blank.

This means you can analyse a single CSV in Excel/Power BI without worrying about which workload contributed which columns.

## `sweep.log`

Append-only, timestamped, one line per worker invocation:

```text
2026-04-30T14:32:01Z  ok      SensitiveInformationType   "Credit Card Number"          rows=42
2026-04-30T14:32:08Z  skip    SensitiveInformationType   "U.S. Social Security Number" exists
2026-04-30T14:32:09Z  fail    SensitiveInformationType   "Azure Storage Account Key"   <error message>
```

Status values:

- `ok` — worker completed, per-tag CSV written (`rows=N` is the number of items)
- `skip` — per-tag CSV already existed, worker not invoked (`exists`)
- `fail` — worker threw, per-tag CSV not written; tag will retry on next run

## Sample output

The repo includes a 15-row synthetic sample at [`examples/items_all.sample.csv`](https://github.com/LukeEvansTech/purview-content-explorer-export/blob/main/examples/items_all.sample.csv) covering all four workloads, multiple SITs, and the various row shapes you'll see (full file URL for SPO/ODB, empty `FileUrl` + email subject for EXO, channel reference for Teams).
