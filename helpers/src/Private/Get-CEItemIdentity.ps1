function Get-CEItemIdentity {
    <#
    .SYNOPSIS
        Derive a stable per-item identity string from an exporter CSV row.

    .DESCRIPTION
        The cmdlet's Location column duplicates Workload (see docs/docs/output-schema.md), so it
        cannot identify an item. The real identity is:

        - FileUrl when present and non-empty (SPO/ODB rows carry the full file path);
        - otherwise 'FileSourceUrl|FileName' (EXO rows: mailbox UPN + subject; Teams rows:
          poster UPN + "Posted in #channel").

        Returns $null when neither is derivable - callers skip such rows. Uses the StrictMode-safe
        PSObject.Properties indexer, so rows from CSVs lacking these columns simply yield $null.

        Note the EXO/Teams fallback key is as fine-grained as the export allows: two emails in the
        same mailbox with an identical subject share a key and are treated as one item.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Row
    )

    $fileUrl = $Row.PSObject.Properties['FileUrl']
    if ($fileUrl -and -not [string]::IsNullOrEmpty([string]$fileUrl.Value)) {
        return [string]$fileUrl.Value
    }

    $src  = $Row.PSObject.Properties['FileSourceUrl']
    $name = $Row.PSObject.Properties['FileName']
    $srcValue  = if ($src)  { [string]$src.Value }  else { '' }
    $nameValue = if ($name) { [string]$name.Value } else { '' }
    if ([string]::IsNullOrEmpty($srcValue) -and [string]::IsNullOrEmpty($nameValue)) {
        return $null
    }
    return ('{0}|{1}' -f $srcValue, $nameValue)
}
