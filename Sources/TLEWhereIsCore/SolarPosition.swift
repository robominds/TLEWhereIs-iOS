import Foundation

/// The point on Earth's surface directly beneath the sun.
public struct SubsolarPoint: Sendable, Equatable {
    public let latitudeDeg: Double
    public let longitudeDeg: Double

    public init(latitudeDeg: Double, longitudeDeg: Double) {
        self.latitudeDeg = latitudeDeg
        self.longitudeDeg = longitudeDeg
    }
}

/// Low-precision solar position, good to a fraction of a degree — plenty for
/// drawing a day/night terminator on a map, not an ephemeris-grade result.
/// Standard formulas (e.g. Meeus, "Astronomical Algorithms", low-precision
/// sun position).
public enum SolarPosition {
    public static func subsolarPoint(at date: Date = Date()) -> SubsolarPoint {
        let n = date.timeIntervalSince(j2000) / 86400.0 // days since J2000.0 epoch

        let meanLongitude = normalizedDegrees(280.460 + 0.9856474 * n)
        let meanAnomaly = normalizedDegrees(357.528 + 0.9856003 * n)
        let g = meanAnomaly * .pi / 180

        let eclipticLongitude = meanLongitude + 1.915 * sin(g) + 0.020 * sin(2 * g)
        let obliquity = 23.439 - 0.0000004 * n

        let lambdaRad = eclipticLongitude * .pi / 180
        let epsilonRad = obliquity * .pi / 180

        let declinationRad = asin(sin(epsilonRad) * sin(lambdaRad))
        let rightAscensionRad = atan2(cos(epsilonRad) * sin(lambdaRad), cos(lambdaRad))

        // Greenwich Mean Sidereal Time, referenced to J2000, in degrees.
        let gmst = normalizedDegrees(280.46061837 + 360.98564736629 * n)

        let rightAscensionDeg = rightAscensionRad * 180 / .pi
        let declinationDeg = declinationRad * 180 / .pi
        let longitude = normalizedSignedDegrees(rightAscensionDeg - gmst)

        return SubsolarPoint(latitudeDeg: declinationDeg, longitudeDeg: longitude)
    }

    /// The latitude of the day/night terminator at a given longitude, for a
    /// sun at `subsolar`. The terminator is the great circle 90° from the
    /// subsolar point in every direction, so this is well-defined everywhere
    /// except when the subsolar declination is exactly 0 (equinox), where
    /// it degenerates to a pair of meridians -- guarded with a small epsilon
    /// rather than dividing by zero.
    public static func terminatorLatitudeDeg(atLongitudeDeg longitudeDeg: Double, subsolar: SubsolarPoint) -> Double {
        let declinationRad = subsolar.latitudeDeg * .pi / 180
        let guardedTanDeclination = tan(abs(declinationRad) < 1e-9 ? (declinationRad < 0 ? -1e-9 : 1e-9) : declinationRad)
        let deltaLonRad = (longitudeDeg - subsolar.longitudeDeg) * .pi / 180
        let latRad = atan(-cos(deltaLonRad) / guardedTanDeclination)
        return latRad * 180 / .pi
    }

    private static let j2000 = Date(timeIntervalSince1970: 946_727_935.816) // 2000-01-01T11:58:55.816Z (JD 2451545.0)

    private static func normalizedDegrees(_ deg: Double) -> Double {
        let wrapped = deg.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    private static func normalizedSignedDegrees(_ deg: Double) -> Double {
        let positive = normalizedDegrees(deg)
        return positive > 180 ? positive - 360 : positive
    }
}
