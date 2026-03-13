<#
.SYNOPSIS
    Builds a single self-contained HTML dashboard from config files.
.DESCRIPTION
    Reads config/settings.json, config/team-roster.csv and config/bank-holidays.csv,
    embeds them inline into a standalone HTML file with all CSS and JS included.
    The output file needs NO server — works from file:// or IIS static hosting.
.PARAMETER OutputPath
    Path for the generated HTML file. Default: dist/ShftRota.html
.EXAMPLE
    .\Build-Dashboard.ps1
    .\Build-Dashboard.ps1 -OutputPath "C:\inetpub\wwwroot\dashboard\ShftRota.html"
#>
[CmdletBinding()]
param(
    [string]$OutputPath
)

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = $PSScriptRoot }

if (-not $OutputPath) {
    $distDir = Join-Path $root "dist"
    if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir -Force | Out-Null }
    $OutputPath = Join-Path $distDir "ShftRota.html"
}

Write-Host ""
Write-Host "  =========================================" -ForegroundColor Cyan
Write-Host "    ShftRota - Build Standalone HTML        " -ForegroundColor Cyan
Write-Host "  =========================================" -ForegroundColor Cyan
Write-Host ""

# ---- Load config ----
$settingsPath = Join-Path $root "config\settings.json"
$rosterPath   = Join-Path $root "config\team-roster.csv"
$holidayPath  = Join-Path $root "config\bank-holidays.csv"

if (-not (Test-Path $settingsPath)) { Write-Error "config/settings.json not found"; return }
if (-not (Test-Path $rosterPath))   { Write-Error "config/team-roster.csv not found"; return }

$settingsJson = Get-Content $settingsPath -Raw
$settings     = $settingsJson | ConvertFrom-Json
Write-Host "  [OK] settings.json loaded" -ForegroundColor Green

$rosterCsv = Import-Csv $rosterPath
$teamCount = ($rosterCsv | Measure-Object).Count
Write-Host "  [OK] team-roster.csv loaded ($teamCount engineers)" -ForegroundColor Green

# Build JS team array from CSV
$teamJs = "["
foreach ($r in $rosterCsv) {
    $name     = $r.name -replace "'", "\'"
    $initials = $r.initials
    $email    = $r.email
    $phone    = $r.phone
    $region   = $r.region
    $shift    = $r.weekday_shift
    $teamJs += "`n            { name: `"$name`", initials: `"$initials`", email: `"$email`", phone: `"$phone`", region: `"$region`", shift: `"$shift`" },"
}
$teamJs = $teamJs.TrimEnd(',') + "`n        ]"

# Build holidays JS array
$holidaysJs = "[]"
$holCount = 0
if (Test-Path $holidayPath) {
    $holidayCsv = Import-Csv $holidayPath
    $holCount = ($holidayCsv | Measure-Object).Count
    Write-Host "  [OK] bank-holidays.csv loaded ($holCount holidays)" -ForegroundColor Green
    $holidaysJs = "["
    foreach ($h in $holidayCsv) {
        $hname = $h.name -replace "'", "\'" -replace '"', '\"'
        $holidaysJs += "`n            { date: `"$($h.date)`", name: `"$hname`", region: `"$($h.region)`", type: `"$($h.type)`" },"
    }
    $holidaysJs = $holidaysJs.TrimEnd(',') + "`n        ]"
} else {
    Write-Host "  [--] bank-holidays.csv not found (holidays tab will be empty)" -ForegroundColor Yellow
}

# Build region keys
$regionKeys = @($settings.regions | ForEach-Object { $_.key })
$regionCount = $regionKeys.Count

# Read CSS
$css = Get-Content (Join-Path $root "css\style.css") -Raw
Write-Host "  [OK] style.css loaded" -ForegroundColor Green

# Read app.js
$appJs = Get-Content (Join-Path $root "js\app.js") -Raw
Write-Host "  [OK] app.js loaded" -ForegroundColor Green

# Read index.html
$indexHtml = Get-Content (Join-Path $root "index.html") -Raw
Write-Host "  [OK] index.html loaded" -ForegroundColor Green

$buildDate = (Get-Date).ToString('yyyy-MM-dd HH:mm')

# --- Transform: replace CSS link with inline style ---
$indexHtml = $indexHtml -replace '<link rel="stylesheet" href="css/style.css">', "<style>`n$css`n    </style>"

# --- Transform: patch app.js to use embedded data instead of fetch ---
$modifiedAppJs = $appJs

# Replace loadSettings() - use embedded data
$modifiedAppJs = $modifiedAppJs -replace '(?s)async function loadSettings\(\)\s*\{.*?\n\}', @"
async function loadSettings() {
    SETTINGS = EMBEDDED_SETTINGS;
    ESCALATION_MINUTES = SETTINGS.escalation?.minutes ?? 15;
    ROTATION_ANCHOR    = new Date(SETTINGS.rotation?.anchorDate ?? '2026-03-02T00:00:00Z');
    REGIONS = {};
    WEEKEND_REGIONS = {};
    (SETTINGS.regions || []).forEach(r => {
        REGIONS[r.key] = {
            flag: r.flag, color: r.color,
            shiftStart: r.weekday.startUTC, shiftEnd: r.weekday.endUTC,
            tz: r.timezone, tzLabel: r.tzLabel, utcOffset: r.utcOffset
        };
        WEEKEND_REGIONS[r.key] = {
            flag: r.flag, color: r.color,
            shiftStart: r.weekend.startUTC, shiftEnd: r.weekend.endUTC,
            tz: r.timezone, tzLabel: r.tzLabel, utcOffset: r.utcOffset,
            shiftLabel: r.weekend.label
        };
    });
}
"@

# Replace loadRoster() - use embedded data
$modifiedAppJs = $modifiedAppJs -replace '(?s)async function loadRoster\(\)\s*\{.*?\n\}', @"
async function loadRoster() {
    TEAM = EMBEDDED_TEAM;
    const rosterHeader = document.querySelector('.roster-header');
    if (rosterHeader) rosterHeader.textContent = String.fromCodePoint(0x1F465) + ' Team Roster (' + TEAM.length + ' Engineers)';
    const meta = document.querySelector('.header .meta');
    if (meta) {
        const regionCount = [...new Set(TEAM.map(t => t.region))].length;
        meta.textContent = 'Follow-the-Sun Coverage | ' + TEAM.length + ' Engineers | ' + regionCount + ' Regions | Escalation: ' + ESCALATION_MINUTES + ' min | Auto-refreshes every 60s';
    }
}
"@

# Replace loadHolidays() - use embedded data
$modifiedAppJs = $modifiedAppJs -replace '(?s)async function loadHolidays\(\)\s*\{.*?\n\}', @"
async function loadHolidays() {
    HOLIDAYS = EMBEDDED_HOLIDAYS.sort((a, b) => a.date.localeCompare(b.date));
    const badge = document.getElementById('holidayCount');
    if (badge) badge.textContent = HOLIDAYS.length;
}
"@

# Build the embedded data block + the patched app.js
$embeddedBlock = @"

        /* ===== EMBEDDED CONFIG (generated by Build-Dashboard.ps1 on $buildDate) ===== */
        const EMBEDDED_TEAM = $teamJs;
        const EMBEDDED_SETTINGS = $settingsJson;
        const EMBEDDED_HOLIDAYS = $holidaysJs;

"@

$fullScript = "$embeddedBlock`n$modifiedAppJs"

# Replace <script src="js/app.js"></script> with embedded script
$indexHtml = $indexHtml -replace '<script src="js/app.js"></script>', "<script>`n$fullScript`n    </script>"

# Update footer version
$indexHtml = $indexHtml -replace 'ShftRota v2\.0', "ShftRota v2.1 (standalone, built $buildDate)"

# Update loading text
$indexHtml = $indexHtml -replace 'Loading roster &amp; settings', 'Initializing'

# Write output
$indexHtml | Out-File -FilePath $OutputPath -Encoding UTF8 -Force

$size = [math]::Round((Get-Item $OutputPath).Length / 1024, 1)
Write-Host ""
Write-Host "  [OK] Built: $OutputPath ($size KB)" -ForegroundColor Green
Write-Host "  $teamCount engineers | $regionCount regions | $holCount holidays" -ForegroundColor DarkGray
Write-Host "  Tabs: Weekday + Weekend + Bank Holidays" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Usage:" -ForegroundColor Yellow
Write-Host "    - Open directly in browser (file://)" -ForegroundColor DarkGray
Write-Host "    - Copy to IIS wwwroot" -ForegroundColor DarkGray
Write-Host "    - Link from your dashboard" -ForegroundColor DarkGray
Write-Host ""
