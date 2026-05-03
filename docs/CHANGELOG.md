# Changelog

All notable changes to this project will be documented in this file. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once it reaches `v1.0.0`.

## [Unreleased]

Pre-release working state. Tag `v1.0.0` once the design has stabilised in real-tenant use.

### Added

- Item-level export via `Export-CEItems.ps1` (worker) and `Invoke-CESweep.ps1` (orchestrator)
- `-NamesFile` CSV-driven include list with unmatched-name reporting
- `match-sits.ps1` helper for canonical-name suggestions (normalized-exact / substring / Levenshtein)
- Pester unit tests for the pure-logic helpers (18 tests, run on Ubuntu / macOS / Windows in CI)
- GitHub Actions workflows for tests, super-linter, and docs deploy
- MkDocs Material documentation site
