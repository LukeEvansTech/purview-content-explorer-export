#!/usr/bin/env pwsh
#Requires -Version 7.0
param(
    [string]$Source = '/Users/luke.evans/Scratch/tbsits/SITs.csv',
    [string]$Output = '/Users/luke.evans/Scratch/tbcontentexplorer/sits-corrected.csv'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Final canonical mapping: source-CSV name → tenant canonical name.
$map = @{
    'Australia drivers license number'                                = 'Australia Driver''s License Number'
    'Austria drivers license number'                                  = 'Austria Driver''s License Number'
    'Austria value added tax'                                         = 'Austria Value Added Tax (VAT) Number'
    'Cyprus drivers license number'                                   = 'Cyprus Driver''s License Number'
    'EU Tax identification number'                                    = 'EU Tax Identification Number (TIN)'
    'France tax identification number'                                = 'France Tax Identification Number (numéro SPI.)'
    'Indonesia driver''s license number'                              = 'Indonesia Drivers License Number'
    'Israel national identification number'                           = 'Israel National ID'
    'Philippines national identification number'                      = 'Philippines National ID'
    'Poland passport number'                                          = 'Poland Passport'
    'Taiwan national identification number'                           = 'Taiwan National ID'
    'Taiwan-resident certificate (ARC/TARC) number'                   = 'Taiwan Resident Certificate (ARC/TARC)'
    'U.A.E. identity card number'                                     = 'UAE Identity Card Number'
    'U.A.E. passport number'                                          = 'UAE Passport Number'
    'U.S./U.K. passport number'                                       = 'U.S. / U.K. Passport Number'
    'All credentials'                                                 = 'All Credential Types'
    'Australia business number'                                       = 'Australian Business Number'
    'Australia company number'                                        = 'Australian Company Number'
    'Brazil national identification card (RG)'                        = 'Brazil National ID Card (RG)'
    'Czech passport number'                                           = 'Czech Republic Passport Number'
    'EU social security number or equivalent identification'          = 'EU Social Security Number (SSN) or Equivalent ID'
    'Germany driver''s license number'                                = 'German Driver''s License Number'
    'Germany passport number'                                         = 'German Passport Number'
    'Greece tax identification number'                                = 'Greek Tax identification Number'
    'Hungary social security number (TAJ)'                            = 'Hungarian Social Security Number (TAJ)'
    'Hungary value added tax number'                                  = 'Hungarian Value Added Tax Number'
    'Japan My Number - Corporate'                                     = 'Japanese My Number Corporate'
    'Japan My Number - Personal'                                      = 'Japanese My Number Personal'
    'Japan residence card number'                                     = 'Japanese Residence Card Number'
    'Luxemburg driver''s license number'                              = 'Luxembourg Driver''s License Number'
    'Luxemburg national identification number (natural persons)'      = 'Luxembourg National Identification Number (Natural persons)'
    'Luxemburg national identification number (non-natural persons)'  = 'Luxembourg National Identification Number (Non-natural persons)'
    'Luxemburg passport number'                                       = 'Luxembourg Passport Number'
    'Luxemburg physical addresses'                                    = 'Luxembourg Physical Addresses'
    'Malaysia identification card number'                             = 'Malaysia Identity Card Number'
    'Malta tax identification number'                                 = 'Malta Tax ID Number'
    'Medical specialities'                                            = 'Medical Specialties'
    'New Zealand driver''s license number'                            = 'New Zealand Driver License Number'
    'Norway identification number'                                    = 'Norway Identity Number'
    'Philippines unified multi-purpose identification number'         = 'Philippines Unified Multi-Purpose ID Number'
    'Poland REGON number'                                             = 'Polish REGON Number'
    'Portugal physical addresses'                                     = 'Portuguese Physical Addresses'
    'Qatari identification card number'                               = 'Qatari ID Card Number'
    'Romania personal numeric code (CNP)'                             = 'Romania Personal Numerical Code (CNP)'
    'Russia passport number domestic'                                 = 'Russian Passport Number (Domestic)'
    'Russia passport number international'                            = 'Russian Passport Number (International)'
    'Switzerland SSN AHV number'                                      = 'Swiss Social Security Number AHV'
    'Turkey national identification number'                           = 'Turkish National Identification number'
    'Ukraine passport domestic'                                       = 'Ukraine Passport Number (Domestic)'
    'Ukraine passport international'                                  = 'Ukraine Passport Number (International)'
}
Write-Host "applying $($map.Count) name corrections"

# Read raw CSV (handling '#' header issue)
$rawLines = Get-Content -Path $Source
$headers = $rawLines[0].Split(',') | ForEach-Object { ($_ -replace '^"|"$', '').Trim() }
$rows = $rawLines | Select-Object -Skip 1 | ConvertFrom-Csv -Header $headers

$changedCount = 0
foreach ($row in $rows) {
    if ($map.ContainsKey($row.Name)) {
        $row.Name = $map[$row.Name]
        $changedCount++
    }
}
Write-Host "changed $changedCount row(s)"

# Write back without the '#' column header issue (rename '#' to 'Index' so re-imports work)
$newHeaders = $headers | ForEach-Object { if ($_ -eq '#') { 'Index' } else { $_ } }
$rows | Select-Object -Property $newHeaders | Export-Csv -Path $Output -NoTypeInformation -Encoding UTF8
Write-Host "wrote $Output"
