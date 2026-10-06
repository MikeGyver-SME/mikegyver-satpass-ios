# MikeGyver SatPass v1.0.0 — PowerShell Setup Runbook

Two parts, in order. Part 1 puts your TLE Worker online and proves it
works. Part 2 builds the iPhone app in GitHub Actions and delivers it to
your phone through TestFlight.

**What you're building**

```
iPhone (SatPass, SwiftUI)                    Cloudflare (free plan)
┌──────────────────────────────────┐         ┌────────────────────────────┐
│ Passes: next 48 h for ISS,       │  HTTPS  │ satpass-tle Worker         │
│ SO-50, AO-91, FO-29, JO-97       │ ──────► │  GET /tles → 5 curated     │
│ 40°+ highlighted, FT-65R cheat   │  (TLEs  │  sats, cached 12 h         │
│ sheet per pass, Guide tab        │   only) └────────────────────────────┘
│ 10-min local alert before        │
│ 40°+ passes                      │         Prediction runs ON your
└──────────────────────────────────┘         iPhone (JavaScriptCore +
                                             satellite.js) — the Worker
                                             only serves TLEs.
```

**Before you start:** the `satpass-ios-v1.0.0.zip` from Wiggs, extracted
somewhere handy (these steps assume
`~\Downloads\satpass-ios-v1.0.0\satpass-ios`). A Cloudflare account (free
plan is fine) and your paid Apple Developer membership. If you built
WalkLog, you already have Node, the App Store Connect API key, and your
Team ID — reuse all of them.

---

## Part 1 — Cloudflare Worker (TLE proxy)

### 1.1 Install Node.js LTS (skip if you have it from WalkLog)

```powershell
winget install -e --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
```

Close PowerShell and open a **new** one, then verify:

```powershell
node -v
npm -v
```

### 1.2 Install the Worker dependencies and run the smoke test

```powershell
cd "$env:USERPROFILE\Downloads\satpass-ios-v1.0.0\satpass-ios\worker"
npm install
npm test
```

`npm test` fetches the live CelesTrak catalogs and checks that all five
satellites (ISS, SO-50, AO-91, FO-29, JO-97) parse. Expected:

```
25544 ISS (ZARYA): line1 ok, line2 ok
...
SMOKE TEST PASSED (113 TLEs parsed)
```

(The exact count drifts as the catalog changes; what matters is all five
lines say `ok`.)

### 1.3 Log in to Cloudflare (skip if already logged in)

```powershell
npx wrangler login
```

### 1.4 Deploy

```powershell
npx wrangler deploy
```

Wrangler prints something like:

```
✨ Success! Deployed satpass-tle to https://satpass-tle.<your-subdomain>.workers.dev
```

**Copy that URL** — it's your Worker URL.

### 1.5 Smoke-test the deployed Worker

```powershell
$Worker = "https://satpass-tle.<your-subdomain>.workers.dev"
(Invoke-RestMethod -Uri "$Worker/tles").sats.PSObject.Properties.Name
```

Expected: the five NORAD IDs `25544 27607 43017 24278 43803`. Hit it
again — the second response should come back instantly from the 12-hour
cache (`"cached": true`).

**Part 1 is done.** Write down:

- Worker URL: `https://satpass-tle.<your-subdomain>.workers.dev`

---

## Part 2 — GitHub repo, secrets, and TestFlight build

### 2.1 One-time Apple setup

Good news: the App Store Connect API key and Team ID from WalkLog work
for every app on your team — no new key needed.

1. **Check the app name is available:** App Store Connect → **My Apps** →
   **+** → **New App** → type `MikeGyver SatPass`. If Apple accepts it,
   finish creating the record: platform **iOS**, Bundle ID
   `studio.mikegyver.satpass` (see step 2), SKU `satpass-ios-001`. If the
   name is taken, pick a close variant (e.g. `MikeGyver SatPass TX`),
   tell Wiggs, and he'll update the display name to match.
2. **Register the bundle ID:**
   https://developer.apple.com/account → **Certificates, Identifiers &
   Profiles** → **Identifiers** → **+** → **App IDs** → **App**
   - Description: `SatPass`, Bundle ID: **Explicit** →
     `studio.mikegyver.satpass`
   - No special capabilities needed (local notifications are not a
     capability) → **Register**

### 2.2 Create the GitHub repo and push the code

On https://github.com/new (or under your `MikeGyver-SME` org): repository
name **`mikegyver-satpass-ios`**, visibility **Private**, do **not** add a
README (the zip already has one).

Then in PowerShell:

```powershell
cd "$env:USERPROFILE\Downloads\satpass-ios-v1.0.0\satpass-ios"
git init -b main
git add -A
git commit -m "SatPass iOS v1.0.0"
git remote add origin https://github.com/MikeGyver-SME/mikegyver-satpass-ios.git
git branch -M main
git push -u origin main
```

> Shortcut: `scripts\push-satpass-ios.ps1` in this folder does the
> commit/push/tag cycle for you on later versions — see the script's
> header comments.

### 2.3 Add the four secrets to the repo

Same four secrets as WalkLog (same values — the API key is per-team, not
per-app). Either: repo page → **Settings** → **Secrets and variables** →
**Actions** → **New repository secret** (four times), or with the GitHub
CLI:

```powershell
$Repo = "MikeGyver-SME/mikegyver-satpass-ios"

gh secret set ASC_KEY_ID    --body "A1B2C3D4E5"   --repo $Repo
gh secret set ASC_ISSUER_ID --body "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" --repo $Repo
gh secret set TEAM_ID       --body "WXMPJQBSTA7"   --repo $Repo   # <-- YOUR real Team ID

$P8 = Get-Content -Raw "$env:USERPROFILE\Downloads\AuthKey_A1B2C3D4E5.p8"
gh secret set ASC_KEY_P8 --body $P8 --repo $Repo
```

(Use your real Key ID / Issuer ID / Team ID / `.p8` file from the WalkLog
build, not the placeholders above. `gh secret set` handles the multi-line
`.p8` correctly. Don't have `gh`? `winget install GitHub.cli`, then
`gh auth login`.)

### 2.4 Trigger the build

The workflow runs on version tags. Push one:

```powershell
cd "$env:USERPROFILE\Downloads\satpass-ios-v1.0.0\satpass-ios"
git tag v1.0.0
git push origin v1.0.0
```

Watch it: repo → **Actions** → **Build and upload SatPass to
TestFlight**. Roughly 10–15 minutes: XcodeGen → archive with App Store
signing → export IPA → `fastlane pilot upload`. A copy of the IPA is also
kept as a workflow artifact for 14 days.

The workflow also verifies the bundled JS engine (`satellite.min.js` +
`passengine.js`) before building, and guards `Info.plist` against
XcodeGen overwrites.

### 2.5 Install on your iPhone via TestFlight

1. App Store Connect → **My Apps** → **MikeGyver SatPass** →
   **TestFlight** → the new build appears under **iOS Builds**
   (processing takes a few minutes)
2. **Internal Testing** → add yourself as a tester
3. On your iPhone: install **TestFlight**, open the invite, install
   **MikeGyver SatPass**

### 2.6 First launch

1. Open SatPass → **Settings** (gear) → paste your **Worker URL** →
   **Test connection** (expect "✓ Connected — 5 satellites")
2. Back → pull to refresh. The app fetches TLEs, computes the next 48 h
   on-device (~1 s), and lists every pass peaking above 10°, with 40°+
   passes badged gold.
3. Tap any pass → the FT-65R cheat sheet: what to listen on, which way to
   tune for Doppler, and an honest SSB warning on FO-29/JO-97.
4. Settings → **10-minute heads-up** → allow notifications. The app
   schedules a local alert 10 minutes before AOS of every 40°+ pass.
   (Open the app and refresh once a day so the alerts stay scheduled.)

### 2.7 Shipping v1.0.1 and beyond

1. Bump versions in `ios/project.yml`: `MARKETING_VERSION` (what users
   see) and `CURRENT_PROJECT_VERSION` (must increase every TestFlight
   upload)
2. Commit, push, tag the new version:
   ```powershell
   git add -A; git commit -m "SatPass iOS v1.0.1"
   git push
   git tag v1.0.1; git push origin v1.0.1
   ```
3. TestFlight testers get the update automatically

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Test connection` fails | Worker URL typo, or `http://` instead of `https://`. Re-run the Part 1.5 smoke test |
| `/tles` → 502 | CelesTrak hiccup — wait a few minutes and retry; the app falls back to cached TLEs and says so |
| "Add your Worker URL in Settings first" | Paste the URL from Part 1.4 into Settings |
| Workflow fails at Archive: signing/provisioning | Same four secrets as WalkLog — API key needs Admin (or App Manager); check they landed in *this* repo |
| `pilot upload`: app not found | Do step 2.1(1): the App Store Connect app record must exist before the first upload |
| No notifications arrive | Settings → SatPass → Notifications → Allow; then toggle the heads-up off and on to reschedule |
| Pass times drift from the CLI | Check the TLE age in the app footer — predictions degrade as TLEs age; pull to refresh |

**Notes worth knowing:** predictions are computed on your iPhone in about
a second — that's the SGP4 math running in JavaScriptCore, and it's why
the app works on cached TLEs with no signal. TLEs refresh every 12 hours
(like the CLI's disk cache); the footer always shows their age, and the
app falls back to stale cache with an honest warning if the Worker is
unreachable.
