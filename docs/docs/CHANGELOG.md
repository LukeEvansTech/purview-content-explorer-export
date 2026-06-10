# Changelog

All notable changes to this project will be documented in this file. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once it reaches `v1.0.0`.

## [Unreleased]

Prerelease working state. Tag `v1.0.0` once the design has stabilised in real-tenant use.

### Added

- Item-level export via `Export-CEItems.ps1` (worker) and `Invoke-CESweep.ps1` (orchestrator)
- `-NamesFile` CSV-driven include list with unmatched-name reporting
- `match-sits.ps1` helper for canonical-name suggestions (normalized-exact / substring / Levenshtein)
- Pester unit tests for the pure-logic helpers (run on Ubuntu / macOS / Windows in CI)
- GitHub Actions workflows for tests, super-linter, and docs deploy
- MkDocs Material documentation site
- `TargetConfidence` and `ItemMaxConfidence` output columns — sortable `3-High`/`2-Medium`/`1-Low`/`0-None` labels distilled from `SensitiveInfoTypesData`, so you can filter/rank the most confident matches without parsing JSON (`ItemMaxConfidence` is the reliable signal for bundle SITs)
- `SensitiveInfoTypeNames` output column — resolves the `SensitiveInfoTypes` GUIDs to friendly SIT names (same order), so the detection detail is readable without manual GUID lookups
- `PurviewContentExplorerHelpers` reporting module under `helpers/` (`Find-UnlabeledPII`, `Get-LabelCoverageByWorkload`, `Compare-ExportDelta`) — consolidated in from the former standalone `purview-content-explorer-helpers` repository, with its function docs folded into the docs site and offline Pester coverage in `tests/Helpers.Tests.ps1`

### Changed

- Lowered the `#Requires` floor from PowerShell 7.0 to 5.1 so the scripts run on stock Windows PowerShell 5.1. Made the pipeline `.Count` checks and CSV reads array-safe (`@(...)`) for strict-mode parity across 5.1 and 7. On 5.1, CSV output carries a UTF-8 BOM.

### Fixed

- Worker crashed on Windows PowerShell 5.1 (`Cannot convert "System.Object[]" to "System.Int32"`) for items carrying multiple SITs. On 5.1, piping a top-level JSON array through `ConvertFrom-Json` emits the whole array as one object (PowerShell 7 unrolls it), collapsing the per-SIT entries in `Get-CEConfidenceSummary`. Fixed by capturing the parse to a variable before filtering.
- The `helpers/` reporting functions now identify labels and PII from each row's `TagType` / `TagName` / `Workload` columns instead of inferring tags from the CSV filename. The old filename match never matched the exporter's real `items_<TagType>_<safeName>.csv` output, so `Find-UnlabeledPII` and `Get-LabelCoverageByWorkload` silently found no labels end-to-end.
- `Get-LabelCoverageByWorkload` now de-duplicates items by `(Workload, Location)`, so an item matching several tags is counted once rather than inflating the totals.
- `Compare-ExportDelta` threw `Cannot find an overload for "new"` on any non-empty export because a hashtable's `.Keys` (non-generic `IEnumerable`) was passed straight to the `HashSet[string]` constructor; the keys are now cast to `[string[]]` first. It also keys an item's tag set off `TagType/TagName` rather than the filename, so a renamed export is no longer reported as a change.

[Unreleased]: https://github.com/LukeEvansTech/purview-content-explorer-export/commits/main/
