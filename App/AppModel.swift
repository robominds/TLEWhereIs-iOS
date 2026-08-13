import Foundation
import Observation
import TLEWhereIsCore

@Observable
@MainActor
final class AppModel {
    private let store: Store
    private let notificationScheduler: NotificationScheduler
    let locationManager: LocationManager

    private(set) var state: AppState
    var currentPosition: SatellitePosition?
    var currentLookAngle: LookAngle?
    var nextClosestApproach: (time: Date, lookAngle: LookAngle)?
    var groundTrack: [GroundTrackPoint] = []
    var subsolarPoint: SubsolarPoint?
    var errorMessage: String?

    private var propagator: Propagator?
    private var refreshTask: Task<Void, Never>?
    private var mapRefreshTask: Task<Void, Never>?

    init(
        store: Store = Store(),
        locationManager: LocationManager = LocationManager(),
        notificationScheduler: NotificationScheduler = NotificationScheduler()
    ) {
        self.store = store
        self.locationManager = locationManager
        self.notificationScheduler = notificationScheduler
        self.state = store.load()
        if let tle = state.current?.cachedTLE {
            self.propagator = try? Propagator(record: tle)
        }
    }

    var observer: Observer? {
        switch state.settings.locationMode {
        case .gps: locationManager.observer
        case .manual: state.settings.manualObserver
        }
    }

    func onAppear() {
        if state.settings.locationMode == .gps {
            locationManager.requestAuthorization()
        }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshCurrentPosition()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        // Ground track/subsolar point barely change second to second, so
        // this refreshes far less often than the live position above.
        mapRefreshTask?.cancel()
        mapRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshMapData()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func onDisappear() {
        refreshTask?.cancel()
        mapRefreshTask?.cancel()
    }

    /// Fetches and starts tracking the satellite matching `identifier`
    /// (a name or NORAD ID already resolved to one candidate — see
    /// `TLEFetcher.fetchCandidates` for picking among ambiguous matches).
    func track(identifier: String) async {
        errorMessage = nil
        do {
            let record = try await TLEFetcher.fetch(identifier: identifier)
            propagator = try Propagator(record: record)
            state = try store.trackSatellite(record)
            await refreshCurrentPosition()
            await refreshClosestApproach()
            await refreshMapData()
            await refreshPassPredictions()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Re-tracks a satellite already in history: refreshes its TLE from
    /// Celestrak, falling back to the cached one on failure (same behavior
    /// as the CLI).
    func selectFromHistory(_ satellite: TrackedSatellite) async {
        errorMessage = nil
        do {
            let record = try await TLEFetcher.fetch(identifier: String(satellite.noradID))
            propagator = try Propagator(record: record)
            state = try store.trackSatellite(record)
        } catch {
            guard let cached = satellite.cachedTLE, let cachedPropagator = try? Propagator(record: cached) else {
                errorMessage = Self.describe(error)
                return
            }
            propagator = cachedPropagator
            state = (try? store.trackSatellite(cached)) ?? state
            errorMessage = "Using cached data — \(Self.describe(error))"
        }
        await refreshCurrentPosition()
        await refreshClosestApproach()
        await refreshMapData()
        await refreshPassPredictions()
    }

    func requestNotificationAuthorization() async -> Bool {
        await notificationScheduler.requestAuthorization()
    }

    /// Best-effort background refresh entry point (called from a
    /// `BGAppRefreshTask`): re-fetches the tracked satellite's TLE and
    /// reschedules pass notifications so they stay accurate even when the
    /// app hasn't been opened in a while. iOS does not guarantee this runs
    /// on any particular schedule.
    func refreshInBackground() async {
        guard let current = state.current else { return }
        if let record = try? await TLEFetcher.fetch(identifier: String(current.noradID)) {
            propagator = try? Propagator(record: record)
            state = (try? store.trackSatellite(record)) ?? state
        }
        await refreshPassPredictions()
    }

    func updateSettings(_ transform: (inout Settings) -> Void) {
        state = (try? store.updateSettings(transform)) ?? state
        Task {
            await refreshClosestApproach()
            await refreshPassPredictions()
        }
    }

    private func refreshCurrentPosition() async {
        guard let propagator else {
            currentPosition = nil
            currentLookAngle = nil
            return
        }
        currentPosition = try? propagator.position()
        if let observer {
            currentLookAngle = try? propagator.lookAngle(from: observer)
            // Covers the case where GPS wasn't ready yet when the satellite
            // was first tracked: computed once as soon as a location shows
            // up, rather than on every 5s tick.
            if nextClosestApproach == nil {
                await refreshClosestApproach()
            }
        } else {
            currentLookAngle = nil
        }
    }

    /// Scans ahead (up to 24h) for the next point of minimum range — not
    /// gated on being above the horizon, since a pass that never clears the
    /// horizon still has a well-defined closest approach.
    private func refreshClosestApproach() async {
        guard let propagator, let observer else {
            nextClosestApproach = nil
            return
        }
        nextClosestApproach = try? PassPredictor.nextClosestApproach(
            propagator: propagator, observer: observer, from: Date()
        )
    }

    /// Ground track spans 90 minutes behind and ahead of now — comfortably
    /// more than one LEO orbital period in each direction — plus the
    /// current subsolar point, for drawing the day/night terminator.
    private func refreshMapData() async {
        subsolarPoint = SolarPosition.subsolarPoint()
        guard let propagator else {
            groundTrack = []
            return
        }
        groundTrack = (try? propagator.groundTrack(
            from: Date().addingTimeInterval(-90 * 60), duration: 180 * 60, stepSeconds: 60
        )) ?? []
    }

    func refreshPassPredictions() async {
        guard state.settings.notificationsEnabled, let propagator, let observer, let name = state.current?.name else {
            await notificationScheduler.cancelAll()
            return
        }
        try? await notificationScheduler.reschedule(
            satelliteName: name,
            propagator: propagator,
            observer: observer,
            thresholdDeg: state.settings.elevationThresholdDeg
        )
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case TLEFetchError.noMatches(let id):
            return "No satellite found matching \"\(id)\"."
        case TLEFetchError.ambiguousMatches(let id, let candidates):
            return "\"\(id)\" matches \(candidates.count) satellites: \(candidates.joined(separator: ", "))"
        case TLEFetchError.malformedResponse:
            return "Celestrak returned an unexpected response."
        case PropagationError.invalidTLE:
            return "That TLE could not be parsed."
        case PropagationError.propagationFailed:
            return "Could not compute a position for this satellite right now."
        default:
            return error.localizedDescription
        }
    }
}
