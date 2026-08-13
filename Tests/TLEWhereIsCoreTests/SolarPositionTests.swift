import Foundation
import XCTest
@testable import TLEWhereIsCore

final class SolarPositionTests: XCTestCase {
    private func angularDistanceDeg(latA: Double, lonA: Double, latB: Double, lonB: Double) -> Double {
        let lat1 = latA * .pi / 180
        let lat2 = latB * .pi / 180
        let deltaLon = (lonB - lonA) * .pi / 180
        let cosC = sin(lat1) * sin(lat2) + cos(lat1) * cos(lat2) * cos(deltaLon)
        return acos(min(1, max(-1, cosC))) * 180 / .pi
    }

    func testSubsolarPointStaysWithinValidRanges() {
        for offset in stride(from: 0.0, to: 20_000_000_000, by: 1_000_000_000) {
            let point = SolarPosition.subsolarPoint(at: Date(timeIntervalSince1970: offset))
            XCTAssertGreaterThanOrEqual(point.latitudeDeg, -23.45)
            XCTAssertLessThanOrEqual(point.latitudeDeg, 23.45)
            XCTAssertGreaterThanOrEqual(point.longitudeDeg, -180)
            XCTAssertLessThanOrEqual(point.longitudeDeg, 180)
        }
    }

    func testSubsolarDeclinationNearZeroAtMarchEquinox() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-20T12:00:00Z"))
        let point = SolarPosition.subsolarPoint(at: date)
        XCTAssertEqual(point.latitudeDeg, 0, accuracy: 1.5)
    }

    func testSubsolarDeclinationNearMaximumAtJuneSolstice() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-21T12:00:00Z"))
        let point = SolarPosition.subsolarPoint(at: date)
        XCTAssertEqual(point.latitudeDeg, 23.44, accuracy: 1.0)
    }

    func testSubsolarDeclinationNearMinimumAtDecemberSolstice() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-12-21T12:00:00Z"))
        let point = SolarPosition.subsolarPoint(at: date)
        XCTAssertEqual(point.latitudeDeg, -23.44, accuracy: 1.0)
    }

    func testSubsolarLongitudeNearZeroAtUTCNoon() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-20T12:00:00Z"))
        let point = SolarPosition.subsolarPoint(at: date)
        XCTAssertEqual(point.longitudeDeg, 0, accuracy: 5)
    }

    /// The terminator is defined as the set of points exactly 90° of
    /// great-circle angular distance from the subsolar point -- a property
    /// that holds regardless of date, so this doesn't need a hardcoded
    /// reference value.
    func testTerminatorPointsAreNinetyDegreesFromSubsolarPoint() {
        let subsolar = SubsolarPoint(latitudeDeg: 15, longitudeDeg: -40)
        for longitude in stride(from: -180.0, through: 180.0, by: 15.0) {
            let terminatorLat = SolarPosition.terminatorLatitudeDeg(atLongitudeDeg: longitude, subsolar: subsolar)
            let distance = angularDistanceDeg(
                latA: terminatorLat, lonA: longitude,
                latB: subsolar.latitudeDeg, lonB: subsolar.longitudeDeg
            )
            XCTAssertEqual(distance, 90, accuracy: 0.5)
        }
    }

    func testTerminatorHandlesNearZeroDeclinationWithoutCrashing() {
        let subsolar = SubsolarPoint(latitudeDeg: 0, longitudeDeg: 10)
        for longitude in stride(from: -180.0, through: 180.0, by: 30.0) {
            let lat = SolarPosition.terminatorLatitudeDeg(atLongitudeDeg: longitude, subsolar: subsolar)
            XCTAssertFalse(lat.isNaN)
            XCTAssertFalse(lat.isInfinite)
        }
    }
}
