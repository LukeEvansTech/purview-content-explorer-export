# PurviewContentExplorerHelpers

Higher-level reporting helpers that sit on top of the exporter in this repository
(`Invoke-CESweep.ps1` / `Export-CEItems.ps1`). The base tool exports raw item-level data
from Microsoft Purview Content Explorer; this module wraps that output to answer common
reporting questions:

- _Where is unlabelled PII sitting?_
- _What's our sensitivity-label coverage by workload?_
- _What changed between two exports?_

These helpers were previously a separate repository (`purview-content-explorer-helpers`)
and were consolidated here so the producer (exporter) and consumer (reporting module) live
together.

## Status

Early — public seed of an ongoing project.

## Install

The module ships inside this repository. Import it by path from the repository root —
PowerShell Gallery publication is pending while it stabilises.

```powershell
Import-Module ./helpers/src/PurviewContentExplorerHelpers.psd1
```

## Quick start

Assuming you have already produced a per-tag CSV export with `Invoke-CESweep.ps1` /
`Export-CEItems.ps1` (see the repository root for usage):

```powershell
# Find PII items that lack any sensitivity label
Find-UnlabeledPII -Path ./output/

# Coverage rates per workload
Get-LabelCoverageByWorkload -Path ./output/

# Delta between two exports
Compare-ExportDelta -Old ./output-2026-04/ -New ./output-2026-05/
```

## Functions

| Function                      | Description                                                                                       |
| ----------------------------- | ------------------------------------------------------------------------------------------------- |
| `Find-UnlabeledPII`           | Returns items containing PII (per the Purview classifier) that have no sensitivity label applied. |
| `Get-LabelCoverageByWorkload` | Returns label-coverage percentage broken down by Exchange / SharePoint / OneDrive / Teams.        |
| `Compare-ExportDelta`         | Diffs two exports — items added, removed, re-classified.                                          |

## Contributing

PRs welcome. See the repository-root [contributing guide](../docs/docs/contributing.md).

## Licence

[MIT](../LICENSE) — same licence as the rest of the repository.
