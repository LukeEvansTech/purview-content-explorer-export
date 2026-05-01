# CEHelpers.psm1 — pure helper functions for Content Explorer sweep scripts.
# Cmdlet-calling logic lives in the top-level scripts; this module is offline-testable.

function Get-CESafeName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [AllowEmptyString()]
        [string]$Name
    )
    return [regex]::Replace($Name, '[^A-Za-z0-9._-]', '_')
}

Export-ModuleMember -Function Get-CESafeName
