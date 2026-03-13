/* ===================================================================
   ShftRota — Follow-the-Sun On-Call Dashboard
   Application Logic v2.0
   Loads config from: config/settings.json + config/team-roster.csv
   =================================================================== */

'use strict';

/* ===== GLOBAL STATE ===== */
let TEAM          = [];
let SETTINGS      = {};
let REGIONS       = {};
let WEEKEND_REGIONS = {};
let ESCALATION_MINUTES = 15;
let ROTATION_ANCHOR;
let currentMode   = 'weekday';
let currentWeekOffset = 0;
let displayWeekOffset = 0;

/* ===== CONFIG LOADER ===== */

async function loadSettings() {
    const resp = await fetch('config/settings.json');
    if (!resp.ok) throw new Error('Cannot load config/settings.json — ' + resp.status);
    SETTINGS = await resp.json();

    ESCALATION_MINUTES = SETTINGS.escalation?.minutes ?? 15;
    ROTATION_ANCHOR    = new Date(SETTINGS.rotation?.anchorDate ?? '2026-03-02T00:00:00Z');

    // Build REGIONS lookup from settings
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

function parseCSV(text) {
    const lines = text.trim().split('\n');
    const headers = lines[0].split(',').map(h => h.trim().toLowerCase());
    return lines.slice(1).filter(l => l.trim()).map(line => {
        const vals = line.split(',').map(v => v.trim());
        const obj = {};
        headers.forEach((h, i) => obj[h] = vals[i] || '');
        return obj;
    });
}

async function loadRoster() {
    const resp = await fetch('config/team-roster.csv');
    if (!resp.ok) throw new Error('Cannot load config/team-roster.csv — ' + resp.status);
    const text = await resp.text();
    const rows = parseCSV(text);
    TEAM = rows.map(r => ({
        name:     r.name,
        initials: r.initials,
        email:    r.email,
        phone:    r.phone,
        region:   r.region,
        shift:    r.weekday_shift || r.shift || ''
    }));
    // Update header with team count
    const rosterHeader = document.querySelector('.roster-header');
    if (rosterHeader) rosterHeader.textContent = `👥 Team Roster (${TEAM.length} Engineers)`;
    const meta = document.querySelector('.header .meta');
    if (meta) {
        const regionCount = [...new Set(TEAM.map(t => t.region))].length;
        meta.textContent = `Follow-the-Sun Coverage | ${TEAM.length} Engineers | ${regionCount} Regions | Escalation: ${ESCALATION_MINUTES} min | Auto-refreshes every 60s`;
    }
}

/* ===== HELPER FUNCTIONS ===== */

function getActiveRegions() {
    return currentMode === 'weekend' ? WEEKEND_REGIONS : REGIONS;
}

function getRegionKeys() {
    return Object.keys(REGIONS);
}

function getWeekNumber(date) {
    const diff = date.getTime() - ROTATION_ANCHOR.getTime();
    return Math.floor(diff / (7 * 24 * 60 * 60 * 1000));
}

function getWeekStart(weekOffset) {
    return new Date(ROTATION_ANCHOR.getTime() + weekOffset * 7 * 24 * 60 * 60 * 1000);
}

function getOnCallPair(region, weekOffset) {
    const members = TEAM.filter(t => t.region === region);
    if (members.length < 2) return { primary: members[0] || {}, backup: members[1] || members[0] || {} };
    const pairs = Math.floor(members.length / 2);
    const adj = currentMode === 'weekend' ? weekOffset + 1 : weekOffset;
    const pairIdx = ((adj % pairs) + pairs) % pairs;
    return {
        primary: members[pairIdx * 2],
        backup:  members[pairIdx * 2 + 1]
    };
}

function isRegionActive(region) {
    const now = new Date();
    const utcH = now.getUTCHours() + now.getUTCMinutes() / 60;
    const regs = getActiveRegions();
    const r = regs[region];
    if (!r) return false;
    if (r.shiftEnd > 24) return utcH >= r.shiftStart || utcH < (r.shiftEnd - 24);
    return utcH >= r.shiftStart && utcH < r.shiftEnd;
}

function isTodayWeekend() {
    const day = new Date().getUTCDay();
    return day === 0 || day === 6;
}

function getLocalTime(tz) {
    try {
        return new Date().toLocaleTimeString('en-GB', { timeZone: tz, hour: '2-digit', minute: '2-digit', second: '2-digit' });
    } catch { return '--:--:--'; }
}

function formatDate(d) {
    return d.toISOString().slice(0, 10);
}

/* ===== TAB SWITCHING ===== */

function switchTab(mode) {
    currentMode = mode;
    document.getElementById('tabWeekday').className = 'tab-btn' + (mode === 'weekday' ? ' active' : '');
    document.getElementById('tabWeekend').className = 'tab-btn' + (mode === 'weekend' ? ' active' : '');
    renderAll();
}
// Expose to global for onclick handlers
window.switchTab = switchTab;

/* ===== RENDER ===== */

function renderAll() {
    const now = new Date();
    currentWeekOffset = getWeekNumber(now);
    displayWeekOffset = currentWeekOffset;
    updateClock();
    renderOnCallCards();
    renderSunBar();
    renderSchedule(currentWeekOffset);
    renderRoster();
    renderHandoffLog();
    updateStats();
    // Update section titles
    const sunTitle = document.getElementById('sunTitle');
    const schedTitle = document.getElementById('scheduleTitle');
    if (sunTitle) sunTitle.textContent = currentMode === 'weekend'
        ? '🌙 Follow-the-Sun — Weekend Extended Shifts (UTC)'
        : '☀️ Follow-the-Sun — 24h UTC Coverage';
    if (schedTitle) schedTitle.textContent = currentMode === 'weekend'
        ? '📅 Weekend Rotation Schedule (Sat–Sun)'
        : '📅 Weekday Rotation Schedule (Mon–Fri)';
}

function updateClock() {
    const el = document.getElementById('utcClock');
    if (el) el.textContent = new Date().toLocaleTimeString('en-GB', { timeZone: 'UTC', hour: '2-digit', minute: '2-digit', second: '2-digit' }) + ' UTC';
}

function renderOnCallCards() {
    const weekOff = getWeekNumber(new Date());
    const container = document.getElementById('oncallCards');
    if (!container) return;
    container.innerHTML = '';
    const regs = getActiveRegions();
    getRegionKeys().forEach(region => {
        const r = regs[region];
        if (!r) return;
        const pair = getOnCallPair(region, weekOff);
        const active = isRegionActive(region);
        const localTime = getLocalTime(r.tz);
        const displayName = region === 'USA_EST' ? 'USA (EST)' : region;
        const shiftText = currentMode === 'weekend' ? (r.shiftLabel || '') : (pair.primary?.shift || '');
        const colorClass = r.color === 'orange' ? 'india' : r.color === 'blue' ? 'uk' : 'usa';
        const card = document.createElement('div');
        card.className = 'region-card' + (active ? ' active' : '');
        card.innerHTML = `
            <div class="region-name ${colorClass}">${r.flag} ${displayName}</div>
            <div class="region-shift">Shift: ${shiftText} UTC ${currentMode === 'weekend' ? '(extended)' : ''}</div>
            <div class="region-local">🕐 Local: ${localTime} ${r.tzLabel}</div>
            <div class="oncall-person">
                <div class="oncall-avatar primary">${pair.primary?.initials || '?'}</div>
                <div class="oncall-detail">
                    <div class="name">${pair.primary?.name || 'TBD'}</div>
                    <div class="role">🟢 Primary</div>
                    <div class="contact">📧 ${pair.primary?.email || ''} · 📱 ${pair.primary?.phone || ''}</div>
                </div>
            </div>
            <div class="oncall-person">
                <div class="oncall-avatar backup">${pair.backup?.initials || '?'}</div>
                <div class="oncall-detail">
                    <div class="name">${pair.backup?.name || 'TBD'}</div>
                    <div class="role">🟡 Backup (${ESCALATION_MINUTES} min escalation)</div>
                    <div class="contact">📧 ${pair.backup?.email || ''} · 📱 ${pair.backup?.phone || ''}</div>
                </div>
            </div>
        `;
        container.appendChild(card);
    });
}

function renderSunBar() {
    const now = new Date();
    const utcH = now.getUTCHours() + now.getUTCMinutes() / 60;
    const pct = (utcH / 24) * 100;
    const nowLine = document.getElementById('sunNowLine');
    if (nowLine) nowLine.style.left = pct + '%';

    const segs = document.querySelectorAll('.sun-segment');
    if (segs.length < 3) return;
    const regs = getActiveRegions();
    const keys = getRegionKeys();

    keys.forEach((key, i) => {
        if (!segs[i] || !regs[key]) return;
        const r = regs[key];
        const startPct = (r.shiftStart / 24) * 100;
        const widthPct = ((r.shiftEnd - r.shiftStart) / 24) * 100;
        const displayName = key === 'USA_EST' ? 'USA EST' : key;
        const startH = String(Math.floor(r.shiftStart)).padStart(2, '0') + ':' + String(Math.round((r.shiftStart % 1) * 60)).padStart(2, '0');
        const endRaw = r.shiftEnd > 24 ? r.shiftEnd - 24 : r.shiftEnd;
        const endH = String(Math.floor(endRaw)).padStart(2, '0') + ':' + String(Math.round((endRaw % 1) * 60)).padStart(2, '0');
        segs[i].style.left = startPct + '%';
        segs[i].style.width = widthPct + '%';
        segs[i].textContent = `${r.flag} ${displayName} (${startH}–${endH} UTC)`;
    });
}

function renderSchedule(centerWeek) {
    const tbody = document.getElementById('scheduleBody');
    if (!tbody) return;
    tbody.innerHTML = '';
    const currentWeek = getWeekNumber(new Date());
    const keys = getRegionKeys();
    const regionCount = keys.length;

    for (let w = centerWeek - 2; w <= centerWeek + 5; w++) {
        const ws = getWeekStart(w);
        const we = new Date(ws.getTime() + 6 * 24 * 60 * 60 * 1000);
        const isCurrent = (w === currentWeek);
        keys.forEach((region, ri) => {
            const pair = getOnCallPair(region, w);
            const regs = getActiveRegions();
            const r = regs[region];
            if (!r) return;
            const displayRegion = region === 'USA_EST' ? 'USA EST' : region;
            const badgeClass = r.color === 'orange' ? 'badge-india' : r.color === 'blue' ? 'badge-uk' : 'badge-usa';
            const shiftText = currentMode === 'weekend' ? (r.shiftLabel || '') : (pair.primary?.shift || '');
            const weekType = currentMode === 'weekend' ? 'Sat-Sun' : 'Mon-Fri';
            const row = document.createElement('tr');
            if (isCurrent) row.className = 'current-week';
            row.innerHTML = `
                ${ri === 0 ? `<td rowspan="${regionCount}" style="font-weight:600;white-space:nowrap;vertical-align:middle;">${formatDate(ws)}<br><span style="color:var(--text-secondary);font-size:11px;">to ${formatDate(we)}</span><br><span style="color:var(--text-secondary);font-size:10px;">${weekType}</span>${isCurrent ? '<br><span class="badge badge-primary" style="margin-top:4px;">THIS WEEK</span>' : ''}</td>` : ''}
                <td><span class="badge ${badgeClass}">${r.flag} ${displayRegion}</span></td>
                <td style="font-family:monospace;font-size:12px;">${shiftText}</td>
                <td><strong>${pair.primary?.name || 'TBD'}</strong><br><span style="color:var(--text-secondary);font-size:11px;">${pair.primary?.phone || ''}</span></td>
                <td>${pair.backup?.name || 'TBD'}<br><span style="color:var(--text-secondary);font-size:11px;">${pair.backup?.phone || ''}</span></td>
                <td>${isCurrent && isRegionActive(region) ? '<span class="badge badge-primary">🟢 Active</span>' : isCurrent ? '<span class="badge" style="background:rgba(139,148,158,0.15);color:var(--text-secondary);">⚪ Off-shift</span>' : '<span style="color:var(--text-secondary);font-size:12px;">—</span>'}</td>
            `;
            tbody.appendChild(row);
        });
    }
    const ws = getWeekStart(centerWeek);
    const we = new Date(ws.getTime() + 6 * 24 * 60 * 60 * 1000);
    const weekLabel = document.getElementById('weekLabel');
    if (weekLabel) weekLabel.textContent = formatDate(ws) + ' → ' + formatDate(we);
}

function renderRoster() {
    const grid = document.getElementById('rosterGrid');
    if (!grid) return;
    grid.innerHTML = '';
    const currentWeek = getWeekNumber(new Date());
    const onCallNow = {};
    getRegionKeys().forEach(region => {
        const pair = getOnCallPair(region, currentWeek);
        const active = isRegionActive(region);
        if (active) {
            if (pair.primary) onCallNow[pair.primary.name] = 'primary';
            if (pair.backup)  onCallNow[pair.backup.name] = 'backup';
        }
    });

    TEAM.forEach(person => {
        const regionMembers = TEAM.filter(t => t.region === person.region);
        const pairs = Math.floor(regionMembers.length / 2);
        let nextWeek = null;
        for (let w = currentWeek; w < currentWeek + (pairs || 1) * 2; w++) {
            const pair = getOnCallPair(person.region, w);
            if (pair.primary?.name === person.name || pair.backup?.name === person.name) {
                if (w > currentWeek || !nextWeek) { nextWeek = w; break; }
            }
        }

        const regs = getActiveRegions();
        const r = regs[person.region];
        if (!r) return;
        const duty = onCallNow[person.name];
        const badgeClass = r.color === 'orange' ? 'badge-india' : r.color === 'blue' ? 'badge-uk' : 'badge-usa';
        const displayRegion = person.region === 'USA_EST' ? 'USA EST' : person.region;

        const card = document.createElement('div');
        card.className = 'roster-card' + (duty ? ' on-duty' : '');
        card.innerHTML = `
            <div class="roster-avatar" style="background:var(--accent-${r.color});">${person.initials}</div>
            <div class="roster-info">
                <div class="name">${person.name} ${duty ? '<span class="on-duty-badge">' + (duty === 'primary' ? '🟢 PRIMARY' : '🟡 BACKUP') + '</span>' : ''}</div>
                <div class="detail"><span class="badge ${badgeClass}">${r.flag} ${displayRegion}</span> · ${person.phone}</div>
                <div class="next-oncall">Next on-call: Week of ${formatDate(getWeekStart(nextWeek || currentWeek))}</div>
            </div>
        `;
        grid.appendChild(card);
    });
}

function renderHandoffLog() {
    const log = document.getElementById('handoffLog');
    if (!log) return;
    const now = new Date();
    const todayStr = formatDate(now);

    const handoffs = (currentMode === 'weekend'
        ? SETTINGS.handoffs?.weekend
        : SETTINGS.handoffs?.weekday) || [];

    const currentWeek = getWeekNumber(now);
    log.innerHTML = handoffs.map(h => {
        const fromPair = getOnCallPair(h.from, currentWeek);
        const toPair   = getOnCallPair(h.to, currentWeek);
        const fromR = REGIONS[h.from] || {};
        const toR   = REGIONS[h.to] || {};
        const fromName = h.from === 'USA_EST' ? 'USA' : h.from;
        const toName   = h.to === 'USA_EST' ? 'USA' : h.to;
        let isPast = false;
        try {
            const handoffTime = new Date(todayStr + 'T' + h.utcTime + ':00Z');
            isPast = now > handoffTime;
        } catch {}
        return `<div class="handoff-item" style="${isPast ? 'opacity:0.5;' : ''}">
            <div class="handoff-time">${todayStr} ${h.utcTime} UTC ${isPast ? '✅' : '⏳'}</div>
            <div class="handoff-arrow">→</div>
            <div class="handoff-detail">
                ${fromR.flag || ''} <strong>${fromName}</strong> (${fromPair.primary?.name || 'TBD'})
                &nbsp;→&nbsp;
                ${toR.flag || ''} <strong>${toName}</strong> (${toPair.primary?.name || 'TBD'})
                <br><span style="color:var(--text-secondary);font-size:11px;">${h.note || ''}</span>
            </div>
        </div>`;
    }).join('');
}

function updateStats() {
    const keys = getRegionKeys();
    const activeCount = keys.filter(r => isRegionActive(r)).length;
    const total = keys.length;
    const safeSet = id => { const el = document.getElementById(id); return el; };

    const el1 = safeSet('statActiveRegions'); if (el1) el1.textContent = activeCount + ' / ' + total;
    const el2 = safeSet('statOnCall');        if (el2) el2.textContent = (activeCount * 2) + ' / ' + (total * 2);

    const now = new Date();
    const utcH = now.getUTCHours() + now.getUTCMinutes() / 60;
    const boundaries = currentMode === 'weekend'
        ? (SETTINGS.handoffs?.weekend || []).map(h => { const [hh, mm] = h.utcTime.split(':'); return parseInt(hh) + parseInt(mm || 0) / 60; })
        : (SETTINGS.handoffs?.weekday || []).map(h => { const [hh, mm] = h.utcTime.split(':'); return parseInt(hh) + parseInt(mm || 0) / 60; });
    boundaries.sort((a, b) => a - b);
    let nextBoundary = boundaries.find(b => b > utcH);
    if (!nextBoundary) nextBoundary = (boundaries[0] || 0) + 24;
    const hoursLeft = nextBoundary - utcH;
    const mins = Math.floor((hoursLeft % 1) * 60);
    const hrs  = Math.floor(hoursLeft);
    const el3 = safeSet('statNextHandoff'); if (el3) el3.textContent = hrs + 'h ' + mins + 'm';
    const el4 = safeSet('statWeek');        if (el4) el4.textContent = formatDate(getWeekStart(getWeekNumber(now)));

    // Day type indicator
    const indicator = document.getElementById('dayTypeIndicator');
    if (indicator) {
        const isWeekend = isTodayWeekend();
        if (currentMode === 'weekday') {
            indicator.className = 'tab-indicator weekday';
            indicator.textContent = isWeekend ? '📋 Weekday (Viewing)' : '📋 WEEKDAY — LIVE';
        } else {
            indicator.className = 'tab-indicator weekend';
            indicator.textContent = isWeekend ? '🌙 WEEKEND — LIVE' : '🌙 Weekend (Viewing)';
        }
    }
}

/* ===== NAVIGATION ===== */

function changeWeek(delta) {
    displayWeekOffset += delta;
    renderSchedule(displayWeekOffset);
}
window.changeWeek = changeWeek;

function goToCurrentWeek() {
    displayWeekOffset = getWeekNumber(new Date());
    renderSchedule(displayWeekOffset);
}
window.goToCurrentWeek = goToCurrentWeek;

/* ===== ERROR DISPLAY ===== */

function showError(msg) {
    const el = document.getElementById('configError');
    if (el) { el.textContent = '⚠️ ' + msg; el.classList.add('visible'); }
    const overlay = document.getElementById('loadingOverlay');
    if (overlay) overlay.classList.add('hidden');
}

/* ===== INIT ===== */

async function init() {
    try {
        await loadSettings();
        await loadRoster();

        if (isTodayWeekend()) {
            currentMode = 'weekend';
            document.getElementById('tabWeekday').className = 'tab-btn';
            document.getElementById('tabWeekend').className = 'tab-btn active';
        }

        displayWeekOffset = getWeekNumber(new Date());
        renderAll();

        // Hide loading overlay
        const overlay = document.getElementById('loadingOverlay');
        if (overlay) overlay.classList.add('hidden');

        // Live updates
        setInterval(() => {
            updateClock();
            renderSunBar();
            renderOnCallCards();
            updateStats();
        }, 1000);
        setInterval(renderAll, 60000);

    } catch (err) {
        console.error('ShftRota init error:', err);
        showError(err.message + ' — Make sure config files exist. See README.');
    }
}

document.addEventListener('DOMContentLoaded', init);
