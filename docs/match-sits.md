# match-sits.ps1

Helper. Connects to your tenant, dumps the canonical SIT list, then for each name in your input CSV suggests the closest tenant match using normalized-exact, substring, and Levenshtein-distance fallbacks. Useful when adapting an externally-sourced SIT list (a planning spreadsheet, a Microsoft docs export) to match the canonical names your tenant actually returns.

## Synopsis

```powershell
./scripts/match-sits.ps1
    -NamesFile <string>
    [-NamesColumn <string>]
    [-OutFile <string>]
```

## Parameters

| Name | Type | Default | Notes |
|---|---|---|---|
| `-NamesFile` | `string` | required | Path to a CSV containing the source names |
| `-NamesColumn` | `string` | `Name` | Which column to read names from |
| `-OutFile` | `string` | `/tmp/sit_mappings.csv` | Where to write the mapping CSV |

## Example

```powershell
./scripts/match-sits.ps1 -NamesFile ./my-sits.csv
# 50 of 315 names are non-canonical → printed table + /tmp/sit_mappings.csv
```

## How matching works

For each row's `Name`:

1. **Normalized-exact** — strip non-alphanumerics, lowercase. If equal to a tenant name post-normalization, accept (`exact` or `normalized-exact`).
2. **Substring containment** — if either side contains the other after normalization. Pick the candidate whose length is closest (`substring`).
3. **Levenshtein distance** — compute edit distance against every tenant name; accept the closest if distance ≤ 30% of the source length (`levenshtein-N`).
4. Otherwise → `<<NO MATCH>>`.

## Output format

Printed table and exported CSV:

```text
Source                                       Suggested                              Type
------                                       ---------                              ----
All credentials                              All Credential Types                   levenshtein-7
Australia drivers license number             Australia Driver's License Number      normalized-exact
Germany passport number                      German Passport Number                 levenshtein-1
```

## Caveats

- **Hand-review the Levenshtein matches.** The algorithm picks the closest by edit distance, which can produce false positives where unrelated names happen to be similar. We've seen `Czech passport number` get suggested as `Greece Passport Number` (5 edits, accepted) when the real answer was `Czech Republic Passport Number` (8 edits, rejected by threshold).
- **No automatic apply.** The script only suggests — it never writes back to your source CSV. That's intentional: you should eyeball the suggestions before applying.
- **Auth required.** Connects to Security & Compliance PowerShell on the same `Connect-IPPSSession` flow as the orchestrator.
