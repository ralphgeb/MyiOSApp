# CLAUDE.md — Ahead (iOS calendar widget app)

Project guide for future sessions. Full history and rationale: `PROJECT_NOTES.md`.

## What this is
**Ahead** — iPhone calendar widgets (home + lock screen) plus a companion app. Owner: Ralph (individual Apple developer, **no Mac**; everything builds in GitHub Actions and ships to TestFlight).

- Repo: `ralphgeb/MyiOSApp`, project root `CalendarWidgetApp/` (XcodeGen, `project.yml`)
- Bundle IDs: app `com.ralphgeb.calendarwidgetapp`, widget `com.ralphgeb.calendarwidgetapp.widget`
- App Group: `group.com.ralphgeb.calendarwidgetapp` (app ↔ widget share UserDefaults)
- IAP (non-consumable, £1.99): `com.ralphgeb.calendarwidgetapp.unlock`, branded **Ahead Plus**
- Sister apps (same owner/workflow): Halo (`ralphgeb/FridgeCheck`, `HaloApp`), Scout (`ralphgeb/ScoutAI`)
- Targets: iOS 17+ deployment, iPhone only (`TARGETED_DEVICE_FAMILY: "1"`, no iPad anything), Swift 5 mode, Xcode 27 on the `xcode-27` runner (same as Halo)

## Layout
```
.github/workflows/build-ios.yml   build + TestFlight upload (workflow_dispatch only)
CalendarWidgetApp/
  project.yml                     XcodeGen spec (edit this, never a .xcodeproj)
  Sources/   app: CalendarWidgetApp.swift, CalendarTabView.swift, ContentView.swift (Settings),
             Store.swift (StoreKit 2 + paywall), Look.swift (AppTheme), Onboarding.swift,
             Duo.swift (Distribution.isTestFlight, orientation app delegate, simulator sample events)
  Shared/    compiled into BOTH targets: SharedSettings.swift, Presets.swift, Weather*.swift
  Widget/    CalendarWidget.swift, PageIntent.swift (paging), Weather.swift (widget-side fetch)
docs/ + root index/privacy/support.html   PUBLIC GitHub Pages (never put notes/secrets here)
CLAUDE.md, PROJECT_NOTES.md       internal docs (repo root, not in docs/)
```

## Release workflow (standing procedure)
1. Edit code → commit (with the attribution lines) → push to `main`.
2. `gh workflow run build-ios.yml` then poll **`gh run list --workflow build-ios.yml`** (always filter by workflow — the Pages workflow also runs and was once polled by mistake).
3. Check annotations (`gh api .../check-runs/.../annotations`) for errors/warnings.
4. Tell the user the **TestFlight build number = run number** of build-ios.yml. If the upload could not be verified, say so plainly — never claim "uploaded" without evidence.
5. Concurrent uploads can fail with a "buildUpload relationship" error → wait and retry.
6. Experiments go on a branch (e.g. `glass`), keep `main` intact.
7. The same run also builds for the simulator and publishes `Ahead-simulator.zip` (release `ios-simulator-latest`) for Appetize.io. Input `target`: both / testflight / simulator.

The workflow deletes old Apple Development certificates via the App Store Connect API before each build (continue-on-error) so Apple's certificate limit never blocks CI. Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`, `APPLE_TEAM_ID`. Never print or commit them.

## Product rules
- **Free:** small (2×2) and large (4×4) home widgets, 3 days ahead (`SharedSettings.freeDays`), ONE theme chosen in onboarding (default Graphite), Automatic/Light/Dark mode.
- **Ahead Plus:** medium + extra-large widgets, both Lock Screen widgets, calendar selection, custom colors (background, text, highlight, highlighted-date text, cards), all themes, days shown, all-day toggle.
- Locked widget families show a message instead of events.
- No fake/test payment paths or diagnostic UI in shipped builds.
- US English, sentence-case UI strings.

## Architecture patterns
- **All cross-process state lives in `SharedSettings`** (App Group UserDefaults). Any change that affects widgets must call `SharedSettings.reloadWidgets()`; app redraws use the `.colorsChanged` notification.
- **Widget look:** `reloadWidgets()` first writes `look.json` (colors, appearance mode, isPro) to the App Group container and the widget reads it from there (UserDefaults could reach the widget late → old colors), then reloads twice (now and +1.2 s). Light/Dark/Automatic in the app is set with `InterfaceStyle.apply()` on the windows, not `preferredColorScheme` (it stuck after going back to Automatic).
- **Colors:** `RGBA` (opacity always 1) → `ColorSet {background,text,highlight,highlightText,card}` → `ColorSettings.resolved(for: scheme)`. Widgets read `SharedSettings.effectiveColorSettings` (Plus → user colors; free → the chosen preset). Presets in `Shared/Presets.swift` (`LookPreset`: Graphite, Ocean, Forest, Mono, Dusk, Sand, Sky, Blush; Sky/Blush are light in both modes). Editing a color sets `presetID = "custom"`.
- **App chrome** themed by `AppTheme` (`Sources/Look.swift`); `AppearanceMode` applied via `preferredColorScheme`. Toggles use `.tint(theme.accent)`; never tint with ink (white-on-white bugs).
- **Widgets can't scroll:** per-family paging in the App Group (`Pager`, `PageIntent`), reset on resize or 15 min idle; page change via `.id(pageIndex)` + `.transition(.push)`. Events are chunked by measured height (`Cost`).
- **Weather (WeatherKit) cost design:** one hourly call → 24 stored hours (`WeatherForecast`); widget picks the icon per timeline entry with `SharedSettings.weather(at:)`. Refresh rules in `weatherNeedsRefresh`: 15-min throttle; refresh if none / <4h covered / moved >10 km; skip 23:00–06:00 while >1h covered; widget location check ≤ every 2h; fetch has timeouts (location 3s, whole refresh 5s).
- **Calendar tab:** pinned overlay header over a ScrollView with an equal-height spacer; month grid folds as the list scrolls (today's row pins); `dayTops` via PreferenceKey; scroll offset via `onScrollGeometryChange` (iOS 18) with `#available` + preference fallback; orange circle follows the first-seen day; dots = upcoming events (max 3).
- iOS 18/27 APIs must be availability-gated (deployment target is 17). `systemExtraLargePortrait` is behind `#if compiler(>=6.4)`.
- **iPhone Duo:** the app delegate allows rotation only on a big screen (short side ≥ 560 pt), portrait elsewhere; `refreshOrientations()` runs when the screen folds/opens. Calendar tab: landscape + wide (≥700 pt) → still month on the left, scrolling events on the right, circle follows the day at the top; upright → the normal folding calendar. Onboarding pages max 560 pt wide.
- **TestFlight vs App Store:** one build; `Distribution.isTestFlight` (sandbox receipt, or DEBUG/simulator) shows the TestFlight section at the bottom of Settings: show the start screens again, reset to free version (`Store.forcedFree`, cleared by buying/restoring). Simulator: Plus unlocked and sample events added once.
- Permissions are requested **after** onboarding (`.task(id: onboarded)`), calendar = full access.

## Pitfalls we hit
- Don't name things `set` (Swift keyword clash). Add `import CoreLocation` where `CLLocation` is used in Shared.
- Python-scripted edits: assert the `old` string is non-empty and found exactly once (an empty `old` once corrupted a file).
- Animation on Settings theme cards made recoloring look slow → `.animation(nil, value: paletteTick)`.
- GitHub Pages content is public; keep internal docs out of `docs/`.
- Existing pre-onboarding users have `freeThemeID == nil` → they keep the original look.

## User preferences
- When the user says "question, don't do it", answer only.
- Confirm before destructive/public actions.
- Be honest about unverified uploads; give the build number each time.
- Keep replies short; the user is often on a phone.

## Open items
- **App Review 1.0 rejected under Guideline 4.3(a) (spam)**, submission `7bc39548-98fd-4528-9127-45245b1bfb9f`; name was "Ahead: Simple calendar widgets". Needs a Resolution Center reply and/or differentiated name/subtitle/screenshots/description.
- Confirm the IAP product exists/active in App Store Connect (Paid Apps Agreement) and rename its display name to "Ahead Plus".
- Enable GitHub Pages (Settings → Pages → main) so privacy/support URLs resolve: `https://ralphgeb.github.io/MyiOSApp/privacy.html`, `/support.html`.
- Latest TestFlight build: **88** (branch `claude/laughing-allen-f2cvag`, commit be21ac2). Appetize: https://appetize.io/app/rvxaazcudw7zvlgfy3cdzmb4m4
