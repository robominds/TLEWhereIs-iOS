# TLEWhereIs iOS App — Design

## Purpose

An iPhone app for tracking a satellite's current position, mirroring and extending
the `TLEWhereIs.py` CLI tool: pick a satellite to track (search or reuse a
previously tracked one), see its live position including elevation/azimuth
relative to the user's location, and get a notification when it rises above a
configurable elevation angle.

## Environment constraint

This machine has only Xcode Command Line Tools, not full Xcode — no `xcodebuild`,
no iOS simulator. The project is split so the parts that matter most for
correctness (orbital math, TLE parsing, name resolution, pass prediction) live in
a plain Swift Package that builds and tests via `swift build` / `swift test`
without Xcode. The SwiftUI app target cannot be compiled or run in this
environment; the user must open the generated `.xcodeproj` in Xcode to build,
sign, and run it on a device. The project file is generated with `xcodegen`
(installed via Homebrew, itself requiring only CLT) from a `project.yml` spec,
which avoids hand-authoring a fragile `project.pbxproj`.

## Architecture

```
TLEWhereIs-iOS/
  Package.swift                  # SPM manifest: TLEWhereIsCore library + SatelliteKit dep
  Sources/TLEWhereIsCore/
    TLERecord.swift              # TLE + satellite name/NORAD model
    TLEFetcher.swift             # Celestrak fetch; name/NORAD resolution with
                                  #   exact-match-else-list-candidates disambiguation
                                  #   (same fix applied to TLEWhereIs.py)
    Observer.swift               # Geodetic observer location value type
    Propagation.swift            # Wraps SatelliteKit: ECI/geodetic position,
                                  #   topocentric look angle (az/el/range)
    PassPredictor.swift          # Scans a time window for elevation-threshold
                                  #   crossings, returns predicted pass windows
    Store.swift                  # Codable persistence: tracked-satellite history,
                                  #   current satellite, per-satellite TLE cache,
                                  #   settings (threshold, location mode)
  Tests/TLEWhereIsCoreTests/     # swift test — runnable without Xcode
  App/
    TLEWhereIsApp.swift          # App entry point, notification delegate
    Views/
      TrackingView.swift         # current satellite: lat/lon/alt, speed,
                                  #   live elevation & azimuth vs. user location
      SearchView.swift           # Celestrak name search, disambiguation picker
      HistoryView.swift          # previously tracked satellites, tap to switch
      SettingsView.swift         # elevation threshold, location mode, notifications
    LocationManager.swift        # CoreLocation wrapper; GPS with manual override
    NotificationScheduler.swift  # UNUserNotificationCenter + BGTaskScheduler
  project.yml                    # xcodegen spec -> TLEWhereIs.xcodeproj
  README.md
```

### Dependency

[SatelliteKit](https://github.com/gavineadie/SatelliteKit) (SPM) — Vallado-validated
SGP4/SDP4 propagation and topocentric look-angle math, already shipping in iOS
apps. Avoids reimplementing orbital mechanics.

## Data flow

1. **Selecting a satellite** (search result tap, or history list tap) sets it as
   "currently tracked," fetches its latest TLE (Celestrak, falling back to the
   per-satellite cache on failure — same behavior as the CLI), and moves it to
   the front of the persisted history list.
2. **Foreground display**: a timer (~5s) recomputes the tracked satellite's
   geodetic position and, using the current location from `LocationManager`,
   its topocentric elevation/azimuth/range. `TrackingView` re-renders on each
   tick.
3. **Notification scheduling**: whenever the tracked satellite, TLE, observer
   location, or elevation threshold changes, `PassPredictor` recomputes upcoming
   passes over the next 5 days (capped to stay under iOS's 64-pending-local-
   notification limit) and reschedules one `UNNotificationRequest` per pass, fired
   at the moment elevation first crosses the threshold. Stale pending
   notifications are cancelled before rescheduling. A `BGAppRefreshTask` also
   triggers this on a best-effort periodic basis, since iOS does not guarantee
   background execution timing.

## Persistence

Plain `Codable` structs written to a JSON file in the app's Application Support
directory (no SwiftData/CoreData — the data model is simple: a small list of
tracked satellites, one TLE cache entry each, and a settings struct). Chosen over
`UserDefaults` because per-satellite TLE cache entries can grow past what
`UserDefaults` is meant for.

## Error handling

- Celestrak fetch fails -> fall back to cached TLE for that satellite, show a
  warning banner (mirrors the CLI's cache fallback).
- No cache and no network -> explicit error state in `TrackingView`, not a
  silent stale value.
- Ambiguous search match (e.g. "ISS" matching multiple catalog entries) -> show
  the candidate list instead of guessing, same principle as the CLI fix.
- Location permission denied -> prompt to switch to manual location entry in
  Settings; elevation/azimuth and notifications are unavailable until a location
  is set one way or the other.

## Testing

`TLEWhereIsCoreTests` (runs via `swift test`, no Xcode needed):
- TLE line parsing and NORAD ID extraction
- Name resolution: exact match wins; multiple non-exact matches raise with the
  candidate list; single match succeeds
- Look-angle sanity check against a known TLE + observer + expected az/el
- Pass-window detection over a synthetic elevation time series (rising/falling
  edges, multiple passes, no passes)

The SwiftUI app itself is not build-verified in this environment. The user opens
`TLEWhereIs.xcodeproj` in Xcode to build, resolve the SatelliteKit SPM
dependency, set a signing team, and run on-device.

## Out of scope (for this iteration)

- Multiple simultaneously-tracked satellites with independent notifications
  (matches the CLI's single "currently tracked" model)
- Map/globe visualization
- watchOS/companion targets
