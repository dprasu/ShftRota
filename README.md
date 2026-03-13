# 📞 ShftRota — Follow-the-Sun On-Call Dashboard

A modular, config-driven on-call rotation dashboard for global teams with **Weekday / Weekend** tabs, live clocks, and PowerShell tooling.

![Dark Theme](https://img.shields.io/badge/theme-dark-0d1117)
![Zero Dependencies](https://img.shields.io/badge/dependencies-zero-green)
![Config Driven](https://img.shields.io/badge/config-CSV%20%2B%20JSON-58a6ff)
![PowerShell](https://img.shields.io/badge/scripts-PowerShell%205.1%2B-blue)

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| **📋 Weekday / 🌙 Weekend Tabs** | Separate shift configs — 8h weekday, 12h extended weekend |
| **🟢 Live Region Cards** | Real-time primary + backup with contact info, green glow when active |
| **☀️ Follow-the-Sun Bar** | 24h UTC timeline with live red time marker |
| **📅 Rotation Schedule** | 8-week scrollable view with week navigation |
| **🔄 Handoff Log** | Daily handoff timeline with ✅/⏳ status |
| **👥 Team Roster** | Dynamic engineer count with on-duty badges |
| **🕐 Live UTC Clock** | Auto-refreshing every second |
| **📍 Auto-Tab Select** | Opens Weekend tab on Sat/Sun automatically |
| **📄 CSV Roster** | Edit team in Excel/Notepad — no code changes needed |
| **⚙️ JSON Config** | Shifts, regions, handoffs all configurable |
| **🔧 PowerShell Scripts** | Validate, query, export, and alert from CLI |
| **⏳ Loading Overlay** | Smooth spinner while config loads |

---

## 📁 Project Structure

```
ShftRota/
├── index.html                     # Dashboard (loads CSS + JS)
├── css/
│   └── style.css                  # All styles (dark theme, responsive)
├── js/
│   └── app.js                     # Application logic (config-driven)
├── config/
│   ├── settings.json              # Regions, shifts, handoffs, rotation
│   └── team-roster.csv            # Team members (editable in Excel)
├── scripts/
│   ├── Start-Dashboard.ps1        # Local HTTP server (Python or .NET)
│   ├── Test-Config.ps1            # Validate config files
│   ├── Get-CurrentOnCall.ps1      # Who's on-call right now?
│   ├── Export-Schedule.ps1        # Export N weeks to CSV/table
│   └── Send-HandoffAlert.ps1      # Teams/Slack webhook notifications
├── .gitignore
└── README.md
```

---

## 🚀 Quick Start

```powershell
# Clone
git clone https://github.com/dprasu/ShftRota.git
cd ShftRota

# Start local server (required for config loading)
.\scripts\Start-Dashboard.ps1

# Or specify a custom port
.\scripts\Start-Dashboard.ps1 -Port 3000
```

> **Note**: The dashboard loads `config/settings.json` and `config/team-roster.csv` via `fetch()`, which requires HTTP. Use the included server script or any web server.

---

## ⚙️ Configuration

### Team Roster — `config/team-roster.csv`

Edit in Excel, VS Code, or any text editor:

```csv
name,initials,email,phone,region,weekday_shift
Ravi Kumar,RK,ravi.kumar@corp.com,+91-98765-43210,India,05:30-13:30
James Wilson,JW,james.wilson@corp.com,+44-7700-900100,UK,08:00-16:00
Mike Johnson,MJ,mike.johnson@corp.com,+1-212-555-1201,USA_EST,13:00-21:00
```

| Column | Required | Description |
|--------|----------|-------------|
| name | ✅ | Full name |
| initials | ✅ | 2-letter avatar |
| email | ✅ | Contact email |
| phone | ✅ | Contact phone |
| region | ✅ | Must match a key in settings.json |
| weekday_shift | ✅ | UTC shift hours for weekdays |

### Settings — `config/settings.json`

```json
{
    "rotation": {
        "anchorDate": "2026-03-02T00:00:00Z",
        "cycleLengthWeeks": 4
    },
    "regions": [
        {
            "key": "India",
            "flag": "🇮🇳",
            "color": "orange",
            "timezone": "Asia/Kolkata",
            "weekday": { "startUTC": 5.5, "endUTC": 13.5 },
            "weekend": { "startUTC": 0,   "endUTC": 12   }
        }
    ]
}
```

---

## 🌍 Coverage Model

### Weekday (Mon–Fri) — Standard 8h Shifts
| Region | UTC Window | Local Time | Overlap |
|--------|-----------|------------|---------|
| 🇮🇳 India | 05:30 – 13:30 | 11:00 – 19:00 IST | 3.5h with UK |
| 🇬🇧 UK | 08:00 – 16:00 | 08:00 – 16:00 GMT | 3h with USA |
| 🇺🇸 USA EST | 13:00 – 21:00 | 08:00 – 16:00 EST | — |

### Weekend (Sat–Sun) — Extended 12h Shifts
| Region | UTC Window | Overlap |
|--------|-----------|---------|
| 🇮🇳 India | 00:00 – 12:00 | 4h with UK |
| 🇬🇧 UK | 08:00 – 20:00 | 8h with USA |
| 🇺🇸 USA EST | 12:00 – 00:00 | — |

---

## 🔧 PowerShell Scripts

### Validate Config
```powershell
.\scripts\Test-Config.ps1
# ✅ settings.json — parsed OK
# ✅ team-roster.csv — 20 engineers loaded
# ✅ All checks passed!
```

### Who's On-Call Now?
```powershell
.\scripts\Get-CurrentOnCall.ps1
# Region  Active Primary       Backup        ShiftUTC
# ------  ------ -------       ------        --------
# India   True   Ravi Kumar    Priya Sharma  5.5 - 13.5
# UK      True   James Wilson  Sarah Brown   8 - 16

.\scripts\Get-CurrentOnCall.ps1 -AsJson
```

### Export Schedule
```powershell
# Console table (12 weeks)
.\scripts\Export-Schedule.ps1

# Export to CSV
.\scripts\Export-Schedule.ps1 -Weeks 26 -OutputPath ".\schedule.csv"
```

### Handoff Alerts (Teams/Slack)
```powershell
# Run every 15 min via Task Scheduler
.\scripts\Send-HandoffAlert.ps1 -WebhookUrl "https://outlook.office.com/webhook/..."

# Custom lookahead
.\scripts\Send-HandoffAlert.ps1 -WebhookUrl $url -LookaheadMinutes 30
```

---

## 📦 Deployment Options

| Method | Steps |
|--------|-------|
| **Local** | `.\scripts\Start-Dashboard.ps1` |
| **IIS** | Copy folder to wwwroot, add MIME types for .json/.csv |
| **Nginx** | Point root to project folder |
| **GitHub Pages** | Enable Pages on `main` branch |
| **Azure Static Web Apps** | Deploy from GitHub |
| **SharePoint** | Upload files as page assets |
| **Teams Tab** | Add as Website tab → `http://your-server:8080` |

---

## 🔄 Rotation Logic

- **Pairs rotate weekly** — each pair = Primary + Backup
- **Anchor date**: configurable (default: March 2, 2026)
- **Weekend offset**: +1 pair index — ensures different people cover weekday vs weekend
- **Escalation**: Primary → 15 min → Backup → 15 min → Team Lead
- Pair index formula: `weekOffset % totalPairs`

---

## 📄 License

MIT — Use freely, modify as needed.
