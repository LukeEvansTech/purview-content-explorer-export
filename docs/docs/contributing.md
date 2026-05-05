# Contributing

PRs welcome. The codebase is small (two PowerShell scripts + a helper module + Pester tests) and the design rationale is in the git log.

## Architecture

```text
purview-content-explorer-export/
  Export-CEItems.ps1          # worker — one (TagType, TagName), N workloads
  Invoke-CESweep.ps1          # orchestrator — enumerate, filter, dispatch, roll-up
  lib/CEHelpers.psm1          # pure helpers (offline-testable)
  tests/CEHelpers.Tests.ps1   # Pester unit tests
  scripts/match-sits.ps1      # canonical-name fuzzy matcher
  examples/
    items_all.sample.csv               # synthetic sample output
    names-credentials.example.csv      # sample curated SIT list (52 names)
  output/                     # gitignored, created at runtime
```

The orchestrator imports the worker as a script (`& $workerScript ...`) per tag, so each tag is a fresh script execution. Per-workload errors stay inside the worker (logged as warnings, don't abort the tag); per-tag errors stay inside the orchestrator (logged to `sweep.log` as `fail`, don't abort the sweep). Only a wholesale enumeration failure or connection failure aborts the run.

## Running tests locally

```powershell
Invoke-Pester ./tests/CEHelpers.Tests.ps1 -CI
# Expected: Tests Passed: 18
```

Only pure-logic helpers (`Get-CESafeName`, `Test-CETagNameFilter`, `Get-CETagTypeEnumeration`) are unit-tested. Cmdlet integration is covered by manual smoke testing against a real M365 tenant — no offline equivalent exists for `Export-ContentExplorerData` and mocking it would just verify the mock.

## Building docs locally

```bash
pip install -r docs/requirements.txt
mkdocs serve
# open http://127.0.0.1:8000/
```

## CI

Two workflows:

- **`test.yml`** — Pester on Ubuntu / macOS / Windows + parse-check on every script
- **`lint.yml`** — Super-Linter v8 (PSScriptAnalyzer / yamllint / markdownlint / gitleaks / actions-lint)
- **`docs.yml`** — Builds and deploys this site to GitHub Pages on every push to main

## House rules

1. Keep `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` in both top-level scripts.
2. Add Pester tests for any new pure-logic helper added to `lib/CEHelpers.psm1`.
3. Don't introduce a dependency on a third-party PowerShell module that isn't already required (e.g. don't pull in `ImportExcel` — read CSVs).
4. If you fix a footgun, add a one-line note in [Troubleshooting](troubleshooting.md) so the next person doesn't hit it.
5. PRs should be green on `test.yml` and `lint.yml` before review.

## Reporting issues

Please include:

1. Output of `pwsh --version`
2. Output of `Get-Module ExchangeOnlineManagement -ListAvailable | Select-Object Name,Version`
3. The exact command you ran
4. The first ~50 lines of the failure (or a summary if it's the same per-tag error 200 times)

For tenant-side issues (e.g. cmdlets behaving differently than documented), include your tenant region if you're comfortable sharing — the cmdlet has known regional quirks.
