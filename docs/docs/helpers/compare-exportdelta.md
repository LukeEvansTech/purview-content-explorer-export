# Compare-ExportDelta

Diff two export runs and surface items that appeared, disappeared, or moved between tags. Part of the `PurviewContentExplorerHelpers` module - it reads two folders of per-tag CSV output and calls no Purview cmdlet.

Everything is derived from row data, never from filenames:

- **Item identity** (the join key) is `FileUrl` (SPO/ODB), falling back to `FileSourceUrl`+`FileName` (EXO/Teams). The cmdlet's `Location` column duplicates `Workload` and is not an item identity.
- Each item's tag set is the rows' `TagType`/`TagName` values (formatted `TagType/TagName`), so a renamed CSV is not reported as a change.

## Synopsis

```powershell
Compare-ExportDelta
    -Old <string>
    -New <string>
```

## Parameters

| Name | Type | Default | Notes |
|---|---|---|---|
| `-Old` | `string` | required | Folder containing the earlier export |
| `-New` | `string` | required | Folder containing the later export |

## Examples

```powershell
Import-Module ./helpers/src/PurviewContentExplorerHelpers.psd1

# What changed between two monthly runs?
Compare-ExportDelta -Old ./output-2026-04/ -New ./output-2026-05/ | Format-Table

# Only items that lost or gained a tag
Compare-ExportDelta -Old ./output-2026-04/ -New ./output-2026-05/ |
    Where-Object Change -eq 'Reclassified'
```

## Output

One `PSCustomObject` per changed item (unchanged items are omitted):

| Property | Notes |
|---|---|
| `Item` | The item identity - `FileUrl`, or `FileSourceUrl` joined to `FileName` for EXO/Teams |
| `Change` | `Added` (only in new), `Removed` (only in old), or `Reclassified` (tag set differs) |
| `OldTags` | `TagType/TagName` values in the old export, comma-separated |
| `NewTags` | `TagType/TagName` values in the new export, comma-separated |

## Notes

- Comparison is by tag membership, not row content - an item is `Reclassified` when the set of tags it appears under changes (for example it gained a sensitivity label or dropped a SIT match).
- Item-identity and tag matching are case-insensitive, so URL- or name-casing drift between runs is not reported as a change.
- The `items_all.csv` roll-up is skipped in both folders (it duplicates every per-tag row) unless it is the only CSV present. Files lacking the `TagType`/`TagName` columns and rows with no derivable item identity are ignored.
