# Microsoft Purview Content Explorer — Aggregate Sweep

**Date:** 2026-04-30
**Status:** Approved (design phase)

## Goal

Produce a tenant-wide aggregate inventory of Microsoft Purview Content Explorer data — folder-level counts of items stamped with each label, sensitive info type, retention tag, and trainable classifier — using the `Export-ContentExplorerData` cmdlet from Security & Compliance PowerShell.

The output is a baseline inventory: which tags hit which folders/mailboxes/sites and how many items each. Item-level detail is explicitly out of scope.

## Non-Goals

- Item-level export (no use of `Export-ContentExplorerData` without `-Aggregate`).
- Certificate-based / unattended authentication. Interactive only.
- Re-auth on session-token expiry mid-run. Re-running is the recovery path; skip-existing handles resumption.
- Parallel execution.
- Ongoing scheduling. This is a one-shot sweep tool the user runs as needed.

## Architecture

Two PowerShell scripts plus a shared output convention.

```
tbcontentexplorer/
  Export-CEAggregate.ps1            # worker (one tag, one or more workloads)
  Invoke-CEAggregateSweep.ps1       # orchestrator (enumerate + dispatch + roll-up)
  output/
    aggregate_<TagType>_<safe-name>.csv
    aggregate_all.csv               # merged roll-up
    sweep.log                       # per-tag status log
```

The worker is independently runnable for one-off use; the orchestrator imports/invokes it.

## Worker — `Export-CEAggregate.ps1`

### Parameters

| Name | Type | Default | Notes |
|---|---|---|---|
| `-TagType` | enum | required | `Retention`, `SensitiveInformationType`, `Sensitivity`, `TrainableClassifier` |
| `-TagName` | string | required | Passed verbatim to `Export-ContentExplorerData` |
| `-Workloads` | string[] | `EXO,ODB,SPO,Teams` | Subset to query |
| `-OutDir` | path | `./output` | Created if missing |
| `-Force` | switch | off | Overwrite existing per-tag CSV |
| `-PageSize` | int | `1000` | 1–10000, passed through |

### Behaviour

1. If `-Force` is not set and `aggregate_<TagType>_<safe-name>.csv` already exists, log "skip (exists)" and return.
2. For each workload in `-Workloads`:
   a. First call: `Export-ContentExplorerData -Aggregate -TagType $T -TagName $N -Workload $W -PageSize $P`.
   b. While `MorePagesAvailable -eq $true`, repeat with `-PageCookie $cookie`.
   c. For each returned record, add `TagType`, `TagName`, and `Workload` columns (these are the join keys for the roll-up; storing them in-row avoids relying on the lossy filename mapping).
3. Concatenate records across workloads and write `aggregate_<TagType>_<safe-name>.csv` (UTF-8, `-NoTypeInformation`).
4. Filename safe-name rule: replace any character outside `[A-Za-z0-9._-]` with `_`.
5. Per-workload errors are caught, written to `sweep.log`, and do not abort other workloads or tags.

### Why pagination is still used in aggregate mode

The Microsoft docs state `-Aggregate` reduces export time but do not guarantee a single-call response. Looping on `PageCookie` is cheap insurance; in the common case the loop runs once.

## Orchestrator — `Invoke-CEAggregateSweep.ps1`

### Parameters

| Name | Type | Default | Notes |
|---|---|---|---|
| `-TagTypes` | string[] | all four | Which tag types to enumerate |
| `-NameLike` | string[] | `*` | Wildcard include filter on tag name |
| `-NameNotLike` | string[] | (none) | Wildcard exclude filter on tag name |
| `-Workloads` | string[] | `EXO,ODB,SPO,Teams` | Pass-through to worker |
| `-OutDir` | path | `./output` | Pass-through to worker |
| `-Force` | switch | off | Pass-through to worker |
| `-PageSize` | int | `1000` | Pass-through to worker |
| `-DryRun` | switch | off | Print plan, don't call `Export-*` |

### Flow

1. **Connection check.** Probe with a cheap call (e.g. `Get-ConnectionInformation` if available, otherwise a trivial `Get-Label -ResultSize 1`). If not connected, run `Connect-IPPSSession` interactively.
2. **Enumerate tags.** For each requested `TagType`, run the matching cmdlet:

   | TagType | Enumeration cmdlet | Name property |
   |---|---|---|
   | `SensitiveInformationType` | `Get-DlpSensitiveInformationType` | `Name` |
   | `Sensitivity` | `Get-Label` | `DisplayName` |
   | `Retention` | `Get-ComplianceTag` | `Name` |
   | `TrainableClassifier` | `Get-DlpTrainableClassifier` (best guess — verify at runtime) | `Name` |

3. Apply `-NameLike` / `-NameNotLike` filters (PowerShell `-like` semantics, case-insensitive).
4. If `-DryRun`, print the planned `(TagType, TagName)` list with counts and exit.
5. For each `(TagType, TagName)`, invoke the worker. Wrap in `try/catch`. Append a status line to `sweep.log` with timestamp and outcome (`ok`, `skip`, `fail: <message>`).
6. **Roll-up.** After the loop, concatenate every `aggregate_*.csv` in `OutDir` (excluding `aggregate_all.csv` itself) into `aggregate_all.csv`. Each per-tag file already carries `TagType` / `TagName` / `Workload` columns, so the roll-up is a straight concatenation.
7. Print a final summary: `processed=X succeeded=Y skipped=Z failed=W`. Non-zero failure count exits non-zero.

### Trainable Classifier enumeration — open item

The exact cmdlet for listing trainable classifiers in S&C PowerShell is not pinned down in the docs we worked from. The orchestrator handles this defensively:

- On first use it checks for `Get-DlpTrainableClassifier`. If found, use it.
- If not found, print a clear message: "Could not enumerate TrainableClassifier — supply names via `-NameLike` against a known list, or omit `TrainableClassifier` from `-TagTypes`." Skip and continue.

This avoids hard-coding a possibly-wrong cmdlet name and gives the user an actionable workaround.

## Output Format

### Per-tag CSV — `aggregate_<TagType>_<safe-name>.csv`

Columns:
- All columns returned by `Export-ContentExplorerData -Aggregate` (these include the folder identifier — `SiteUrl` for SPO/ODB, `UserPrincipalName` for EXO/Teams — and item count).
- `TagType`, `TagName`, `Workload` (added by worker).

Rows: one per folder/mailbox/site that has at least one item stamped with this tag, across all sweep'd workloads.

### Roll-up — `aggregate_all.csv`

A straight concatenation of every `aggregate_*.csv` under `OutDir` (excluding `aggregate_all.csv` itself). Because the per-tag files already carry `TagType`, `TagName`, and `Workload` columns, no parsing or column injection is needed.

The roll-up is regenerated from per-tag files at the end of every run, so re-running with `-Force` on a single tag and then re-running the sweep yields a consistent merged file.

### `sweep.log`

Plain-text, append-only. One line per worker invocation:
```
2026-04-30T14:32:01Z  ok      SensitiveInformationType  "Credit Card Number"          rows=42
2026-04-30T14:32:08Z  skip    SensitiveInformationType  "U.S. Social Security Number" exists
2026-04-30T14:32:09Z  fail    Sensitivity               "Confidential"                 ConnectionClosed
```

## Authentication

Interactive only. The orchestrator runs `Connect-IPPSSession` once at startup if no session is detected. The user signs in via the modern auth web prompt. No credentials stored.

If the ~1h session token expires mid-sweep, the worker will see API failures, log them per tag, and continue to the next tag. Re-running the orchestrator with default params then picks up only the failed/missing tags (skip-existing on by default).

## Error Handling

- **Per-workload errors inside a tag:** logged to `sweep.log`, other workloads for that tag still attempted.
- **Per-tag errors:** logged, sweep continues with next tag.
- **Enumeration failure for a TagType:** logged, that TagType is skipped, other TagTypes proceed.
- **Connection failure at startup:** hard-fail with a clear message before any work begins.
- **Final exit code:** 0 if `failed=0`, 1 otherwise.

## Testing Approach

This script can only meaningfully be tested against a real M365 tenant — `Export-ContentExplorerData` has no offline equivalent and mocking it would just verify the mock. So:

1. **`-DryRun` smoke test** — run against a real tenant, verify enumeration cmdlets work and tag list looks sensible.
2. **Single-tag worker test** — run worker directly for one well-known SIT (e.g. "Credit Card Number") on one workload, verify CSV shape.
3. **Narrow sweep** — `-TagTypes SensitiveInformationType -NameLike 'Credit*'`, verify per-tag CSVs and roll-up.
4. **Resumability** — interrupt a sweep with Ctrl+C, re-run, verify previously-written tags are skipped.
5. **Full sweep** — only after the above pass.

No automated tests; manual checklist run in the tenant.

## YAGNI / Explicitly Out

- CBA / cert auth.
- Scheduled / unattended runs.
- Auto re-auth.
- Parallelism.
- Item-level export.
- Multi-tenant config files.
- A separate config-file mode (the `-NameLike`/`-NameNotLike` filters cover targeted runs).
