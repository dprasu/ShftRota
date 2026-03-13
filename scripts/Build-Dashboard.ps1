<#
.SYNOPSIS
    Builds a single self-contained HTML dashboard from config files.
.DESCRIPTION
    Reads config/settings.json and config/team-roster.csv, embeds them
    inline into a standalone HTML file with all CSS and JS included.
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
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║  🔨  ShftRota — Build Standalone HTML     ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ---- Load config ----
$settingsPath = Join-Path $root "config\settings.json"
$rosterPath   = Join-Path $root "config\team-roster.csv"

if (-not (Test-Path $settingsPath)) { Write-Error "config/settings.json not found"; return }
if (-not (Test-Path $rosterPath))   { Write-Error "config/team-roster.csv not found"; return }

$settingsJson = Get-Content $settingsPath -Raw
$settings     = $settingsJson | ConvertFrom-Json
Write-Host "  ✅ settings.json loaded" -ForegroundColor Green

$rosterCsv = Import-Csv $rosterPath
$teamCount = ($rosterCsv | Measure-Object).Count
Write-Host "  ✅ team-roster.csv loaded ($teamCount engineers)" -ForegroundColor Green

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

# Build region keys
$regionKeys = @($settings.regions | ForEach-Object { $_.key })
$regionCount = $regionKeys.Count

# Read CSS
$css = Get-Content (Join-Path $root "css\style.css") -Raw
Write-Host "  ✅ style.css loaded" -ForegroundColor Green

# Read JS template
$jsSource = Get-Content (Join-Path $root "js\app.js") -Raw
Write-Host "  ✅ app.js loaded" -ForegroundColor Green

# ---- Generate HTML ----
$buildDate = (Get-Date).ToString('yyyy-MM-dd HH:mm')

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ShftRota — On-Call Dashboard</title>
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='0.9em' font-size='90'>📞</text></svg>">
    <style>
$css
    </style>
</head>
<body>

    <!-- ===== HEADER ===== -->
    <div class="header">
        <div class="header-top">
            <h1>📞 <span>ShftRota — On-Call Dashboard</span></h1>
            <div style="display:flex;align-items:center;gap:16px;">
                <span class="tab-indicator" id="dayTypeIndicator">—</span>
                <div><span class="live-dot"></span><span class="live-clock" id="utcClock">--:--:-- UTC</span></div>
            </div>
        </div>
        <div class="meta">
            Follow-the-Sun Coverage | $teamCount Engineers | $regionCount Regions | Escalation: $($settings.escalation.minutes) min | Auto-refreshes every 60s
        </div>
    </div>

    <!-- ===== TAB BAR ===== -->
    <div class="tab-bar">
        <button class="tab-btn active" onclick="switchTab('weekday')" id="tabWeekday">
            📋 Weekday <span class="tab-badge wd">Mon – Fri</span>
        </button>
        <button class="tab-btn" onclick="switchTab('weekend')" id="tabWeekend">
            🌙 Weekend <span class="tab-badge we">Sat – Sun</span>
        </button>
    </div>

    <div class="container">

        <!-- ===== STATS ROW ===== -->
        <div class="stats-row">
            <div class="stat-card green"><div class="stat-label">Regions Active</div><div class="stat-value" id="statActiveRegions">—</div></div>
            <div class="stat-card blue"><div class="stat-label">Engineers On-Call</div><div class="stat-value" id="statOnCall">—</div></div>
            <div class="stat-card orange"><div class="stat-label">Next Handoff</div><div class="stat-value" id="statNextHandoff" style="font-size:16px;">—</div></div>
            <div class="stat-card purple"><div class="stat-label">Current Week</div><div class="stat-value" id="statWeek" style="font-size:16px;">—</div></div>
            <div class="stat-card cyan"><div class="stat-label">Rotation Cycle</div><div class="stat-value">$($settings.rotation.cycleLengthWeeks) wk</div></div>
        </div>

        <!-- ===== CURRENT ON-CALL ===== -->
        <div class="oncall-now" id="oncallCards"></div>

        <!-- ===== FOLLOW-THE-SUN ===== -->
        <div class="sun-section">
            <h3 id="sunTitle">☀️ Follow-the-Sun — 24h UTC Coverage</h3>
            <div class="sun-bar-container">
                <div class="sun-track">
                    <div class="sun-segment india" style="left:22.9%;width:33.3%;">🇮🇳 India</div>
                    <div class="sun-segment uk"    style="left:33.3%;width:33.3%;">🇬🇧 UK</div>
                    <div class="sun-segment usa"   style="left:54.2%;width:33.3%;">🇺🇸 USA EST</div>
                    <div class="sun-now" id="sunNowLine" style="left:50%;"></div>
                </div>
            </div>
            <div class="sun-hours">
                <span>00</span><span>02</span><span>04</span><span>06</span><span>08</span>
                <span>10</span><span>12</span><span>14</span><span>16</span><span>18</span>
                <span>20</span><span>22</span><span>24</span>
            </div>
        </div>

        <!-- ===== WEEKLY SCHEDULE ===== -->
        <div class="schedule-section">
            <div class="schedule-header">
                <h3 id="scheduleTitle">📅 Weekly Rotation Schedule</h3>
                <div class="schedule-nav">
                    <button onclick="changeWeek(-4)">◀◀</button>
                    <button onclick="changeWeek(-1)">◀ Prev</button>
                    <span class="week-label" id="weekLabel">—</span>
                    <button onclick="changeWeek(1)">Next ▶</button>
                    <button onclick="changeWeek(4)">▶▶</button>
                    <button onclick="goToCurrentWeek()" style="margin-left:8px;color:var(--accent-green);border-color:var(--accent-green);">📍 Today</button>
                </div>
            </div>
            <table>
                <thead>
                    <tr>
                        <th>Week</th>
                        <th>Region</th>
                        <th>Shift (UTC)</th>
                        <th>🟢 Primary</th>
                        <th>🟡 Backup</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody id="scheduleBody"></tbody>
            </table>
        </div>

        <!-- ===== HANDOFF LOG ===== -->
        <div class="handoff-section">
            <div class="handoff-header">🔄 Today's Handoff Log</div>
            <div id="handoffLog"></div>
        </div>

        <!-- ===== TEAM ROSTER ===== -->
        <div class="roster-section">
            <div class="roster-header">👥 Team Roster ($teamCount Engineers)</div>
            <div class="roster-grid" id="rosterGrid"></div>
        </div>

    </div>

    <div class="footer">
        ShftRota v2.0 — Follow-the-Sun On-Call Dashboard |
        Escalation: Primary → $($settings.escalation.minutes) min → Backup → $($settings.escalation.minutes) min → Team Lead |
        Auto-refresh: 60s | Built: $buildDate
    </div>

    <script>
        /* ===== EMBEDDED CONFIG (generated by Build-Dashboard.ps1) ===== */
        const TEAM = $teamJs;

        const SETTINGS = $settingsJson;

        /* ===== DERIVED CONFIG ===== */
        const REGIONS = {};
        const WEEKEND_REGIONS = {};
        SETTINGS.regions.forEach(function(r) {
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

        const ESCALATION_MINUTES = SETTINGS.escalation.minutes || 15;
        const ROTATION_ANCHOR = new Date(SETTINGS.rotation.anchorDate);
        let currentMode = 'weekday';
        let currentWeekOffset = 0;
        let displayWeekOffset = 0;

        /* ===== HELPERS ===== */
        function getActiveRegions() { return currentMode === 'weekend' ? WEEKEND_REGIONS : REGIONS; }
        function getRegionKeys() { return Object.keys(REGIONS); }

        function getWeekNumber(date) {
            return Math.floor((date.getTime() - ROTATION_ANCHOR.getTime()) / (7*24*60*60*1000));
        }
        function getWeekStart(weekOffset) {
            return new Date(ROTATION_ANCHOR.getTime() + weekOffset * 7*24*60*60*1000);
        }
        function getOnCallPair(region, weekOffset) {
            var members = TEAM.filter(function(t) { return t.region === region; });
            if (members.length < 2) return { primary: members[0]||{}, backup: members[1]||members[0]||{} };
            var pairs = Math.floor(members.length / 2);
            var adj = currentMode === 'weekend' ? weekOffset + 1 : weekOffset;
            var pairIdx = ((adj % pairs) + pairs) % pairs;
            return { primary: members[pairIdx*2], backup: members[pairIdx*2+1] };
        }
        function isRegionActive(region) {
            var now = new Date();
            var utcH = now.getUTCHours() + now.getUTCMinutes()/60;
            var r = getActiveRegions()[region];
            if (!r) return false;
            if (r.shiftEnd > 24) return utcH >= r.shiftStart || utcH < (r.shiftEnd-24);
            return utcH >= r.shiftStart && utcH < r.shiftEnd;
        }
        function isTodayWeekend() { var d = new Date().getUTCDay(); return d===0||d===6; }
        function getLocalTime(tz) {
            try { return new Date().toLocaleTimeString('en-GB',{timeZone:tz,hour:'2-digit',minute:'2-digit',second:'2-digit'}); }
            catch(e) { return '--:--:--'; }
        }
        function formatDate(d) { return d.toISOString().slice(0,10); }

        /* ===== TABS ===== */
        function switchTab(mode) {
            currentMode = mode;
            document.getElementById('tabWeekday').className = 'tab-btn' + (mode==='weekday'?' active':'');
            document.getElementById('tabWeekend').className = 'tab-btn' + (mode==='weekend'?' active':'');
            renderAll();
        }

        /* ===== RENDER ===== */
        function renderAll() {
            var now = new Date();
            currentWeekOffset = getWeekNumber(now);
            displayWeekOffset = currentWeekOffset;
            updateClock(); renderOnCallCards(); renderSunBar();
            renderSchedule(currentWeekOffset); renderRoster(); renderHandoffLog(); updateStats();
            document.getElementById('sunTitle').textContent = currentMode==='weekend'
                ? '🌙 Follow-the-Sun — Weekend Extended Shifts (UTC)'
                : '☀️ Follow-the-Sun — 24h UTC Coverage';
            document.getElementById('scheduleTitle').textContent = currentMode==='weekend'
                ? '📅 Weekend Rotation Schedule (Sat–Sun)'
                : '📅 Weekday Rotation Schedule (Mon–Fri)';
        }

        function updateClock() {
            document.getElementById('utcClock').textContent =
                new Date().toLocaleTimeString('en-GB',{timeZone:'UTC',hour:'2-digit',minute:'2-digit',second:'2-digit'})+' UTC';
        }

        function renderOnCallCards() {
            var weekOff = getWeekNumber(new Date());
            var container = document.getElementById('oncallCards');
            container.innerHTML = '';
            var regs = getActiveRegions();
            getRegionKeys().forEach(function(region) {
                var r = regs[region]; if(!r) return;
                var pair = getOnCallPair(region, weekOff);
                var active = isRegionActive(region);
                var localTime = getLocalTime(r.tz);
                var displayName = region==='USA_EST'?'USA (EST)':region;
                var shiftText = currentMode==='weekend'?(r.shiftLabel||''):(pair.primary.shift||'');
                var colorClass = r.color==='orange'?'india':r.color==='blue'?'uk':'usa';
                var card = document.createElement('div');
                card.className = 'region-card'+(active?' active':'');
                card.innerHTML =
                    '<div class="region-name '+colorClass+'">'+r.flag+' '+displayName+'</div>'+
                    '<div class="region-shift">Shift: '+shiftText+' UTC '+(currentMode==='weekend'?'(extended)':'')+'</div>'+
                    '<div class="region-local">🕐 Local: '+localTime+' '+r.tzLabel+'</div>'+
                    '<div class="oncall-person"><div class="oncall-avatar primary">'+(pair.primary.initials||'?')+'</div>'+
                    '<div class="oncall-detail"><div class="name">'+(pair.primary.name||'TBD')+'</div>'+
                    '<div class="role">🟢 Primary</div>'+
                    '<div class="contact">📧 '+(pair.primary.email||'')+' · 📱 '+(pair.primary.phone||'')+'</div></div></div>'+
                    '<div class="oncall-person"><div class="oncall-avatar backup">'+(pair.backup.initials||'?')+'</div>'+
                    '<div class="oncall-detail"><div class="name">'+(pair.backup.name||'TBD')+'</div>'+
                    '<div class="role">🟡 Backup ('+ESCALATION_MINUTES+' min escalation)</div>'+
                    '<div class="contact">📧 '+(pair.backup.email||'')+' · 📱 '+(pair.backup.phone||'')+'</div></div></div>';
                container.appendChild(card);
            });
        }

        function renderSunBar() {
            var now = new Date();
            var utcH = now.getUTCHours()+now.getUTCMinutes()/60;
            document.getElementById('sunNowLine').style.left = (utcH/24*100)+'%';
            var segs = document.querySelectorAll('.sun-segment');
            if(segs.length<3) return;
            var regs = getActiveRegions();
            var keys = getRegionKeys();
            keys.forEach(function(key,i) {
                if(!segs[i]||!regs[key]) return;
                var r = regs[key];
                var startPct = (r.shiftStart/24)*100;
                var widthPct = ((r.shiftEnd-r.shiftStart)/24)*100;
                var dn = key==='USA_EST'?'USA EST':key;
                var sH = String(Math.floor(r.shiftStart)).padStart(2,'0')+':'+String(Math.round((r.shiftStart%1)*60)).padStart(2,'0');
                var eRaw = r.shiftEnd>24?r.shiftEnd-24:r.shiftEnd;
                var eH = String(Math.floor(eRaw)).padStart(2,'0')+':'+String(Math.round((eRaw%1)*60)).padStart(2,'0');
                segs[i].style.left = startPct+'%';
                segs[i].style.width = widthPct+'%';
                segs[i].textContent = r.flag+' '+dn+' ('+sH+'–'+eH+' UTC)';
            });
        }

        function renderSchedule(centerWeek) {
            var tbody = document.getElementById('scheduleBody');
            tbody.innerHTML = '';
            var currentWeek = getWeekNumber(new Date());
            var keys = getRegionKeys();
            var rc = keys.length;
            for (var w = centerWeek-2; w <= centerWeek+5; w++) {
                var ws = getWeekStart(w);
                var we = new Date(ws.getTime()+6*24*60*60*1000);
                var isCurrent = (w===currentWeek);
                keys.forEach(function(region, ri) {
                    var pair = getOnCallPair(region,w);
                    var regs = getActiveRegions();
                    var r = regs[region]; if(!r) return;
                    var dr = region==='USA_EST'?'USA EST':region;
                    var bc = r.color==='orange'?'badge-india':r.color==='blue'?'badge-uk':'badge-usa';
                    var st = currentMode==='weekend'?(r.shiftLabel||''):(pair.primary.shift||'');
                    var wt = currentMode==='weekend'?'Sat-Sun':'Mon-Fri';
                    var row = document.createElement('tr');
                    if(isCurrent) row.className='current-week';
                    row.innerHTML =
                        (ri===0?'<td rowspan="'+rc+'" style="font-weight:600;white-space:nowrap;vertical-align:middle;">'+formatDate(ws)+'<br><span style="color:var(--text-secondary);font-size:11px;">to '+formatDate(we)+'</span><br><span style="color:var(--text-secondary);font-size:10px;">'+wt+'</span>'+(isCurrent?'<br><span class="badge badge-primary" style="margin-top:4px;">THIS WEEK</span>':'')+'</td>':'')+
                        '<td><span class="badge '+bc+'">'+r.flag+' '+dr+'</span></td>'+
                        '<td style="font-family:monospace;font-size:12px;">'+st+'</td>'+
                        '<td><strong>'+(pair.primary.name||'TBD')+'</strong><br><span style="color:var(--text-secondary);font-size:11px;">'+(pair.primary.phone||'')+'</span></td>'+
                        '<td>'+(pair.backup.name||'TBD')+'<br><span style="color:var(--text-secondary);font-size:11px;">'+(pair.backup.phone||'')+'</span></td>'+
                        '<td>'+(isCurrent&&isRegionActive(region)?'<span class="badge badge-primary">🟢 Active</span>':isCurrent?'<span class="badge" style="background:rgba(139,148,158,0.15);color:var(--text-secondary);">⚪ Off-shift</span>':'<span style="color:var(--text-secondary);font-size:12px;">—</span>')+'</td>';
                    tbody.appendChild(row);
                });
            }
            var ws2 = getWeekStart(centerWeek);
            var we2 = new Date(ws2.getTime()+6*24*60*60*1000);
            document.getElementById('weekLabel').textContent = formatDate(ws2)+' → '+formatDate(we2);
        }

        function renderRoster() {
            var grid = document.getElementById('rosterGrid');
            grid.innerHTML = '';
            var cw = getWeekNumber(new Date());
            var onCallNow = {};
            getRegionKeys().forEach(function(region) {
                var pair = getOnCallPair(region,cw);
                if(isRegionActive(region)) {
                    if(pair.primary) onCallNow[pair.primary.name]='primary';
                    if(pair.backup) onCallNow[pair.backup.name]='backup';
                }
            });
            TEAM.forEach(function(person) {
                var rm = TEAM.filter(function(t){return t.region===person.region;});
                var pairs = Math.floor(rm.length/2);
                var nextWeek = null;
                for(var w=cw;w<cw+(pairs||1)*2;w++) {
                    var pair=getOnCallPair(person.region,w);
                    if((pair.primary&&pair.primary.name===person.name)||(pair.backup&&pair.backup.name===person.name)){
                        if(w>cw||!nextWeek){nextWeek=w;break;}
                    }
                }
                var regs = getActiveRegions();
                var r = regs[person.region]; if(!r) return;
                var duty = onCallNow[person.name];
                var bc = r.color==='orange'?'badge-india':r.color==='blue'?'badge-uk':'badge-usa';
                var dr = person.region==='USA_EST'?'USA EST':person.region;
                var card = document.createElement('div');
                card.className = 'roster-card'+(duty?' on-duty':'');
                card.innerHTML =
                    '<div class="roster-avatar" style="background:var(--accent-'+r.color+');">'+person.initials+'</div>'+
                    '<div class="roster-info">'+
                    '<div class="name">'+person.name+' '+(duty?'<span class="on-duty-badge">'+(duty==='primary'?'🟢 PRIMARY':'🟡 BACKUP')+'</span>':'')+'</div>'+
                    '<div class="detail"><span class="badge '+bc+'">'+r.flag+' '+dr+'</span> · '+person.phone+'</div>'+
                    '<div class="next-oncall">Next on-call: Week of '+formatDate(getWeekStart(nextWeek||cw))+'</div></div>';
                grid.appendChild(card);
            });
        }

        function renderHandoffLog() {
            var log = document.getElementById('handoffLog');
            var now = new Date();
            var todayStr = formatDate(now);
            var handoffs = currentMode==='weekend' ? SETTINGS.handoffs.weekend : SETTINGS.handoffs.weekday;
            var cw = getWeekNumber(now);
            log.innerHTML = handoffs.map(function(h) {
                var fp = getOnCallPair(h.from,cw);
                var tp = getOnCallPair(h.to,cw);
                var fr = REGIONS[h.from]||{};
                var tr = REGIONS[h.to]||{};
                var fn = h.from==='USA_EST'?'USA':h.from;
                var tn = h.to==='USA_EST'?'USA':h.to;
                var isPast = false;
                try { isPast = now > new Date(todayStr+'T'+h.utcTime+':00Z'); } catch(e){}
                return '<div class="handoff-item" style="'+(isPast?'opacity:0.5;':'')+'">'+
                    '<div class="handoff-time">'+todayStr+' '+h.utcTime+' UTC '+(isPast?'✅':'⏳')+'</div>'+
                    '<div class="handoff-arrow">→</div>'+
                    '<div class="handoff-detail">'+(fr.flag||'')+' <strong>'+fn+'</strong> ('+((fp.primary||{}).name||'TBD')+')'+
                    ' &nbsp;→&nbsp; '+(tr.flag||'')+' <strong>'+tn+'</strong> ('+((tp.primary||{}).name||'TBD')+')'+
                    '<br><span style="color:var(--text-secondary);font-size:11px;">'+(h.note||'')+'</span></div></div>';
            }).join('');
        }

        function updateStats() {
            var keys = getRegionKeys();
            var ac = keys.filter(function(r){return isRegionActive(r);}).length;
            document.getElementById('statActiveRegions').textContent = ac+' / '+keys.length;
            document.getElementById('statOnCall').textContent = (ac*2)+' / '+(keys.length*2);
            var now = new Date();
            var utcH = now.getUTCHours()+now.getUTCMinutes()/60;
            var handoffs = currentMode==='weekend'?SETTINGS.handoffs.weekend:SETTINGS.handoffs.weekday;
            var boundaries = handoffs.map(function(h){var p=h.utcTime.split(':');return parseInt(p[0])+parseInt(p[1]||0)/60;});
            boundaries.sort(function(a,b){return a-b;});
            var nb = null;
            for(var i=0;i<boundaries.length;i++){if(boundaries[i]>utcH){nb=boundaries[i];break;}}
            if(!nb) nb = (boundaries[0]||0)+24;
            var hl = nb-utcH;
            document.getElementById('statNextHandoff').textContent = Math.floor(hl)+'h '+Math.floor((hl%1)*60)+'m';
            document.getElementById('statWeek').textContent = formatDate(getWeekStart(getWeekNumber(now)));
            var ind = document.getElementById('dayTypeIndicator');
            var isWE = isTodayWeekend();
            if(currentMode==='weekday'){
                ind.className='tab-indicator weekday';
                ind.textContent=isWE?'📋 Weekday (Viewing)':'📋 WEEKDAY — LIVE';
            } else {
                ind.className='tab-indicator weekend';
                ind.textContent=isWE?'🌙 WEEKEND — LIVE':'🌙 Weekend (Viewing)';
            }
        }

        /* ===== NAVIGATION ===== */
        function changeWeek(delta) { displayWeekOffset+=delta; renderSchedule(displayWeekOffset); }
        function goToCurrentWeek() { displayWeekOffset=getWeekNumber(new Date()); renderSchedule(displayWeekOffset); }

        /* ===== INIT ===== */
        if(isTodayWeekend()) {
            currentMode='weekend';
            document.getElementById('tabWeekday').className='tab-btn';
            document.getElementById('tabWeekend').className='tab-btn active';
        }
        displayWeekOffset = getWeekNumber(new Date());
        renderAll();
        setInterval(function(){updateClock();renderSunBar();renderOnCallCards();updateStats();},1000);
        setInterval(renderAll,60000);
    </script>
</body>
</html>
"@

# Write output
$html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force

$size = [math]::Round((Get-Item $OutputPath).Length / 1024, 1)
Write-Host ""
Write-Host "  ✅ Built: $OutputPath ($size KB)" -ForegroundColor Green
Write-Host "  📋 $teamCount engineers | $regionCount regions | Weekday + Weekend tabs" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Usage:" -ForegroundColor Yellow
Write-Host "    • Open directly in browser (file://)" -ForegroundColor DarkGray
Write-Host "    • Copy to IIS wwwroot" -ForegroundColor DarkGray
Write-Host "    • Link from your dashboard" -ForegroundColor DarkGray
Write-Host ""
