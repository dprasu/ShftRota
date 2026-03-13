<#
.SYNOPSIS
    Sends Teams/Slack webhook notification for shift handoffs.
.DESCRIPTION
    Checks if a handoff is occurring within the next N minutes and
    sends a notification to the configured webhook URL.
    Designed to run as a scheduled task every 15 minutes.
.PARAMETER WebhookUrl
    The Teams Incoming Webhook or Slack Webhook URL.
.PARAMETER LookaheadMinutes
    How many minutes ahead to check for upcoming handoffs. Default: 20
.EXAMPLE
    .\Send-HandoffAlert.ps1 -WebhookUrl "https://outlook.office.com/webhook/..."
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$WebhookUrl,

    [int]$LookaheadMinutes = 20
)

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = $PSScriptRoot }

$settings = Get-Content (Join-Path $root "config\settings.json") -Raw | ConvertFrom-Json
$roster   = Import-Csv (Join-Path $root "config\team-roster.csv")

$now       = [datetime]::UtcNow
$utcHour   = $now.Hour + $now.Minute / 60
$isWeekend = $now.DayOfWeek -in @('Saturday', 'Sunday')

$handoffs = if ($isWeekend) { $settings.handoffs.weekend } else { $settings.handoffs.weekday }

$anchor  = [datetime]::Parse($settings.rotation.anchorDate).ToUniversalTime()
$weekNum = [math]::Floor(($now - $anchor).TotalDays / 7)

foreach ($h in $handoffs) {
    $parts     = $h.utcTime -split ':'
    $handoffH  = [double]$parts[0] + [double]$parts[1] / 60
    $diffMin   = ($handoffH - $utcHour) * 60

    if ($diffMin -gt 0 -and $diffMin -le $LookaheadMinutes) {
        # Get on-call pairs
        $fromMembers = @($roster | Where-Object { $_.region -eq $h.from })
        $toMembers   = @($roster | Where-Object { $_.region -eq $h.to })

        $fromPairs = [math]::Floor($fromMembers.Count / 2)
        $toPairs   = [math]::Floor($toMembers.Count / 2)

        $fromAdj = if ($isWeekend) { $weekNum + 1 } else { $weekNum }
        $toAdj   = $fromAdj

        $fromIdx = (($fromAdj % $fromPairs) + $fromPairs) % $fromPairs
        $toIdx   = (($toAdj % $toPairs) + $toPairs) % $toPairs

        $fromPrimary = $fromMembers[$fromIdx * 2]
        $toPrimary   = $toMembers[$toIdx * 2]

        $title = "🔄 ShftRota Handoff in $([math]::Round($diffMin)) min"
        $body  = @"
**$($h.from)** → **$($h.to)** at $($h.utcTime) UTC

From: **$($fromPrimary.name)** ($($fromPrimary.phone))
To: **$($toPrimary.name)** ($($toPrimary.phone))

_$($h.note)_
"@

        # Send to Teams/Slack
        $payload = @{
            '@type'    = 'MessageCard'
            summary    = $title
            themeColor = '39d2c0'
            title      = $title
            text       = $body
        } | ConvertTo-Json -Depth 3

        try {
            Invoke-RestMethod -Uri $WebhookUrl -Method Post -ContentType 'application/json' -Body $payload
            Write-Host "✅ Alert sent: $($h.from) → $($h.to) at $($h.utcTime)" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to send webhook: $_"
        }
    }
}
