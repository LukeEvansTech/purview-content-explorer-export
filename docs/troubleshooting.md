# Troubleshooting

Real footguns we hit during development and how the code handles each. If you hit something not on this list, please [open an issue](https://github.com/LukeEvansTech/purview-content-explorer-export/issues).

## Connection probe fails with "parameter cannot be found" on `Get-Label -ResultSize 1`

**Fixed in current code.** `-ResultSize` is an Exchange-cmdlet convention; `Get-Label` (a Security & Compliance cmdlet) doesn't accept it. The connection probe now tries `Get-ConnectionInformation` first and falls back to plain `Get-Label | Select-Object -First 1`.

## `Connect-IPPSSession` hangs / browser window doesn't appear

The popup sometimes hides behind other windows or doesn't focus. If after 60s nothing has happened, kill the pwsh process and try again. As an alternative, use device-code auth — prints a code in the terminal that you paste into [microsoft.com/devicelogin](https://microsoft.com/devicelogin):

```powershell
Connect-IPPSSession -UseDeviceAuthentication
```

## `Cannot index into a null array` from the worker

**Fixed in current code.** Happens when `Export-ContentExplorerData` emits `Write-Error` without throwing terminating, leaving `$response` null. The worker defensively checks for null and surfaces a clearer message ("server-side error the cmdlet did not throw").

The most common cause is a `TagName` that doesn't actually exist in the tenant for the requested workload — verify enumeration coverage with `-DryRun`.

## `The property 'Count' cannot be found on this object`

**Fixed in current code.** Caused by `Set-StrictMode -Version Latest` rejecting member-access enumeration on a scalar `FileInfo`. The roll-up wraps `Get-ChildItem` in `@(...)` to force-array.

## CSV with a `#` column header silently loses the header

**Fixed in current code.** `Import-Csv` treats lines starting with `#` as comments. The orchestrator now reads the header line manually and feeds it to `ConvertFrom-Csv -Header`, bypassing the comment behaviour.

## Trainable Classifier enumeration: "cmdlet 'Get-DlpTrainableClassifier' not available"

The cmdlet name for listing trainable classifiers varies by tenant rollout. The orchestrator detects this and prints a warning, skipping that tag type. Workarounds:

1. Supply names via `-NameLike` against a known list of classifier names.
2. Drop `TrainableClassifier` from `-TagTypes`.

## `WARNING: The TotalCount value might be different from the total number of items returned`

Benign warning emitted by `Export-ContentExplorerData` on every call. Ignore. To silence, edit the worker to add `-WarningAction SilentlyContinue` to the cmdlet call.

## Sweep is much slower than expected

Typical pace is **30–90 seconds per tag** depending on result size. Token expiry blocks sweeps at the ~60-min boundary.

If a tag with many thousands of items is taking many minutes, that's expected — the cmdlet paginates 10k items per call and large SITs (`All Credential Types`, `Client Secret / API Key`) genuinely have a lot of pages.

Use `-NamesFile` with a curated list to avoid sweeping high-volume SITs you don't care about.

## Roll-up `items_all.csv` has missing columns from some per-tag files

**Fixed in current code.** Earlier versions used `Import-Csv | Export-Csv` which adopts the first object's schema and silently drops columns from later objects. The current code computes a column union before re-emitting.

## Pester not installed

The CI workflow installs Pester 5+ automatically. For local development:

```powershell
Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck
Invoke-Pester ./tests/CEHelpers.Tests.ps1 -CI
```

## I want only certain `(TagType, TagName)` pairs

Use a `-NamesFile`. The orchestrator reads the `Name` column and treats each value as a `-NameLike` pattern. See [Common scenarios](usage.md#sweep-a-curated-subset-of-sits).

## Names from my CSV don't match the tenant

See [Working with non-canonical names](name-matching.md). The `match-sits.ps1` helper suggests canonical replacements.
