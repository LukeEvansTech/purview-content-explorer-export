# purview-content-explorer-export

PowerShell tool for exporting **item-level data** from Microsoft Purview Content Explorer — one row per file/email — across all four Microsoft 365 workloads (Exchange, SharePoint, OneDrive, Teams) and across many tags (Sensitive Information Types, Sensitivity labels, Retention labels, Trainable Classifiers).

It wraps the [`Export-ContentExplorerData`](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/export-contentexplorerdata) cmdlet with the boring-but-essential plumbing: pagination, multi-workload fan-out, per-tag CSV files, a merged roll-up, skip-existing for resumable runs, and a CSV-driven include list so you can sweep only the SITs you actually care about.

> **Not affiliated with Microsoft.** "Microsoft Purview" and "Content Explorer" are Microsoft trademarks. This tool just calls a public PowerShell cmdlet.

---

## What you get out

For every `(TagType, TagName)` combination that has hits in your tenant, you get a CSV with one row per matching item. Columns include:

| Column | What it is |
|---|---|
| `TagType` | `SensitiveInformationType`, `Sensitivity`, `Retention`, or `TrainableClassifier` |
| `TagName` | The label/SIT/classifier name (e.g. `Credit Card Number`) |
| `Workload` | `EXO`, `ODB`, `SPO`, or `Teams` |
| `Location` | Same as workload (Microsoft includes both) |
| `FileSourceUrl` | Site / mailbox URL |
| `FileUrl` | Full path to the file (SPO/ODB) — empty for EXO/Teams |
| `FileName` | File name (SPO/ODB), email subject (EXO), or "Posted in #channel" (Teams) |
| `SensitiveInfoTypes` | Comma-separated GUIDs of all SITs detected in this item |
| `SensitivityLabel` | GUID of the sensitivity label applied (if any) |
| `RetentionLabel` | Retention label name (if any) |
| `TrainableClassifiers` | Comma-separated GUIDs of trainable classifiers that fired |
| `UserCreated` | Display name of creator |
| `UserModified` | Display name of last modifier |
| `LastModifiedTime` | UTC timestamp |
| `SensitiveInfoTypesData` | JSON array with confidence-level match counts per SIT |

A 15-row example is in [`examples/items_all.sample.csv`](examples/items_all.sample.csv) — fake but representative.

---

## Prerequisites

- **PowerShell 7+.** The scripts declare `#Requires -Version 7.0` because they rely on member-access enumeration on pipelines, which doesn't work in PS 5.1. macOS, Windows, and Linux all work.
- **`ExchangeOnlineManagement` module** (provides `Connect-IPPSSession` and `Export-ContentExplorerData`):
  ```powershell
  Install-Module ExchangeOnlineManagement -Scope CurrentUser
  ```
- **`Pester` 5+** — only needed if you want to run the offline unit tests:
  ```powershell
  Install-Module Pester -Scope CurrentUser -SkipPublisherCheck
  ```
- **Microsoft 365 account with the `Content Explorer List Viewer` role group** assigned in Microsoft Purview. Without this, `Export-ContentExplorerData` returns "access denied" for every call.

---

## Install

Clone the repo and you're done — the scripts run in place:

```bash
git clone https://github.com/<you>/purview-content-explorer-export.git
cd purview-content-explorer-export
```

Mark the scripts executable if your shell needs it (already done in repo):

```bash
chmod +x ./Invoke-CESweep.ps1 ./Export-CEItems.ps1
```

Verify Pester tests still pass:

```bash
pwsh -NoProfile -Command "Invoke-Pester ./tests/CEHelpers.Tests.ps1 -CI"
# Expected: Tests Passed: 18
```

---

## Quick start

```powershell
# 1. Connect interactively (one-time per shell session, ~1h token life).
Connect-IPPSSession

# 2. Dry-run to see which SITs would be swept — no item exports yet.
./Invoke-CESweep.ps1 -DryRun

# 3. Sweep. Default is all SensitiveInformationTypes across all four workloads.
./Invoke-CESweep.ps1
```

Output lands in `./output/`:
- `items_<TagType>_<safe-name>.csv` — one per `(TagType, TagName)` that had at least one hit
- `items_all.csv` — concatenation of all per-tag files, schemas unioned (the file you load into Excel / Power BI)
- `sweep.log` — append-only timestamped status log

---

## Configuration / common scenarios

### Sweep a curated subset of SITs

Most users don't want all 300+ tenant SITs — they want the ~50 they actually have policies for. Maintain a CSV with a `Name` column and pass it via `-NamesFile`:

```powershell
./Invoke-CESweep.ps1 -NamesFile ./my-sits.csv
```

The example file [`examples/names-credentials.example.csv`](examples/names-credentials.example.csv) is a 52-name credentials-focused list (Tier 1 generic credential detectors + Tier 2 cloud provider secrets). Use it directly or as a template:

```powershell
./Invoke-CESweep.ps1 -NamesFile ./examples/names-credentials.example.csv
```

The orchestrator reads the `Name` column by default. Override with `-NamesColumn`:

```powershell
./Invoke-CESweep.ps1 -NamesFile ./list.csv -NamesColumn 'SIT Name'
```

After enumeration, names from your file that didn't match anything in the tenant are listed as a warning — useful for spotting typos or names that exist in your list but not in this tenant.

### Other tag types

```powershell
# Sensitivity labels only
./Invoke-CESweep.ps1 -TagTypes Sensitivity

# Multiple tag types
./Invoke-CESweep.ps1 -TagTypes SensitiveInformationType,Sensitivity,Retention

# Trainable classifiers (note: the cmdlet name varies by tenant — see Troubleshooting)
./Invoke-CESweep.ps1 -TagTypes TrainableClassifier
```

### Narrow by name pattern

```powershell
# All SITs whose name starts with "Credit"
./Invoke-CESweep.ps1 -NameLike 'Credit*'

# Sweep everything except the named patterns
./Invoke-CESweep.ps1 -NameNotLike 'Default *','General','Public'
```

### Subset of workloads

```powershell
./Invoke-CESweep.ps1 -Workloads EXO,SPO
```

### Force / resume

```powershell
# Re-run is safe — tags whose per-tag CSV already exists are skipped.
./Invoke-CESweep.ps1

# Force a complete re-export, overwriting existing CSVs.
./Invoke-CESweep.ps1 -Force
```

### One tag, by hand

```powershell
./Export-CEItems.ps1 -TagType SensitiveInformationType -TagName 'Credit Card Number'
```

---

## Recovery (the `Connect-IPPSSession` token expires after ~1h)

A typical 50-SIT credential sweep takes ~1–1.5 hours; a wider sweep can run for many hours. The session token from `Connect-IPPSSession` lives ~60 minutes, so longer runs *will* hit token expiry mid-sweep.

**Recovery is automatic-ish:**

1. When the token expires, the worker will fail every workload for the current and subsequent tags (`all 4 workload(s) errored — see warnings above`). Each failed tag is logged to `sweep.log` as `fail`.
2. **Re-authenticate and re-run the same command.** Skip-existing means tags whose per-tag CSV already exists are skipped, so the sweep picks up where it left off:
   ```powershell
   Connect-IPPSSession      # re-auth
   ./Invoke-CESweep.ps1 -NamesFile ./my-sits.csv   # resume
   ```
3. Use `-Force` only if you actually want to re-export tags that already have a CSV.

The orchestrator exits with code 1 if any tag failed in the run, 0 otherwise. CI-style automation can re-run on non-zero exit.

---

## Working with non-canonical SIT names

A common gotcha: SIT lists exported from Microsoft documentation, planning spreadsheets, or DLP policy templates often use *almost* the right names. Examples we've hit:

| What the spreadsheet says | What the tenant actually returns |
|---|---|
| `All credentials` | `All Credential Types` |
| `Australia drivers license number` | `Australia Driver's License Number` |
| `Germany passport number` | `German Passport Number` |
| `Luxemburg passport number` | `Luxembourg Passport Number` |
| `U.A.E. identity card number` | `UAE Identity Card Number` |

The orchestrator's `-NameLike` is case-insensitive (PowerShell `-like`), so case differences resolve automatically. But "All credentials" vs "All Credential Types" is a real semantic mismatch and won't match.

The companion script [`scripts/match-sits.ps1`](scripts/match-sits.ps1) helps fix this. It connects to your tenant, dumps the canonical SIT list, and for each name in your input CSV suggests the closest tenant match using normalized-exact, substring, and Levenshtein-distance fallbacks:

```powershell
./scripts/match-sits.ps1 -NamesFile ./my-sits.csv
# Inspect /tmp/sit_mappings.csv for the suggestions, hand-curate, then save back.
```

---

## Output schema

### Per-tag CSV — `items_<TagType>_<safe-name>.csv`

Columns are described in the [What you get out](#what-you-get-out) section above. Schema can vary slightly by workload — for example SPO/ODB rows have a real `FileUrl`, while EXO rows have an empty `FileUrl` and the email subject in `FileName`. The orchestrator's roll-up handles this by **column-unioning** all per-tag files when producing `items_all.csv`.

### Roll-up — `items_all.csv`

Concatenation of every `items_*.csv` (excluding itself). Because per-tag files can have slightly different schemas across workloads and tag types, the roll-up collects the union of all column names and re-emits each row with that full column set, leaving missing fields blank. This means you can analyse a single CSV in Excel/Power BI without worrying about which workload contributed which columns.

### `sweep.log`

Append-only, timestamped, one line per worker invocation:

```
2026-04-30T14:32:01Z  ok      SensitiveInformationType   "Credit Card Number"          rows=42
2026-04-30T14:32:08Z  skip    SensitiveInformationType   "U.S. Social Security Number" exists
2026-04-30T14:32:09Z  fail    SensitiveInformationType   "Azure Storage Account Key"   <error message>
```

---

## Troubleshooting

**`Get-Label -ResultSize 1` fails with "parameter cannot be found"** — fixed in current code. The connection probe uses `Get-ConnectionInformation` first and falls back to `Get-Label | Select-Object -First 1`.

**`Connect-IPPSSession` opens a browser window that the user can't see** — the popup sometimes hides behind other windows or doesn't focus. If after 60s nothing has happened, kill the pwsh process and try again. As an alternative, you can use device-code auth: `Connect-IPPSSession -UseDeviceAuthentication` (prints a code to paste into [microsoft.com/devicelogin](https://microsoft.com/devicelogin)).

**`Cannot index into a null array` from the worker** — happens when `Export-ContentExplorerData` emits `Write-Error` without throwing terminating, leaving `$response` null. The current code defensively checks for null and surfaces a clearer message ("server-side error the cmdlet did not throw"). The most common cause is a TagName that doesn't actually exist in the tenant for the requested workload — check enumeration coverage with `-DryRun`.

**`The property 'Count' cannot be found on this object`** — fixed. Caused by `Set-StrictMode -Version Latest` rejecting member-access enumeration on a scalar `FileInfo`. The roll-up now wraps `Get-ChildItem` in `@(...)`.

**CSV with a `#` column header has the header silently dropped** — fixed. `Import-Csv` treats lines starting with `#` as comments. The orchestrator now reads the header line manually and feeds it to `ConvertFrom-Csv -Header`.

**Trainable Classifier enumeration fails with "cmdlet 'Get-DlpTrainableClassifier' not available"** — the cmdlet name for listing trainable classifiers varies by tenant rollout. The orchestrator detects this and prints a warning, skipping that tag type. Workarounds: (a) supply names via `-NameLike` against a known list of classifier names, or (b) drop `TrainableClassifier` from `-TagTypes`.

**`Export-ContentExplorerData` returns `WARNING: The TotalCount value might be different from the total number of items returned`** — this is a benign warning emitted by the cmdlet on every call. Ignore it. To silence: edit the worker to add `-WarningAction SilentlyContinue` to the `Export-ContentExplorerData` call.

**Sweep is much slower than expected** — typical pace is 30–90s per tag depending on result size. Token expiry blocks at the ~60-min boundary. If a tag with millions of items is taking many minutes, that's expected — the cmdlet paginates 10k items per call. Use `-NamesFile` with a curated list to avoid sweeping high-volume SITs you don't care about.

**Roll-up `items_all.csv` is missing columns from some per-tag files** — fixed. Earlier versions used `Import-Csv | Export-Csv` which adopts the first object's schema and silently drops columns from later objects. The current code computes a column union before re-emitting.

---

## Tests

```powershell
Invoke-Pester ./tests/CEHelpers.Tests.ps1 -CI
# Expected: Tests Passed: 18
```

Only pure-logic helpers (`Get-CESafeName`, `Test-CETagNameFilter`, `Get-CETagTypeEnumeration`) are unit-tested. Cmdlet integration is covered by manual smoke testing against a real M365 tenant — no offline equivalent exists for `Export-ContentExplorerData`.

---

## Architecture (for contributors)

```
purview-content-explorer-export/
  Export-CEItems.ps1          # worker — one (TagType, TagName), N workloads
  Invoke-CESweep.ps1          # orchestrator — enumerate, filter, dispatch, roll-up
  lib/CEHelpers.psm1          # pure helpers (offline-testable)
  tests/CEHelpers.Tests.ps1   # Pester unit tests
  scripts/match-sits.ps1      # canonical-name matcher for non-canonical CSVs
  examples/
    items_all.sample.csv               # synthetic sample output
    names-credentials.example.csv      # sample curated SIT list (52 names)
  output/                     # gitignored, created at runtime
```

The orchestrator imports the worker as a script (`& $workerScript ...`) per tag, so each tag is a fresh script execution. Per-workload errors stay inside the worker (logged as warnings, don't abort the tag); per-tag errors stay inside the orchestrator (logged to `sweep.log` as `fail`, don't abort the sweep). Only a wholesale enumeration failure or connection failure aborts the run.

---

## Contributing

PRs welcome. Please:

1. Keep `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` in both top-level scripts.
2. Add Pester tests for any new pure-logic helper added to `lib/CEHelpers.psm1`.
3. Don't introduce a dependency on a third-party PowerShell module that isn't already required (e.g. don't pull in `ImportExcel` — read CSVs).
4. If you fix a footgun, add a one-line note in the Troubleshooting section so the next person doesn't hit it.

---

## License

MIT — see [LICENSE](LICENSE).
