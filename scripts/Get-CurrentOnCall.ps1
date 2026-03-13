<#
.SYNOPSIS
    Returns who is currently on-call (useful for alerting integration).
.DESCRIPTION
    Reads config/settings.json and config/team-roster.csv, calculates
    the current on-call pairs for each active region, and outputs
    structured objects suitable for pipeline or JSON export.
.PARAMETER AsJson
    Output as JSON string instead of PowerShell objects.
.EXAMPLE
    .\Get-CurrentOnCall.ps1
    .\Get-CurrentOnCall.ps1 -AsJson | ConvertFrom-Json
#>
[CmdletBinding()]
param(
    [switch]$AsJson
)

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = $PSScriptRoot }

# Load settings
$settings = Get-Content (Join-Path $root "config\settings.json") -Raw | ConvertFrom-Json
$roster   = Import-Csv (Join-Path $root "config\team-roster.csv")

$anchor  = [datetime]::Parse($settings.rotation.anchorDate).ToUniversalTime()
$now     = [datetime]::UtcNow
$weekNum = [math]::Floor(($now - $anchor).TotalDays / 7)

$isWeekend = $now.DayOfWeek -in @('Saturday', 'Sunday')
$utcHour   = $now.Hour + $now.Minute / 60

$results = @()

foreach ($region in $settings.regions) {
    $key     = $region.key
    $members = @($roster | Where-Object { $_.region -eq $key })
    $pairs   = [math]::Floor($members.Count / 2)
    if ($pairs -eq 0) { continue }

    # Weekend uses +1 offset
    $adj     = if ($isWeekend) { $weekNum + 1 } else { $weekNum }
    $pairIdx = (($adj % $pairs) + $pairs) % $pairs

    $primary = $members[$pairIdx * 2]
    $backup  = $members[$pairIdx * 2 + 1]

    # Check if region is active
    $shift = if ($isWeekend) { $region.weekend } else { $region.weekday }
    $active = ($utcHour -ge $shift.startUTC) -and ($utcHour -lt $shift.endUTC)

    $results += [PSCustomObject]@{
        Region      = $key
        Mode        = if ($isWeekend) { 'Weekend' } else { 'Weekday' }
        Active      = $active
        ShiftUTC    = "$($shift.startUTC) - $($shift.endUTC)"
        Primary     = $primary.name
        PrimaryPhone = $primary.phone
        PrimaryEmail = $primary.email
        Backup      = $backup.name
        BackupPhone = $backup.phone
        BackupEmail = $backup.email
        WeekNumber  = $weekNum
        Timestamp   = $now.ToString('yyyy-MM-dd HH:mm:ss UTC')
    }
}

if ($AsJson) {
    $results | ConvertTo-Json -Depth 3
} else {
    $results | Format-Table -AutoSize
}
