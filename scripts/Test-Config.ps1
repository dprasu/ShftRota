<#
.SYNOPSIS
    Validates ShftRota configuration files.
.DESCRIPTION
    Checks that settings.json and team-roster.csv are valid,
    all regions referenced in the roster exist in settings,
    and each region has an even number of members (for pair rotation).
.EXAMPLE
    .\Test-Config.ps1
#>
[CmdletBinding()]
param()

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = $PSScriptRoot }
$errors   = @()
$warnings = @()

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║  🔍  ShftRota Config Validator            ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ---- settings.json ----
$settingsPath = Join-Path $root "config\settings.json"
if (-not (Test-Path $settingsPath)) {
    $errors += "config/settings.json not found"
} else {
    try {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
        Write-Host "  ✅ settings.json — parsed OK" -ForegroundColor Green

        $regionKeys = @($settings.regions | ForEach-Object { $_.key })
        Write-Host "     Regions: $($regionKeys -join ', ')" -ForegroundColor DarkGray

        if (-not $settings.rotation.anchorDate) { $errors += "Missing rotation.anchorDate" }
        if (-not $settings.escalation.minutes)  { $warnings += "escalation.minutes not set, will default to 15" }

        foreach ($r in $settings.regions) {
            if (-not $r.weekday.startUTC -and $r.weekday.startUTC -ne 0) { $errors += "Region $($r.key) missing weekday.startUTC" }
            if (-not $r.weekend.startUTC -and $r.weekend.startUTC -ne 0) { $errors += "Region $($r.key) missing weekend.startUTC" }
        }
    } catch {
        $errors += "settings.json parse error: $_"
    }
}

# ---- team-roster.csv ----
$rosterPath = Join-Path $root "config\team-roster.csv"
if (-not (Test-Path $rosterPath)) {
    $errors += "config/team-roster.csv not found"
} else {
    $roster = Import-Csv $rosterPath
    $count  = ($roster | Measure-Object).Count
    Write-Host "  ✅ team-roster.csv — $count engineers loaded" -ForegroundColor Green

    # Check required columns
    $requiredCols = @('name', 'initials', 'email', 'phone', 'region', 'weekday_shift')
    $actualCols   = $roster[0].PSObject.Properties.Name
    foreach ($col in $requiredCols) {
        if ($col -notin $actualCols) { $errors += "CSV missing column: $col" }
    }

    # Check region membership
    $regionGroups = $roster | Group-Object -Property region
    foreach ($g in $regionGroups) {
        $regionName = $g.Name
        Write-Host "     $regionName : $($g.Count) engineers" -ForegroundColor DarkGray

        if ($regionKeys -and $regionName -notin $regionKeys) {
            $errors += "Region '$regionName' in CSV not found in settings.json regions"
        }
        if ($g.Count % 2 -ne 0) {
            $warnings += "Region '$regionName' has $($g.Count) members (odd) — last person has no backup pair"
        }
    }

    # Check for duplicates
    $dupes = $roster | Group-Object -Property name | Where-Object { $_.Count -gt 1 }
    foreach ($d in $dupes) { $errors += "Duplicate name: $($d.Name)" }

    # Check for empty fields
    foreach ($r in $roster) {
        if (-not $r.name)     { $errors += "Empty name found in CSV row" }
        if (-not $r.initials) { $warnings += "Missing initials for $($r.name)" }
        if (-not $r.email)    { $warnings += "Missing email for $($r.name)" }
    }
}

# ---- Summary ----
Write-Host ""
if ($errors.Count -eq 0 -and $warnings.Count -eq 0) {
    Write-Host "  ✅ All checks passed! Configuration is valid." -ForegroundColor Green
} else {
    if ($warnings.Count -gt 0) {
        Write-Host "  ⚠️  Warnings ($($warnings.Count)):" -ForegroundColor Yellow
        $warnings | ForEach-Object { Write-Host "     • $_" -ForegroundColor Yellow }
    }
    if ($errors.Count -gt 0) {
        Write-Host "  ❌ Errors ($($errors.Count)):" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "     • $_" -ForegroundColor Red }
    }
}
Write-Host ""
