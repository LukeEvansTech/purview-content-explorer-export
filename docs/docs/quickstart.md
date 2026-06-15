# Quick start

## Prerequisites

- **PowerShell 5.1+ or PowerShell 7+.** The scripts declare `#Requires -Version 5.1`, so they run on stock Windows PowerShell 5.1 as well as PowerShell 7 (macOS, Windows, Linux). On 5.1, CSV output is UTF-8 *with* a BOM (PowerShell 7 omits it) - Excel, Power BI, and `Import-Csv` all read either form.
- **`ExchangeOnlineManagement` module** (provides `Connect-IPPSSession` and `Export-ContentExplorerData`). Use **v3 or later** - on Windows PowerShell 5.1 the connection probe prefers `Get-ConnectionInformation`, which v3+ supplies (it falls back to `Get-Label` on older modules):
  ```powershell
  Install-Module ExchangeOnlineManagement -Scope CurrentUser
  ```
- **`Pester` 5+** - only needed if you want to run the offline unit tests:
  ```powershell
  Install-Module Pester -Scope CurrentUser -SkipPublisherCheck
  ```
- **Microsoft 365 account with the `Content Explorer List Viewer` role group** assigned in Microsoft Purview. Without this, `Export-ContentExplorerData` returns "access denied" for every call.

## Install

Clone the repository - the scripts run in place:

```bash
git clone https://github.com/LukeEvansTech/purview-content-explorer-export.git
cd purview-content-explorer-export
```

The scripts are already executable in the repository. If `chmod` got stripped:

```bash
chmod +x ./Invoke-CESweep.ps1 ./Export-CEItems.ps1
```

Verify Pester tests still pass:

```bash
pwsh -NoProfile -Command "Invoke-Pester ./tests -CI"
# Expected: Tests Passed: 61
```

## Run

```powershell
# 1. Connect interactively (one-time per shell session, ~1h token life).
Connect-IPPSSession

# 2. Dry-run to see which SITs would be swept — no item exports yet.
./Invoke-CESweep.ps1 -DryRun

# 3. Sweep. Default is all SensitiveInformationTypes across all four workloads.
./Invoke-CESweep.ps1
```

Output lands in `./output/`:

- `items_<TagType>_<safe-name>.csv` - one per `(TagType, TagName)` that had at least one hit
- `items_all.csv` - concatenation of all per-tag files, schemas unioned (load this into Excel / Power BI)
- `sweep.log` - append-only timestamped status log

!!! tip "Curate your include list"
    Sweeping all 300+ tenant SITs typically takes many hours and most of them won't be relevant to your DLP policies. Maintain a CSV of the ~50 names you actually care about and pass it via `-NamesFile`. See [Common scenarios](usage.md) for examples.

## Verify it worked

After the sweep finishes, you should see a summary like:

```text
processed=52 succeeded=52 skipped=0 failed=0
```

The roll-up CSV is the file you'll work with:

```bash
ls -la output/items_all.csv
wc -l output/items_all.csv     # one row per item + 1 header
```

Open it in Excel / Power BI and pivot by `TagName` × `Workload` to see where each SIT is finding hits.
