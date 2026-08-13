import CoreLocation
import Observation
import TLEWhereIsCore

@Observable
@MainActor
final class LocationManager: NSObject, CLLocationManagerDelegate {
    enum AuthorizationState {
        case notDetermined
        case denied
        case authorized
    }

    private let manager = CLLocationManager()
    var authorizationState: AuthorizationState
    var currentLocation: CLLocation?

    override init() {
        self.authorizationState = Self.map(manager.authorizationStatus)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Observer derived from the last known GPS fix, or nil if none yet.
    var observer: Observer? {
        guard let location = currentLocation else { return nil }
        return Observer(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitudeKm: max(location.altitude, 0) / 1000
        )
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationState = Self.map(status)
            if self.authorizationState == .authorized {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.currentLocation = location }
    }

    private static func map(_ status: CLAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: return .authorized
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }
}
