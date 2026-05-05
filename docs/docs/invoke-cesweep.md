# Invoke-CESweep.ps1

The orchestrator. Connects to Security & Compliance PowerShell, enumerates tags, applies filters, dispatches the worker per tag, writes a per-tag status log, and produces the merged roll-up CSV.

## Synopsis

```powershell
./Invoke-CESweep.ps1
    [-TagTypes <string[]>]
    [-NameLike <string[]>]
    [-NameNotLike <string[]>]
    [-NamesFile <string>]
    [-NamesColumn <string>]
    [-Workloads <string[]>]
    [-OutDir <string>]
    [-PageSize <int>]
    [-Force]
    [-DryRun]
```

## Parameters

| Name | Type | Default | Notes |
|---|---|---|---|
| `-TagTypes` | `string[]` | `SensitiveInformationType` | Subset of `Retention`, `SensitiveInformationType`, `Sensitivity`, `TrainableClassifier` |
| `-NameLike` | `string[]` | `*` | Wildcard include filter on tag name (case-insensitive). OR semantics — matches if any pattern matches |
| `-NameNotLike` | `string[]` | (none) | Wildcard exclude filter. Excludes if any pattern matches |
| `-NamesFile` | `string` | (none) | Path to a CSV. When set, replaces `-NameLike` entirely with the values from the chosen column |
| `-NamesColumn` | `string` | `Name` | Which column to read names from in `-NamesFile` |
| `-Workloads` | `string[]` | `EXO,ODB,SPO,Teams` | Subset to query |
| `-OutDir` | `string` | `./output` | Where per-tag CSVs and the roll-up land |
| `-PageSize` | `int` | `1000` | 1–10000, passed through to the cmdlet |
| `-Force` | `switch` | off | Re-export tags even if a per-tag CSV already exists |
| `-DryRun` | `switch` | off | Enumerate + filter, print the plan, exit. No item exports, no connection check |

## Examples

```powershell
# Default sweep — all SITs, all workloads
./Invoke-CESweep.ps1

# Curated SIT list from a CSV
./Invoke-CESweep.ps1 -NamesFile ./my-sits.csv

# Sweep retention labels and sensitivity labels, no SITs
./Invoke-CESweep.ps1 -TagTypes Retention,Sensitivity

# Force a complete re-export (overwriting existing CSVs)
./Invoke-CESweep.ps1 -Force

# DryRun — see what would be swept without exporting anything
./Invoke-CESweep.ps1 -NamesFile ./my-sits.csv -DryRun
```

## Behaviour

1. **Connection check.** Probes via `Get-ConnectionInformation` (or `Get-Label | Select-Object -First 1` as fallback). Runs `Connect-IPPSSession` interactively if no active session.
2. **Enumerate tags.** For each requested `TagType`, calls the matching `Get-*` cmdlet and applies `-NameLike`/`-NameNotLike` filters. Deduplicates on `(TagType, Name)` since some `Get-*` cmdlets return multiple objects with the same display name.
3. **DryRun short-circuit.** If `-DryRun`, prints the planned `(TagType, TagName)` list and exits. The connection check is skipped under DryRun, so this works offline against an unauthenticated session — it'll print warnings about cmdlets being unavailable, which is the expected behaviour for a smoke test.
4. **Dispatch.** For each tag, checks if the per-tag CSV exists. If yes and `-Force` not set → log `skip` and continue. Otherwise invoke `Export-CEItems.ps1` with the same parameters.
5. **Roll-up.** After the dispatch loop, concatenate every `items_*.csv` (except `items_all.csv`) into `items_all.csv`, computing the column union so schemas-divergent files don't drop columns.
6. **Exit code.** `0` if `failed=0`, `1` otherwise.

## Edge cases handled

- **`Get-ConnectionInformation` not available** — falls back to `Get-Label | Select-Object -First 1`.
- **Trainable Classifier cmdlet name varies by tenant** — orchestrator detects and skips with a warning, doesn't fail the whole sweep.
- **CSV with `#` column header** — `Import-Csv` treats `#`-prefixed lines as comments, dropping the real header. Orchestrator reads the header line manually and feeds it to `ConvertFrom-Csv -Header`.
- **Strict-mode `.Count` on a scalar `FileInfo`** — wraps `Get-ChildItem` in `@(...)` to force-array.
- **Per-tag CSVs with mismatched schemas** — roll-up computes column union so EXO's `UserPrincipalName`-shape rows and SPO's `SiteUrl`-shape rows coexist in `items_all.csv`.
