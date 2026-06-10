# Compare-ExportDelta

Diff two export runs and surface items that appeared, disappeared, or moved between tags. Part of the `PurviewContentExplorerHelpers` module — it reads two folders of per-tag CSV output and calls no Purview cmdlet.

`Location` is the join key. Each item's tag set is taken from the rows' `TagType` / `TagName` columns (formatted `TagType/TagName`), falling back to the CSV filename for rows that lack those columns — so the diff is independent of how the files are named (a renamed export is not reported as a change).

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
| `Location` | The item identity / path |
| `Change` | `Added` (only in new), `Removed` (only in old), or `Reclassified` (tag set differs) |
| `OldTags` | `TagType/TagName` values in the old export, comma-separated |
| `NewTags` | `TagType/TagName` values in the new export, comma-separated |

## Notes

- Comparison is by tag membership, not row content — an item is `Reclassified` when the set of tags it appears under changes (for example it gained a sensitivity label or dropped a SIT match).
- Rows without a `Location` value are ignored in both folders.
