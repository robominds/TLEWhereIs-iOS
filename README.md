# TLEWhereIs (iOS)

An iPhone companion to the [TLEWhereIs](https://github.com/robominds/TLEWhereIs)
CLI: track a satellite's live position, search for satellites by name or NORAD
ID, keep a history of previously tracked ones, and get a notification when
the tracked satellite rises above an elevation angle you set.

## Screens

- **Tracking** — the currently tracked satellite's latitude/longitude/altitude/
  speed, plus its elevation and azimuth relative to your location, updated
  live.
- **Search** — searches Celestrak by name or NORAD ID; tap a result to start
  tracking it.
- **History** — satellites you've tracked before, most recent first; tap to
  switch back to one.
- **Settings** — elevation threshold for notifications, location source
  (device GPS or manual lat/lon), and a notifications on/off toggle.

## How it works

There's no public SPICE SPK ephemeris for most satellites, so — same as the
CLI — the position comes from propagating the satellite's latest TLE with
SGP4/SDP4, via [SatelliteKit](https://github.com/gavineadie/SatelliteKit).
The app is split into two pieces:

- **`TLEWhereIsCore`** (`Sources/`, `Tests/`) — a plain Swift Package with the
  TLE fetch/parse/disambiguation logic, the SatelliteKit propagation wrapper,
  pass prediction, and on-disk persistence. No UIKit/SwiftUI dependency, so it
  builds and tests with `swift build` / `swift test` alone.
- **The app target** (`App/`) — SwiftUI views, CoreLocation, and
  `UNUserNotificationCenter`/`BGTaskScheduler` glue on top of
  `TLEWhereIsCore`.

Notifications work by *predicting* upcoming passes (next ~5 days) rather than
polling in the background, since iOS doesn't guarantee background execution
timing: `PassPredictor` scans ahead for elevation-threshold crossings and one
local notification is scheduled per pass, firing the moment it rises above
your threshold. Predictions are rescheduled whenever the tracked satellite,
location, or threshold changes, on app foreground, and on a best-effort
`BGAppRefreshTask`.

## Setup

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) (the project file
   itself isn't committed — it's generated from `project.yml` — since
   generated `.xcodeproj` files churn badly in git):
   ```bash
   brew install xcodegen
   ```
2. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```
3. Open `TLEWhereIs.xcodeproj` in Xcode, select your team under Signing &
   Capabilities, and run on a simulator or your device.

`TLEWhereIsCore` can also be built and tested standalone, without opening
Xcode at all:
```bash
swift test
```

## Verified vs. not

This was built in an environment with Xcode 26 available but not selected as
the active toolchain. What's actually been verified here:

- `swift test` — **22/22 passing** (TLE parsing/disambiguation, SGP4
  propagation sanity checks, pass-window detection, persistence round-trips).
  This caught two real SatelliteKit-integration bugs during development: a
  malformed TLE line crashing the process instead of throwing (SatelliteKit's
  parser traps on out-of-range input; now guarded before the call), and
  SatelliteKit returning longitude in `[0, 360)` instead of the conventional
  `[-180, 180]` (now normalized in `Propagator`).
- `xcodebuild build` for the iOS Simulator — **succeeds**, including Swift 6
  strict concurrency checking (which caught and fixed two data-race errors in
  `LocationManager`/background-task scheduling).
- Installed and launched on an iPhone 17 Simulator — **launches without
  crashing**; the tab bar, navigation title, and the CoreLocation permission
  prompt (with its custom usage-description text) all render correctly.

Not verified: the Search/History/Settings interaction flows (needs actual
tapping — `simctl` can drive install/launch/screenshots but not UI
gestures — that requires an XCUITest target, which isn't included here) and
real on-device push/notification delivery. Try the golden path — search for a
satellite, track it, set a low elevation threshold, and see whether a
notification fires on a real pass — before relying on this for a specific
observation.

## Known limitations

- Single "currently tracked" satellite drives notifications, matching the
  CLI's model — no independent notifications for multiple satellites at once.
- Pass predictions are sampled at 30-second resolution, not sub-second —
  fine for "get a heads-up a pass is starting," not for precise antenna
  pointing.
- No map/globe visualization.

## Acknowledgments

Built by Mark Castelluccio with Claude Code (Anthropic).
