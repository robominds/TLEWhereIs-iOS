import Foundation
import SatelliteKit

public struct SatellitePosition: Sendable, Equatable {
    public let latitudeDeg: Double
    public let longitudeDeg: Double
    public let altitudeKm: Double
    public let speedKmS: Double
}

public struct LookAngle: Sendable, Equatable {
    public let azimuthDeg: Double
    public let elevationDeg: Double
    public let rangeKm: Double
}

public enum PropagationError: Error {
    case invalidTLE
    case propagationFailed
}

/// Wraps a SatelliteKit `Satellite` (SGP4/SDP4 propagator) built from a
/// resolved TLE, exposing the geodetic position and observer-relative look
/// angle needed by the app.
public struct Propagator {
    private let satellite: Satellite

    public init(record: TLERecord) throws {
        // SatelliteKit's Elements parser indexes into fixed TLE columns and
        // traps (uncatchable) rather than throwing if a line is shorter than
        // the standard 69-character format, so length is validated here
        // first rather than trusting `try` to catch a malformed line.
        guard record.line1.count >= 69, record.line2.count >= 69,
              record.line1.hasPrefix("1 "), record.line2.hasPrefix("2 ")
        else {
            throw PropagationError.invalidTLE
        }
        do {
            let elements = try Elements(record.name, record.line1, record.line2)
            self.satellite = Satellite(elements: elements)
        } catch {
            throw PropagationError.invalidTLE
        }
    }

    public func position(at date: Date = Date()) throws -> SatellitePosition {
        let jd = date.julianDate
        do {
            let lla = try satellite.geoPosition(julianDays: jd)
            let vel = try satellite.velocity(julianDays: jd)
            return SatellitePosition(
                latitudeDeg: lla.lat,
                longitudeDeg: Self.normalizeLongitude(lla.lon),
                altitudeKm: lla.alt,
                speedKmS: vel.magnitude()
            )
        } catch {
            throw PropagationError.propagationFailed
        }
    }

    /// SatelliteKit's `eci2geo` returns longitude in [0, 360); normalize to
    /// the conventional [-180, 180] used everywhere else in this app.
    private static func normalizeLongitude(_ deg: Double) -> Double {
        let wrapped = deg.truncatingRemainder(dividingBy: 360)
        let positive = wrapped < 0 ? wrapped + 360 : wrapped
        return positive > 180 ? positive - 360 : positive
    }

    public func lookAngle(from observer: Observer, at date: Date = Date()) throws -> LookAngle {
        let jd = date.julianDate
        let observerLLA = LatLonAlt(observer.latitude, observer.longitude, observer.altitudeKm)
        do {
            let aed = try satellite.topPosition(julianDays: jd, observer: observerLLA)
            return LookAngle(azimuthDeg: aed.azim, elevationDeg: aed.elev, rangeKm: aed.dist)
        } catch {
            throw PropagationError.propagationFailed
        }
    }
}
