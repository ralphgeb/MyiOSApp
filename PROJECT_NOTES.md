# Ahead — Project Notes

Detailed documentation of the project as built over roughly a month of sessions: requirements, architecture, design decisions, history, and open items. For the short guide see `CLAUDE.md`. No secrets are recorded here.

---

## 1. Overview

**Ahead** is an iPhone app of calendar widgets (home screen and Lock Screen) with a companion app for setup, settings and a calendar view. It reads the user's Apple Calendar through EventKit (including every account synced there), shows upcoming events grouped by day, and optionally shows a weather icon.

The owner is an individual Apple developer without a Mac. All builds run in GitHub Actions (macos-latest, Xcode 26.6 / Swift 6.3.3 at last check) and upload to TestFlight through an App Store Connect API key. The project was previously called **Minimal**; it was renamed **Ahead** ("See what's next" → "Your next days at a glance" as the tagline).

| Item | Value |
|---|---|
| Bundle ID | com.ralphgeb.calendarwidgetapp |
| Widget bundle ID | com.ralphgeb.calendarwidgetapp.widget |
| App Group | group.com.ralphgeb.calendarwidgetapp |
| IAP product | com.ralphgeb.calendarwidgetapp.unlock (non-consumable, £1.99) |
| BG task id | com.ralphgeb.calendarwidgetapp.refresh |
| Repo | ralphgeb/MyiOSApp (project root `CalendarWidgetApp/`) |
| Pages | https://ralphgeb.github.io/MyiOSApp/ (index, privacy.html, support.html) |
| Deployment target | iOS 17.0, iPhone only |
| Display names | App: "Ahead"; widget extension: "Upcoming Events" |

Sister apps by the same owner using the same pipeline: **Halo** (repo ralphgeb/FridgeCheck, folder `HaloApp`) and **Scout** (ralphgeb/ScoutAI). Halo's Theme/Appearance/Settings/Onboarding code was the style reference for Ahead's themed Settings and onboarding.

## 2. Requirements

### Functional
- Home widgets: small (2×2), medium, large (4×4), extra large (iPad-only variant dropped when the app became iPhone-only; iOS 27 `systemExtraLargePortrait` guarded by `#if compiler(>=6.4)`).
- Lock Screen widgets: a 3-event rectangular widget (always three events, with a "Tomorrow"/date label) and a "next event" widget (title same size as the date but bolder, location thin italic, three lines, light dash, maximised to fit).
- Interactive paging in widgets via AppIntent buttons (widgets can't scroll).
- Calendar tab with a month grid that folds into a week strip as the event list scrolls.
- Settings: calendars to include, appearance (Automatic/Light/Dark), themes, custom colors, days shown, all-day toggle, weather, unlock/restore purchase.
- Weather icon per widget time slot, powered by WeatherKit, with Apple Weather attribution in Settings.
- Onboarding: Welcome → theme choice → explanation cards → start.
- Updates to events (EKEventStoreChanged) reload widgets; BGAppRefresh keeps data fresh.

### Monetization
One-time purchase "Ahead Plus" £1.99 (StoreKit 2).
- **Free:** small and large widgets, 3 days ahead, one theme (chosen in onboarding, default Graphite), appearance mode.
- **Plus:** medium and extra-large widgets, both Lock Screen widgets, calendar selection, custom colors (background, text, highlight, highlighted-date text, cards), all other themes, days shown, all-day toggle.
- The user explicitly rejected any fake/test payment path. The product must exist and be active in App Store Connect (Paid Apps Agreement in force) for purchases to work.
- Apple's standard EULA is sufficient (no subscription), so no custom EULA in the description.

### Non-functional / policy
- US English strings, sentence case.
- Privacy: calendar data never leaves the device; location is used only for weather; no analytics/tracking. Privacy manifests (`PrivacyInfo.xcprivacy`) exist for app and widget.
- Info.plist: `NSCalendarsFullAccessUsageDescription`, `NSLocationWhenInUseUsageDescription` ("Ahead uses your location to show the weather icon. Everything else works without it, but no icon will be shown."), `NSWidgetWantsLocation`, `ITSAppUsesNonExemptEncryption: false`, `UIBackgroundModes: fetch`.
- Entitlements: App Group and `com.apple.developer.weatherkit` for both targets.

## 3. Repository and build

```
.github/workflows/build-ios.yml
CalendarWidgetApp/
  project.yml
  Sources/    CalendarWidgetApp.swift  CalendarTabView.swift  ContentView.swift
              Store.swift  Look.swift  Onboarding.swift  PrivacyInfo.xcprivacy
              Assets.xcassets/AppIcon.appiconset/icon-1024.png
  Shared/     SharedSettings.swift  Presets.swift  WeatherFetcher.swift
              WeatherIconData.swift  WeatherIconName.swift  WeatherIconView.swift
  Widget/     CalendarWidget.swift  PageIntent.swift  Weather.swift  PrivacyInfo.xcprivacy
docs/  index.html privacy.html support.html (+ copies at repo root)
```
About 3,000 lines of Swift. `Shared/` is compiled into both targets.

### CI workflow (`build-ios.yml`, manual `workflow_dispatch`)
1. Checkout.
2. Validate secrets (format checks for team ID, key ID, issuer UUID, PEM markers; stray whitespace is tolerated and trimmed).
3. Save the `.p8` key to `$RUNNER_TEMP/AuthKey.p8`.
4. **Remove old Development certificates** (Python + PyJWT ES256 → App Store Connect API; lists `DEVELOPMENT,IOS_DEVELOPMENT` certs and deletes them; `continue-on-error`). Added because every CI build created a new Apple Development certificate and hit Apple's limit, failing many builds.
5. Select the newest non-beta Xcode.
6. `brew install xcodegen && xcodegen generate`.
7. `xcodebuild archive` with `-allowProvisioningUpdates` and the API key; `CURRENT_PROJECT_VERSION = github.run_number`; on failure, error lines are surfaced as annotations.
8. Upload logs on failure.
9. `xcodebuild -exportArchive` with `destination: upload` to TestFlight.

**TestFlight build number = run number of build-ios.yml.** Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`, `APPLE_TEAM_ID`.

### Release procedure
Commit with attribution → push to main → run workflow → poll `gh run list --workflow build-ios.yml` → read annotations → report build number. Be honest when the upload is unverified. If a "buildUpload relationship" error appears (overlapping uploads), wait and retry.

## 4. Shared state and data model

`SharedSettings` (Shared/SharedSettings.swift) is the single source of truth, stored in App Group `UserDefaults`.

- Constants: `widgetKind = "CalendarListWidget"`, `nextEventKind = "NextEventLockWidget"`, `freeDays = 3`, `reloadWidgets()`.
- Colors: `RGBA` (opacity always 1), `ColorSet { background, text, highlight, highlightText, card }` (+ `isEmpty`), `ColorSettings` with `resolved(for: scheme)`, `updateColors` (sets `presetID = "custom"`), `applyPreset(id:light:dark:)`, `presetID`, `freeThemeID`, `effectiveColorSettings`, `resetColors` (clears presetID).
- `AppearanceMode` (automatic/light/dark) + `appearanceMode`; widgets use `appearanceMode.scheme ?? systemScheme`.
- Purchase and options: `isPro`, `hiddenCalendarIDs`, `daysAhead`, `showAllDay`.
- Weather: `WeatherForecast { fetched, lat, lon, hours[start, code, isDay], coveredUntil }`, `forecast`, `weather(at:)`, `weather`, `weatherNeedsRefresh(lat:lon:)`, `weatherLastAttempt`, `lastCoordinate`, `weatherLastLocationCheck`.

## 5. Theming system

- `Shared/Presets.swift`: `RGBA(hex:)`, `luminance`, `mixed(with:)`, `LookPreset` with light and dark tuples (ink / background / card + accent). Auto-contrast chooses `highlightText`. Presets: **Graphite (default free), Ocean, Forest, Mono, Dusk, Sand, Sky, Blush**. Sky and Blush are light in both modes. `LookPreset.find(_:)`.
- Free users get the one theme they chose in onboarding (`freeThemeID`); Plus users can switch themes or set custom colors. Themes other than the free one show a lock badge in the Settings preset row.
- "Same colors in Light and Dark" toggle in Settings.
- `AppTheme` (Sources/Look.swift) drives app chrome: ink, accent, accentText, background, card, barScheme. `.colorsChanged` notification triggers redraws. RootView tints with ink and applies `preferredColorScheme`.
- Lessons: toggles must be tinted with accent (ink tint produced white toggles); the "Calendar access needed" button uses accent background + accentText; recolor animation is disabled in Settings so cards update instantly; presets trigger an immediate widget reload.
- Highlight/"Highlighted Date Text" and "Cards" color pickers were added on request. Top text colors: first two lines and the dates use the same color at 50% opacity.

## 6. Widgets

- `Provider` builds a timeline of entries; each entry carries colors (`SharedSettings.effectiveColorSettings`), events, page and weather icon for that time (`SharedSettings.weather(at: date)`).
- Layout: height-based chunk fitting using a `Cost` enum so rows never clip; large widgets page through days/events.
- `Pager` / `PageIntent`: interactive `Button(intent:)` paging per family, stored in App Group, resets on resize or after 15 idle minutes; slide via `.id(pageIndex)` + `.transition(.push)`.
- Lock Screen: `lockScreen` view (always 3 events, `lockLine`, `dayLabel`: today/tomorrow/date) and `NextEventLockView` (3 lines, size 16.5, light dash, thin italic location).
- Paid families for free users render a "locked" message.
- Weather fetch inside the widget is wrapped in `withTimeout(5)`; `LocationProvider` has a 3s timeout.
- Experiment on branch `glass`: Liquid Glass-style widget background (`ultraThinMaterial` containerBackground via a `widgetBackground` extension). It was reviewed and the user chose to revert; it is **not** in main. Note the system's translucent Lock Screen widgets (battery etc.) are a system style, not something the app controls.

## 7. Calendar tab (Sources/CalendarTabView.swift)

Design iterated heavily from user screenshots:
- Pinned overlay header (date header + calendar block) over a `ScrollView`; a spacer equal to the full header height keeps the list below it.
- Month grid at launch shows the full month; as the user scrolls, rows move with the finger, today's row pins, other rows slide away, ending in a single-row ribbon of days which slides horizontally.
- Orange circle = first-seen day (`cur` computed from group tops ≤ v+2); same orange everywhere; slightly smaller circle; no divider line above weekday letters; larger gap under the strip; date text close to the circle.
- Dots under days = upcoming events (max 3). Tap a day to scroll the list to it.
- `dayTops` collected via `DayTopKey`; scroll offset via `onScrollGeometryChange` (iOS 18) with `ScrollTopKey` preference fallback on iOS 17 (`ScrollTracker` modifier). Scroll value clamped at ≥ 0 (fixed a stuck "28 Oct" highlight on pull-down).
- `load()` uses `store.refreshSourcesIfNecessary()` and a window beginning at the grid start so newly added events appear.
- `CalendarAccessNeededView`: async allow, with "Open Settings" logic for never-asked/write-only statuses.

## 8. Weather and cost design

WeatherKit (500k calls/month included with the Developer Program; paid tiers $49.99/1M, $249.99/5M, $499.99/10M, $999.99/20M, $4,999.99/100M).
- One hourly call → 24 saved hours → widget picks the icon per timeline entry; no per-entry API calls.
- `weatherNeedsRefresh`: 15-minute throttle; refresh when no forecast, under 4h left, or moved >10 km; skip 23:00–06:00 when >1h still covered; widget location check at most every 2 hours.
- Settings shows Apple Weather attribution; the explanatory footer under the weather section was removed on request.
- Discussed and **not built**: a scheduled GitHub Actions job producing per-city weather JSON hosted on Pages/Cloudflare with on-device nearest-city lookup (user said "question, don't do it").

## 9. Onboarding (Sources/Onboarding.swift)

`RootView` shows `OnboardingView` until `@AppStorage("onboarded")`:
1. **Welcome:** `AheadMark` (four animating bars), "Ahead" bold ~22pt (not uppercase), thin subtitle "Your next days at a glance", "Get started". Logo ~15% smaller and raised; the subtitle appears ~0.5s faster.
2. **ThemePage:** eight theme cards with live preview; the choice becomes the free theme (`freeThemeID`), others are Plus.
3. **ExplainPage:** three cards — links with Apple Calendar widgets; needs full calendar access (nothing goes to the cloud); needs location for weather (no data collected).
4. **Start.**
Permissions are requested after onboarding. `PillButton(title:tick:action:)` is the shared button.

## 10. App Store state and history

- Icon: near-black gray with one bright bar and three softer bars.
- Privacy policy and support pages are on GitHub Pages (public). The 404s at first came from Pages not enabled/wrong folder; fixed by keeping copies in `docs/` and the repo root. Pages must be enabled in repo settings.
- Review fixes done: iPhone-only build (removed iPad screenshots requirement/orientations issue), URLs, usage descriptions, privacy manifest.
- Review notes for App Review were drafted (similar in style to the user's other apps).
- **Rejection:** Guideline 4.3(a) Design – Spam on version 1.0, submission ID `7bc39548-98fd-4528-9127-45245b1bfb9f`, app name at the time "Ahead: Simple calendar widgets"; Apple noted the extended review. Likely factors: generic name/subtitle in a crowded category, shared design/onboarding with sister apps, many similar calendar widget apps. Suggested actions: reply in Resolution Center (App Store Connect → the app → App Review → Resolution Center, also via the email notice) explaining the unique features (folding calendar, paging widgets, weather-by-slot icons, themes), and/or revise name, subtitle, screenshots, description and keywords. The user has not chosen yet.
- Last known TestFlight build: **84**, commit `b942e17` ("Theme page in setup, free theme + Ahead Plus, light Sky and Blush themes, remove test sentence, faster subtitle").

### Build/error history worth remembering
| Problem | Fix |
|---|---|
| Certificate limit failures | Cert cleanup step in workflow |
| `onScrollGeometryChange` iOS 18 only | `#available` + preference fallback |
| Scripted edit with empty `old` corrupted a file | Restored from git, redo with assertions |
| `set` identifier clash | Renamed to `makeSet` / `colors` |
| Missing `import CoreLocation` | Added in SharedSettings |
| Upload overlap error | Retry after delay |
| Polled wrong workflow | Always `--workflow build-ios.yml` |
| Reported "uploaded" when archive failed | Corrected; now rely on annotations and state honestly |
| Calendar tab strip not moving, wrong highlighted day | New scroll tracking; `p`/`cur` from group tops |
| Slow Settings recolor | No animation, immediate reload |
| White toggles / white-on-white button | accent tint + accentText |
| "Open Settings" doing nothing | New status-based logic |

## 11. Decisions log

- iPhone only (simpler review, no iPad screenshots).
- One-time unlock rather than subscription; free tier is genuinely useful (small + large widgets, one theme) with Plus for breadth and customisation.
- Free users choose one theme in onboarding; the rest sit behind Plus.
- No Liquid Glass widget background in main (branch only).
- Weather: minimise calls rather than build a server.
- Certificates: delete old Development certs every build.
- Rename Minimal → Ahead; Halo/Scout share style but should be differentiated if review keeps flagging spam.
- Preferences: confirm before destructive/public actions; don't implement when told "question, don't do it"; keep main intact for experiments.

## 12. iPhone Duo, TestFlight tools and tidy-up (Nov 16)

- iPad removed completely (iPad orientations, extra large widget, two-column widget paging).
- iPhone Duo support modelled on Halo: Xcode 27 runner, orientation app delegate (big screen turns, ordinary iPhone stays portrait), side-by-side Calendar tab in landscape (still month left with a moving circle, scrolling events right), onboarding kept to a phone's width.
- TestFlight section in Settings (TestFlight/simulator only): show the start screens again, reset to free version.
- Simulator build zipped for Appetize.io in the same workflow (release `ios-simulator-latest`); in the simulator Plus is unlocked and a week of sample events is added once.
- Tidy: sentence-case Settings strings, widget lock messages name Ahead Plus, one Store for the whole app, stale comments fixed.

## 13. Open items / next steps

1. Respond to or resolve the 4.3(a) rejection (Resolution Center reply and/or revised metadata; options include new subtitle/keywords/description and more distinctive screenshots).
2. Verify the IAP exists, is "Ready to Submit", attached to the version, and rename display name to "Ahead Plus"; confirm Paid Apps Agreement is active.
3. Enable GitHub Pages and confirm privacy/support URLs load.
4. Update the App Store listing name consistently with the app.
5. Consider a one-time migration so users who skipped the new theme page choose a free theme.
6. Optional: server-side weather cache if scale demands it.
