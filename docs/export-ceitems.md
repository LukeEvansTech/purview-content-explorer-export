# Export-CEItems.ps1

The worker. Handles a single `(TagType, TagName)` across one or more workloads — calls `Export-ContentExplorerData` with pagination and writes one CSV per call.

You normally don't call this directly; the orchestrator dispatches it. But it's runnable on its own for one-off exports.

## Synopsis

```powershell
./Export-CEItems.ps1
    -TagType <string>
    -TagName <string>
    [-Workloads <string[]>]
    [-OutDir <string>]
    [-PageSize <int>]
    [-Force]
```

## Parameters

| Name | Type | Default | Notes |
|---|---|---|---|
| `-TagType` | `string` | required | One of `Retention`, `SensitiveInformationType`, `Sensitivity`, `TrainableClassifier` |
| `-TagName` | `string` | required | Passed verbatim to `Export-ContentExplorerData` |
| `-Workloads` | `string[]` | `EXO,ODB,SPO,Teams` | Subset to query |
| `-OutDir` | `string` | `./output` | Where the per-tag CSV is written |
| `-PageSize` | `int` | `1000` | 1–10000, passed to `Export-ContentExplorerData -PageSize` |
| `-Force` | `switch` | off | Overwrite existing per-tag CSV |

## Examples

```powershell
# One SIT, all four workloads
./Export-CEItems.ps1 -TagType SensitiveInformationType -TagName 'Credit Card Number'

# One SIT, just Exchange
./Export-CEItems.ps1 -TagType SensitiveInformationType -TagName 'Credit Card Number' -Workloads EXO

# Re-export an existing tag
./Export-CEItems.ps1 -TagType Sensitivity -TagName 'Confidential' -Force
```

## Behaviour

1. **Skip-existing.** If `output/items_<TagType>_<safe-name>.csv` already exists and `-Force` is not set, log "skip (exists)" and return immediately.
2. **Per-workload loop.** For each workload in `-Workloads`:
    a. First call: `Export-ContentExplorerData -TagType $T -TagName $N -Workload $W -PageSize $P -ErrorAction Stop`.
    b. While `MorePagesAvailable` is `True`, repeat with `-PageCookie`.
    c. For each returned record, prepend `TagType` / `TagName` / `Workload` columns.
3. **Per-workload error handling.** Errors are caught and warning-logged (`workload=<X> failed: <message>`). The loop continues to the next workload.
4. **All-workloads-errored detection.** If every attempted workload threw, the worker re-throws so the orchestrator records the tag as `fail` rather than misleadingly reporting `succeeded with 0 rows`.
5. **Empty-result handling.** If all workloads succeeded but returned 0 rows, write a header-only marker file so skip-existing on re-run leaves it alone.
6. **Write.** All collected rows go into the per-tag CSV (UTF-8, no type info).

## Edge cases handled

- **`Export-ContentExplorerData` returns null** — happens when the cmdlet emits `Write-Error` without throwing terminating (we've seen this with "A server side error has occurred"). The worker checks `$null -eq $response` before indexing and surfaces a clearer message via the catch path.
- **`1..0` array-range trap** — when `RecordsReturned` is 0, naive code would index `$response[1..0]` which in PowerShell is `[1, 0]` (a length-2 array of two indexes), not empty. The worker explicitly guards with `if ($recordsReturned -gt 0)`.
- **Filename safe-name collisions** — two tag names that normalize to the same safe-name (e.g. `Credit/Debit Card` and `Credit-Debit Card` both → `Credit_Debit_Card`) would overwrite the same CSV. Rare in practice; not currently handled. The orchestrator's `(TagType, TagName)` dedupe doesn't catch this case.
