# Recovery & resumability

The `Connect-IPPSSession` token lives ~60 minutes. Sweeps wider than ~50 SITs almost certainly run longer than that, so you *will* hit token expiry mid-sweep.

## What happens at token expiry

When the token expires, the worker fails every workload for the current and subsequent tags with a `server-side error` or null-response. Each failed tag is logged to `sweep.log` as `fail`:

```text
2026-04-30T14:32:09Z  fail    SensitiveInformationType   "Azure Storage Account Key"   ...
```

The sweep keeps running until it's processed every tag in the inventory, so you'll see a wave of failures rather than a hang.

## How to resume

Re-authenticate and re-run the same command. **Skip-existing** means tags whose per-tag CSV already exists are silently skipped, so the sweep picks up where it left off:

```powershell
Connect-IPPSSession                                    # re-auth
./Invoke-CESweep.ps1 -NamesFile ./my-sits.csv          # resume
```

Use `-Force` only if you actually want to re-export tags that already have a CSV (e.g. you're re-running after a tenant policy change).

## Exit codes

The orchestrator exits with code 1 if any tag failed in the run, 0 otherwise. Useful for CI-style automation:

```bash
./Invoke-CESweep.ps1 -NamesFile ./my-sits.csv
if [ $? -ne 0 ]; then
    echo "some tags failed — re-run after re-auth"
fi
```

## Long-running unattended sweeps

For a fully unattended sweep (e.g. nightly), look at certificate-based authentication (CBA) with an Azure app registration assigned the **Content Explorer List Viewer** role group on its Service Principal. CBA tokens last much longer than interactive sign-in. This tool currently only supports interactive auth out of the box — extending it to CBA is a small change at the top of `Invoke-CESweep.ps1`.

See Microsoft's docs on [App-only authentication for Exchange Online PowerShell](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2) for the setup.

## Resumability internals

The skip-existing check is purely filename-based:

```text
output/items_<TagType>_<safe-name>.csv
```

If that file exists for a tag, the orchestrator emits a `skip` line and moves on — no API call, no auth needed. Tags that errored never wrote a per-tag CSV, so they're naturally retried.

This means you can also pre-seed `output/` with placeholder files to skip specific tags, or `rm` a single file to force re-export of just that one without using `-Force`.
