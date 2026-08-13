/// A geodetic observer location used for topocentric look-angle (azimuth /
/// elevation / range) computations.
public struct Observer: Codable, Sendable, Equatable {
    public var latitude: Double // degrees, +N
    public var longitude: Double // degrees, +E
    public var altitudeKm: Double // km above the geoid

    public init(latitude: Double, longitude: Double, altitudeKm: Double = 0) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeKm = altitudeKm
    }
}
