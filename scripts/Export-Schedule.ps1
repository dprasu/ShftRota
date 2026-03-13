<#
.SYNOPSIS
    Exports the full rotation schedule for the next N weeks.
.DESCRIPTION
    Generates a CSV or console-table of all on-call assignments
    for the specified number of weeks. Useful for sharing with
    management or importing into calendars.
.PARAMETER Weeks
    Number of weeks to export. Default: 12
.PARAMETER OutputPath
    Optional CSV file path to export to.
.EXAMPLE
    .\Export-Schedule.ps1 -Weeks 8
    .\Export-Schedule.ps1 -Weeks 12 -OutputPath "C:\Reports\oncall-schedule.csv"
#>
[CmdletBinding()]
param(
    [int]$Weeks = 12,
    [string]$OutputPath
)

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = $PSScriptRoot }

$settings = Get-Content (Join-Path $root "config\settings.json") -Raw | ConvertFrom-Json
$roster   = Import-Csv (Join-Path $root "config\team-roster.csv")

$anchor  = [datetime]::Parse($settings.rotation.anchorDate).ToUniversalTime()
$now     = [datetime]::UtcNow
$weekNum = [math]::Floor(($now - $anchor).TotalDays / 7)

Write-Host ""
Write-Host "  📅 ShftRota — Schedule Export ($Weeks weeks)" -ForegroundColor Cyan
Write-Host ""

$rows = @()

for ($w = $weekNum; $w -lt ($weekNum + $Weeks); $w++) {
    $weekStart = $anchor.AddDays($w * 7)
    $weekEnd   = $weekStart.AddDays(6)

    foreach ($mode in @('Weekday', 'Weekend')) {
        foreach ($region in $settings.regions) {
            $key     = $region.key
            $members = @($roster | Where-Object { $_.region -eq $key })
            $pairs   = [math]::Floor($members.Count / 2)
            if ($pairs -eq 0) { continue }

            $adj     = if ($mode -eq 'Weekend') { $w + 1 } else { $w }
            $pairIdx = (($adj % $pairs) + $pairs) % $pairs

            $primary = $members[$pairIdx * 2]
            $backup  = $members[$pairIdx * 2 + 1]

            $shift = if ($mode -eq 'Weekend') { $region.weekend } else { $region.weekday }

            $rows += [PSCustomObject]@{
                WeekStart    = $weekStart.ToString('yyyy-MM-dd')
                WeekEnd      = $weekEnd.ToString('yyyy-MM-dd')
                Mode         = $mode
                Region       = $key
                ShiftUTC     = $shift.label
                PrimaryName  = $primary.name
                PrimaryPhone = $primary.phone
                PrimaryEmail = $primary.email
                BackupName   = $backup.name
                BackupPhone  = $backup.phone
                BackupEmail  = $backup.email
                IsCurrent    = ($w -eq $weekNum)
            }
        }
    }
}

if ($OutputPath) {
    $rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host "  ✅ Exported $($rows.Count) rows to $OutputPath" -ForegroundColor Green
} else {
    $rows | Format-Table WeekStart, Mode, Region, ShiftUTC, PrimaryName, BackupName, IsCurrent -AutoSize
}
Write-Host ""
