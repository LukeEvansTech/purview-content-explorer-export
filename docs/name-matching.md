# Working with non-canonical SIT names

A common gotcha: SIT lists exported from Microsoft documentation, planning spreadsheets, or DLP policy templates often use *almost* the right names. Examples we've hit in real tenants:

| What the spreadsheet says | What the tenant actually returns |
|---|---|
| `All credentials` | `All Credential Types` |
| `Australia drivers license number` | `Australia Driver's License Number` |
| `Germany passport number` | `German Passport Number` |
| `Luxemburg passport number` | `Luxembourg Passport Number` |
| `U.A.E. identity card number` | `UAE Identity Card Number` |
| `Switzerland SSN AHV number` | `Swiss Social Security Number AHV` |

The orchestrator's `-NameLike` is case-insensitive (PowerShell `-like`), so case differences resolve automatically. But `All credentials` vs `All Credential Types` is a real semantic mismatch and won't match.

## How the orchestrator surfaces this

After enumeration, names from your `-NamesFile` that didn't match anything in the tenant are listed as a warning:

```text
loaded 315 name(s) from /path/to/sits.csv (column 'Name')
enumerating SensitiveInformationType via Get-DlpSensitiveInformationType...
found 265 tag(s) after filtering:
  SensitiveInformationType: 265
WARNING: 50 of 315 name(s) from '/path/to/sits.csv' did not match any tenant tag:
  unmatched: All credentials
  unmatched: Australia drivers license number
  ...
```

That's your hit-list of corrections to make.

## Using `match-sits.ps1` to suggest fixes

The companion script `scripts/match-sits.ps1` connects to your tenant, dumps the canonical SIT list, and for each name in your input CSV suggests the closest tenant match using:

1. **Normalized-exact** — case-insensitive, no punctuation
2. **Substring** — one name contains the other after normalization
3. **Levenshtein distance** — accepts when the edit distance is ≤ 30% of the source length

```powershell
./scripts/match-sits.ps1 -NamesFile ./my-sits.csv
# Inspect the printed suggestions and /tmp/sit_mappings.csv (configurable
# with -OutFile), hand-curate, then save back to your source CSV.
```

The suggestion list will include the match type so you can see how confident each one is:

```text
Source                                       Suggested                              Type
------                                       ---------                              ----
All credentials                              All Credential Types                   levenshtein-7
Australia drivers license number             Australia Driver's License Number      normalized-exact
Germany passport number                      German Passport Number                 levenshtein-1
```

!!! warning "Hand-review the Levenshtein matches"
    Levenshtein can produce false positives where two unrelated names happen to be a few edits apart. We've seen `Czech passport number` get suggested as `Greece Passport Number` (5 edits) when the real match was `Czech Republic Passport Number` (8 edits — beyond the threshold). Always sanity-check the country/category prefix before accepting a suggestion.

## Why we don't just normalize at sweep time

The orchestrator could in principle normalize both sides before comparing — strip punctuation, lowercase, even apply a Germany→German synonym table. We chose not to:

- **Predictability.** What you put in `-NamesFile` is what gets swept; the orchestrator never silently maps your input to something different.
- **Visibility of typos.** If you misspell `Crdit Card Number`, you want a warning, not a silent match to something close-but-wrong.
- **Tenant variation.** The canonical name for one TagType in one tenant may not be the canonical name in another. The matcher script lets you snapshot canonical names per-tenant and curate accordingly.
