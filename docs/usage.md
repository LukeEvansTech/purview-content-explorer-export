# Common scenarios

## Sweep a curated subset of SITs

Most users don't want all 300+ tenant SITs — they want the ~50 they actually have policies for. Maintain a CSV with a `Name` column and pass it via `-NamesFile`:

```powershell
./Invoke-CESweep.ps1 -NamesFile ./my-sits.csv
```

The example file `examples/names-credentials.example.csv` is a 52-name credentials-focused list (Tier 1 generic credential detectors + Tier 2 cloud provider secrets). Use it directly or as a template:

```powershell
./Invoke-CESweep.ps1 -NamesFile ./examples/names-credentials.example.csv
```

The orchestrator reads the `Name` column by default. Override with `-NamesColumn`:

```powershell
./Invoke-CESweep.ps1 -NamesFile ./list.csv -NamesColumn 'SIT Name'
```

After enumeration, names from your file that didn't match anything in the tenant are listed as a warning — useful for spotting typos or names that exist in your list but not in this tenant.

!!! warning "Names need to match the tenant exactly"
    SIT lists exported from Microsoft documentation, planning spreadsheets, or DLP policy templates often use *almost* the right names. The orchestrator's `-NameLike` is case-insensitive, so case differences resolve automatically — but `All credentials` vs `All Credential Types` is a real semantic mismatch and won't match. See [Working with non-canonical names](name-matching.md).

## Other tag types

```powershell
# Sensitivity labels only
./Invoke-CESweep.ps1 -TagTypes Sensitivity

# Multiple tag types
./Invoke-CESweep.ps1 -TagTypes SensitiveInformationType,Sensitivity,Retention

# Trainable classifiers (note: the cmdlet name varies by tenant)
./Invoke-CESweep.ps1 -TagTypes TrainableClassifier
```

## Narrow by name pattern

```powershell
# All SITs whose name starts with "Credit"
./Invoke-CESweep.ps1 -NameLike 'Credit*'

# Sweep everything except the named patterns
./Invoke-CESweep.ps1 -NameNotLike 'Default *','General','Public'
```

## Subset of workloads

```powershell
./Invoke-CESweep.ps1 -Workloads EXO,SPO
```

## Force / resume

```powershell
# Re-run is safe — tags whose per-tag CSV already exists are skipped.
./Invoke-CESweep.ps1

# Force a complete re-export, overwriting existing CSVs.
./Invoke-CESweep.ps1 -Force
```

## One tag, by hand

```powershell
./Export-CEItems.ps1 -TagType SensitiveInformationType -TagName 'Credit Card Number'
```

## Combine filters

`-NamesFile` replaces `-NameLike` when set. To narrow further by workload:

```powershell
./Invoke-CESweep.ps1 -NamesFile ./examples/names-credentials.example.csv -Workloads ODB,SPO
```

To exclude noisy tags from a curated list:

```powershell
./Invoke-CESweep.ps1 -NamesFile ./my-sits.csv -NameNotLike 'All Full Names','All Physical Addresses'
```
