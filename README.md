# 📞 ShftRota — Follow-the-Sun On-Call Dashboard

A self-contained, zero-dependency HTML dashboard for managing **follow-the-sun on-call rotations** across global teams.

![Dark Theme](https://img.shields.io/badge/theme-dark-0d1117)
![Zero Dependencies](https://img.shields.io/badge/dependencies-zero-green)
![Standalone HTML](https://img.shields.io/badge/deploy-single%20HTML-58a6ff)

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| **📋 Weekday / 🌙 Weekend Tabs** | Separate shift configs — 8h weekday, 12h extended weekend |
| **🟢 Live Region Cards** | Real-time primary + backup with contact info, green glow when active |
| **☀️ Follow-the-Sun Bar** | 24h UTC timeline with live red time marker |
| **📅 Rotation Schedule** | 8-week scrollable view with week navigation |
| **🔄 Handoff Log** | Daily handoff timeline with ✅/⏳ status |
| **👥 Team Roster** | 20 engineers with on-duty badges |
| **🕐 Live UTC Clock** | Auto-refreshing every second |
| **📍 Auto-Tab Select** | Opens Weekend tab on Sat/Sun automatically |
| **⌨️ Keyboard-Free** | One-click tab switching, no setup required |

## 🌍 Coverage Model

### Weekday (Mon–Fri) — Standard 8h Shifts
| Region | UTC Window | Local Time | Engineers |
|--------|-----------|------------|-----------|
| 🇮🇳 India | 05:30 – 13:30 | 11:00 – 19:00 IST | 8 (4 pairs) |
| 🇬🇧 UK | 08:00 – 16:00 | 08:00 – 16:00 GMT | 6 (3 pairs) |
| 🇺🇸 USA EST | 13:00 – 21:00 | 08:00 – 16:00 EST | 6 (3 pairs) |

### Weekend (Sat–Sun) — Extended 12h Shifts
| Region | UTC Window | Overlap | Engineers |
|--------|-----------|---------|-----------|
| 🇮🇳 India | 00:00 – 12:00 | 4h with UK | Same pool, +1 pair offset |
| 🇬🇧 UK | 08:00 – 20:00 | 8h with USA | Different pairs than weekday |
| 🇺🇸 USA EST | 12:00 – 00:00 | 8h with UK | Ensures rest between rotations |

## 🚀 Quick Start

```bash
# Clone and open
git clone https://github.com/dprasu/ShftRota.git
cd ShftRota
start index.html          # Windows
open index.html           # macOS
xdg-open index.html       # Linux
```

No build step. No server. No dependencies. Just open the HTML file.

## 🔧 Configuration

Edit the `TEAM` array in `index.html` to add your team members:

```javascript
const TEAM = [
    { name: "Your Name", initials: "YN", email: "you@corp.com", phone: "+1-555-1234", region: "USA_EST", shift: "13:00-21:00" },
    // ... add more
];
```

### Regions
- `India` — IST timezone
- `UK` — GMT timezone  
- `USA_EST` — Eastern timezone

### Rotation Logic
- **Pairs rotate weekly** — Primary + Backup swap each week
- **Anchor date**: March 2, 2026 (configurable via `ROTATION_ANCHOR`)
- **Weekend offset**: +1 pair so weekday/weekend coverage uses different people
- **Escalation**: Primary → 15 min → Backup → 15 min → Team Lead

## 📦 Deployment Options

| Method | Steps |
|--------|-------|
| **Local file** | Just open `index.html` |
| **GitHub Pages** | Enable Pages on `main` branch |
| **IIS / Nginx** | Drop `index.html` into web root |
| **SharePoint** | Upload as a page asset |
| **Teams Tab** | Add as a Website tab |

## 📁 File Structure

```
ShftRota/
├── index.html          # Complete dashboard (single file, ~600 lines)
├── README.md           # This file
└── .gitignore          # Standard ignores
```

## 📄 License

MIT — Use freely, modify as needed.
