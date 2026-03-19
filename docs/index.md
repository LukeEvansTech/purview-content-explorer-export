# purview-content-explorer-export

PowerShell tool for exporting **item-level data** from Microsoft Purview Content Explorer — one row per file/email — across all four Microsoft 365 workloads (Exchange, SharePoint, OneDrive, Teams) and across many tags (Sensitive Information Types, Sensitivity labels, Retention labels, Trainable Classifiers).

It wraps the [`Export-ContentExplorerData`](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/export-contentexplorerdata) cmdlet with the boring-but-essential plumbing: pagination, multi-workload fan-out, per-tag CSV files, a merged roll-up, skip-existing for resumable runs, and a CSV-driven include list so you can sweep only the SITs you actually care about.

!!! note "Not affiliated with Microsoft"
    "Microsoft Purview" and "Content Explorer" are Microsoft trademarks. This tool just calls a public PowerShell cmdlet.

## What you get out

For every `(TagType, TagName)` combination that has hits in your tenant, you get a CSV with one row per matching item. Columns include file paths, file names, creators, modifiers, last-modified timestamps, and JSON-encoded confidence-level match counts.

Roughly the answer to **"which files in M365 contain unprotected credential material"** for your tenant.

| Column | What it is |
|---|---|
| `TagType` | `SensitiveInformationType`, `Sensitivity`, `Retention`, or `TrainableClassifier` |
| `TagName` | The label/SIT/classifier name (e.g. `Credit Card Number`) |
| `Workload` | `EXO`, `ODB`, `SPO`, or `Teams` |
| `FileUrl` | Full path to the file (SPO/ODB) — empty for EXO/Teams |
| `FileName` | File name (SPO/ODB), email subject (EXO), or "Posted in #channel" (Teams) |
| `UserCreated` / `UserModified` | Display name of creator / last modifier |
| `LastModifiedTime` | UTC timestamp |
| `SensitiveInfoTypesData` | JSON array with confidence-level match counts per SIT |

Full schema documented at [Output schema](output-schema.md). A 15-row sample lives in `examples/items_all.sample.csv` in the repo.

## Where to next

- **First time?** → [Quick start](quickstart.md)
- **Want to sweep only specific SITs?** → [Common scenarios](usage.md)
- **A long sweep got interrupted?** → [Recovery & resumability](recovery.md)
- **Hit an error?** → [Troubleshooting](troubleshooting.md)

## Why this exists

Microsoft's `Export-ContentExplorerData` cmdlet returns at most 100 rows per call (10,000 with `-PageSize`), only one tag at a time, and only one workload at a time. To get a tenant-wide inventory of "which files contain Credit Card Numbers" you need to call it many hundreds of times with pagination, error handling, retry, and aggregation. This tool does that.

The original spec started with the cmdlet's `-Aggregate` switch (folder-level counts) but pivoted to item-level detail because the question you actually want answered is **which file**, not just **how many files**.

## License

[MIT](https://github.com/LukeEvansTech/purview-content-explorer-export/blob/main/LICENSE)
