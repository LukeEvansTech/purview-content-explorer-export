# purview-content-explorer-helpers

Higher-level helpers built on top of [`LukeEvansTech/purview-content-explorer-export`](https://github.com/LukeEvansTech/purview-content-explorer-export). The base tool exports raw item-level data from Microsoft Purview Content Explorer; this repository wraps the output to answer common reporting questions:

- _Where is unlabelled PII sitting?_
- _What's our sensitivity-label coverage by workload?_
- _What changed between two exports?_

## Status

Early — public seed of an ongoing project.

## Install

Reference the module locally — PowerShell Gallery publication is pending while it stabilises.

```powershell
git clone https://github.com/LukeEvansTech/purview-content-explorer-helpers.git
cd purview-content-explorer-helpers
Import-Module ./src/PurviewContentExplorerHelpers.psd1
```

## Quick start

Assuming you have already produced a per-tag CSV export with `purview-content-explorer-export`:

```powershell
# Find PII items that lack any sensitivity label
Find-UnlabeledPII -Path ./exports/2026-05/

# Coverage rates per workload
Get-LabelCoverageByWorkload -Path ./exports/2026-05/

# Delta between two exports
Compare-ExportDelta -Old ./exports/2026-04/ -New ./exports/2026-05/
```

## Functions

| Function                      | Description                                                                                       |
| ----------------------------- | ------------------------------------------------------------------------------------------------- |
| `Find-UnlabeledPII`           | Returns items containing PII (per the Purview classifier) that have no sensitivity label applied. |
| `Get-LabelCoverageByWorkload` | Returns label-coverage percentage broken down by Exchange / SharePoint / OneDrive / Teams.        |
| `Compare-ExportDelta`         | Diffs two exports — items added, removed, re-classified.                                          |

## Contributing

PRs welcome. See [CONTRIBUTING](.github/CONTRIBUTING.md).

## Licence

[MIT](LICENSE).
