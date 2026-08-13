# TLEWhereIs (iOS)

An iPhone companion to the [TLEWhereIs](https://github.com/robominds/TLEWhereIs)
CLI: track a satellite's live position, search for satellites by name or NORAD
ID, keep a history of previously tracked ones, and get a notification when
the tracked satellite rises above an elevation angle you set.

## Screens

- **Tracking** — the currently tracked satellite's latitude/longitude/altitude/
  speed, plus its elevation and azimuth relative to your location, updated
  live; and a predicted time/azimuth/elevation for its next closest approach
  (whether or not that approach clears the horizon).
- **Map** — the satellite's ground track (90 minutes behind and ahead of now),
  your location, and a day/night terminator overlay, on a MapKit map.
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

Closest approach works the same way but isn't threshold-gated: `PassPredictor`
scans up to 24h ahead for the next local minimum of range (a coarse pass to
bracket it, then a finer pass to refine), and reports the time, azimuth, and
elevation at that instant — which can be below the horizon if the satellite's
orbit just doesn't bring it overhead this time around.

The map's day/night terminator is computed in `SolarPosition` (low-precision
sun position — the standard textbook approximation, plenty for a visual
overlay). The terminator is the great circle 90° from the subsolar point in
every direction, so it's drawn as a single polygon spanning the full
longitude range, closed at whichever pole is currently in darkness. The
ground track and the app's periodic live-data refresh both run from a single
lifecycle hook on `ContentView` (the `TabView` container itself, not any one
tab) — see "Verified vs. not" below for why that matters.

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
the active toolchain. What's actually been verified:

- `swift test` — **36/36 passing** (TLE parsing/disambiguation, SGP4
  propagation sanity checks, pass-window and closest-approach detection,
  ground-track sampling, solar-position math, persistence round-trips). This
  caught real bugs during development: a malformed TLE line crashing the
  process instead of throwing (SatelliteKit's parser traps on out-of-range
  input; now guarded before the call), SatelliteKit returning longitude in
  `[0, 360)` instead of the conventional `[-180, 180]` (now normalized in
  `Propagator`), and TLE parsing breaking on CRLF line endings with
  interspersed blank lines (see below). The closest-approach tests include an
  end-to-end check against a real ISS TLE, confirming the found time is a
  genuine local minimum of range (not just some sample) by checking
  neighboring samples aren't closer. The solar-position tests check real
  equinox/solstice dates and, for the terminator, a date-independent
  geometric property (every terminator point is exactly 90° of great-circle
  distance from the subsolar point) rather than a hardcoded reference value.
- `xcodebuild build` for the iOS Simulator — **succeeds**, including Swift 6
  strict concurrency checking (which caught and fixed two data-race errors in
  `LocationManager`/background-task scheduling).
- Installed and launched on an iPhone 17 Simulator — **launches without
  crashing**; the tab bar, navigation title, and the CoreLocation permission
  prompt (with its custom usage-description text) all render correctly.
- **Search, on a physical iPhone** — initially failed with "no satellite
  found" for every query, including a plain NORAD ID. Root-caused via
  on-device console logging to a Celestrak response with CRLF endings and a
  blank line inserted after every real line — most likely a carrier or WiFi
  transparent compression proxy re-encoding the gzip response in transit,
  since `curl` against the identical URL (with or without requesting gzip)
  came back clean. `TLEFetcher`'s line-pairing logic only tolerated `"\n"`
  and plain-whitespace trimming, so a stray `"\r"` silently broke it down to
  zero results regardless of query. Fixed by splitting on any newline
  character and dropping blank lines before pairing; also hardened along the
  way: requests now bypass HTTP caching (TLE data is time-sensitive, and a
  cached bad response would otherwise keep replaying) and send an explicit
  browser-style `User-Agent` (some CDNs/WAFs treat iOS's default `CFNetwork`
  UA as bot traffic). Confirmed working after the fix.
- **Next Closest Approach**, on the iPhone 17 Simulator — seeded the app's
  persisted state directly (JSON file in the app container) with ISS as the
  tracked satellite and a San Francisco mock location, launched, and
  confirmed the Tracking screen renders a real predicted time and elevation
  for it (~88°, correctly near-overhead for that satellite/location pair at
  that moment) alongside the existing live position fields.
- **Map**, on the iPhone 17 Simulator — same seeded state, screenshotted the
  Map tab and confirmed the ground track, "You" pin, satellite marker, and
  night-side shading all render and land in sensible places. This caught a
  real bug: the periodic refresh loop (`AppModel.onAppear`) was wired to
  `TrackingView`'s `onAppear`, so a session that opened straight to the Map
  tab and never visited Tracking would never start it — MapKit's own
  default "zoom to my location" camera was the only thing that ever
  rendered (confirmed by screenshot: a street-level San Francisco
  intersection with no satellite data at all). Moved the lifecycle hook to
  `ContentView` (the `TabView` container, always present regardless of
  selected tab) and re-verified both tabs populate correctly on a fresh
  launch.

Not verified: History/Settings interaction flows (needs actual tapping —
`simctl` can drive install/launch/screenshots but not UI gestures — that
requires an XCUITest target, which isn't included here) and real on-device
notification delivery for a predicted pass. Set a low elevation threshold and
see whether a notification actually fires on a real pass before relying on
this for a specific observation.

## Known limitations

- Single "currently tracked" satellite drives notifications, matching the
  CLI's model — no independent notifications for multiple satellites at once.
- Pass predictions are sampled at 30-second resolution, not sub-second —
  fine for "get a heads-up a pass is starting," not for precise antenna
  pointing.
- No map/globe visualization.

## Acknowledgments

Built by Mark Castelluccio with Claude Code (Anthropic).
