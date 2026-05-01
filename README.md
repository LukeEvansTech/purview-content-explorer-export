# tbcontentexplorer

PowerShell tool for sweeping Microsoft Purview Content Explorer aggregate data
across all tags and workloads.

## Quick start

```powershell
# Connect interactively (one-time per session)
Connect-IPPSSession

# Dry-run to see what would be swept
./Invoke-CEAggregateSweep.ps1 -DryRun

# Full sweep with defaults
./Invoke-CEAggregateSweep.ps1

# Narrow to one tag type
./Invoke-CEAggregateSweep.ps1 -TagTypes SensitiveInformationType -NameLike 'Credit*'
```

See `docs/superpowers/specs/` for the design.
