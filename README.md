# MikeGyver SatPass v1.0.0

A native iOS companion to the [satpass](../satpass) Go CLI: ISS and
amateur-satellite pass predictions for Tomball, TX, with a Yaesu FT-65R
frequency/Doppler cheat sheet on every pass and a 10-minute local
heads-up for 40°+ passes.

## How it works

```
iPhone (SatPass, SwiftUI)                    Cloudflare (free plan)
┌──────────────────────────────────┐         ┌────────────────────────────┐
│ Passes tab: next 48 h for        │  HTTPS  │ satpass-tle Worker         │
│ ISS, SO-50, AO-91, FO-29, JO-97  │ ──────► │  GET /tles                 │
│ AOS/LOS, max elevation, 40°+     │  (TLEs  │   CelesTrak stations +     │
│ highlighted                      │   only) │   amateur, parsed, cached  │
│                                  │         │   12 h in the Cache API    │
│ Pass detail: FT-65R cheat sheet  │         └────────────────────────────┘
│ (FM birds) + SSB warning         │
│ (FO-29/JO-97)                    │         Prediction happens ON-DEVICE:
│ Guide tab: full frequency guide  │         JavaScriptCore + vendored
│ Settings: Worker URL, lat/lon,   │         satellite.js v5.0.0 (MIT)
│ alerts, display filters          │         — no compute on the Worker,
└──────────────────────────────────┘         works offline on cached TLEs
```

Notifications are purely local (`UNUserNotificationCenter`): 10 minutes
before AOS of any pass peaking at/above your threshold (default 40°).
No push server, no background modes, no location permission needed —
the ground station coordinates are a setting (default Tomball, TX).

## Layout

```
satpass-ios/
├── worker/                  Cloudflare Worker: TLE proxy + 12 h cache
│   ├── wrangler.toml        (satpass-tle)
│   ├── package.json         (npm test runs the smoke test)
│   ├── src/index.js         GET / and GET /tles
│   ├── src/tleparse.js      TLE parser (mirrors the CLI's parseTLEText)
│   └── test/smoke.mjs       Live CelesTrak parse check (node)
├── ios/                     SwiftUI iPhone app (XcodeGen project)
│   ├── project.yml          MARKETING_VERSION / CURRENT_PROJECT_VERSION live here
│   └── SatPass/
│       ├── SatPassApp.swift
│       ├── Models.swift         Brand, SatGuide frequency data, SatPass, date helpers
│       ├── SettingsStore.swift  Worker URL, lat/lon, alerts (UserDefaults)
│       ├── ApiClient.swift      Worker REST client
│       ├── TleStore.swift       12 h TLE disk cache, stale fallback
│       ├── PassEngine.swift     JavaScriptCore wrapper around the JS engine
│       ├── PassStore.swift      Refresh orchestration (TLEs → SGP4 → passes)
│       ├── NotificationScheduler.swift  10-min local alerts for 40°+ passes
│       ├── ContentView.swift    Passes tab (list, next-pass card, TLE age)
│       ├── PassDetailView.swift Per-pass detail + FT-65R cheat sheet + Guide tab
│       ├── SettingsView.swift   Worker URL/test, ground station, alerts, display
│       ├── passengine.js        Shipped SGP4 pass engine (validated vs the CLI)
│       ├── vendor/satellite.min.js  satellite.js v5.0.0 (MIT, © Shashwat Kandadai)
│       ├── Info.plist
│       └── Assets.xcassets/     Navy/gold app icon set
├── .github/workflows/
│   └── testflight.yml       macos-26: XcodeGen → archive → IPA → fastlane pilot
├── docs/
│   └── POWERSHELL-SETUP.md  Detailed PowerShell runbook (start here)
└── scripts/
    └── push-satpass-ios.ps1 Clone/copy/commit/push/tag helper for Windows
```

## Quickstart

Follow **`docs/POWERSHELL-SETUP.md`** — it covers every command:

1. **Part 1:** Node.js → `npm install` → `wrangler login` →
   `wrangler deploy` → smoke-test `/tles` (no token needed — TLEs are
   public data)
2. **Part 2:** App Store Connect API key + Team ID (reuse your WalkLog
   secrets) + bundle ID `studio.mikegyver.satpass` + app record
   "MikeGyver SatPass" (check name availability first) → create the
   GitHub repo → add 4 secrets → `git tag v1.0.0` → TestFlight
3. **First launch:** Settings → paste Worker URL → **Test connection** →
   back → pull to refresh → enable the 10-minute heads-up

## Data sources

| Data | Source |
|---|---|
| TLEs | CelesTrak `GROUP=stations` + `GROUP=amateur`, via the Worker, 12 h cache |
| SGP4 propagator | satellite.js v5.0.0 (MIT) © Shashwat Kandadai and contributors, run on-device in JavaScriptCore |
| Satellite list | Same 5 as the CLI: ISS (25544), SO-50 (27607), AO-91 (43017), FO-29 (24278), JO-97 (43803) |
| Frequencies | Transcribed from `satcore/sats.go` (verified against AMSAT / work-sat.com, Sep 2026) |

## Validation

The exact shipped JS files (`vendor/satellite.min.js` +
`passengine.js`) were run in a JavaScriptCore-like sandbox against live
CelesTrak TLEs and compared pass-by-pass with the satpass Go CLI
(`gosgp4`) over 48 h for Tomball: **26/26 passes matched, worst AOS
delta 1.0 s, max elevation within 0.1°** (2026-10-03).

## Honest limitations

- The prediction engine is SGP4 with current TLEs — good to about a
  minute on AOS for LEO birds a day or two out; it degrades as TLEs age,
  which is why the app shows TLE age on every screen.
- Passes are computed from the TLE epoch forward; very long windows
  (72 h) on week-old TLEs will drift — refresh the TLEs instead.
- iOS delivers local notifications only if the app has refreshed while
  it had fresh TLEs; open the app once a day and pull to refresh so the
  40°+ alerts stay scheduled.
- FO-29 and JO-97 are SSB linear transponders — the guide says so
  plainly, because the FM-only FT-65R can't work them.
- Frequency data is static in the app (from the CLI guide); verify a
  bird is active at amsat.org/status before a sked.

## Versioning

- `ios/project.yml`: `MARKETING_VERSION` (user-visible) and
  `CURRENT_PROJECT_VERSION` (must increase for every TestFlight upload).
- Tag `v*` (e.g. `git tag v1.0.1; git push origin v1.0.1`) to build + upload.
