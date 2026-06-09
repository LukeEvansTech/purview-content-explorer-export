@{
    RootModule        = 'PurviewContentExplorerHelpers.psm1'
    ModuleVersion     = '0.0.1'
    GUID              = 'd3a9b2f4-6c8e-4e1b-9b7d-2c8e1f5a6b3c'
    Author            = 'Luke Evans'
    CompanyName       = 'LukeEvansTech'
    Copyright         = '(c) 2026 Luke Evans. All rights reserved.'
    Description       = 'Higher-level helpers for Microsoft Purview Content Explorer exports produced by purview-content-explorer-export.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @(
        'Find-UnlabeledPII',
        'Get-LabelCoverageByWorkload',
        'Compare-ExportDelta'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData = @{
        PSData = @{
            Tags        = @('Microsoft365', 'Purview', 'Compliance', 'DLP', 'Reporting')
            LicenseUri  = 'https://github.com/LukeEvansTech/purview-content-explorer-helpers/blob/main/LICENSE'
            ProjectUri  = 'https://github.com/LukeEvansTech/purview-content-explorer-helpers'
            ReleaseNotes = 'Initial public seed.'
        }
    }
}
