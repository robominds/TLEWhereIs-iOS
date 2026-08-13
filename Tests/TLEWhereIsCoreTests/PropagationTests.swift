import Foundation
import XCTest
@testable import TLEWhereIsCore

final class PropagationTests: XCTestCase {
    static let issRecord = TLERecord(
        name: "ISS (ZARYA)",
        noradID: 25544,
        line1: "1 25544U 98067A   26225.14877410  .00003778  00000+0  75606-4 0  9991",
        line2: "2 25544  51.6324  18.1827 0007533  41.6914 318.4648 15.49426097580580"
    )

    func testIssPositionIsPlausibleLEO() throws {
        let propagator = try Propagator(record: Self.issRecord)
        let position = try propagator.position()
        XCTAssertGreaterThan(position.altitudeKm, 300)
        XCTAssertLessThan(position.altitudeKm, 500)
        XCTAssertGreaterThan(position.speedKmS, 7.0)
        XCTAssertLessThan(position.speedKmS, 8.0)
        XCTAssertGreaterThanOrEqual(position.latitudeDeg, -90)
        XCTAssertLessThanOrEqual(position.latitudeDeg, 90)
        XCTAssertGreaterThanOrEqual(position.longitudeDeg, -180)
        XCTAssertLessThanOrEqual(position.longitudeDeg, 180)
    }

    /// An observer placed directly at the satellite's current sub-point
    /// (derived from the same propagation call, so this holds regardless of
    /// TLE staleness) should see it almost straight overhead.
    func testLookAngleIsNearOverheadWhenObserverIsAtSubsatellitePoint() throws {
        let propagator = try Propagator(record: Self.issRecord)
        let now = Date()
        let position = try propagator.position(at: now)
        let observer = Observer(latitude: position.latitudeDeg, longitude: position.longitudeDeg, altitudeKm: 0)
        let look = try propagator.lookAngle(from: observer, at: now)
        XCTAssertGreaterThan(look.elevationDeg, 80)
        XCTAssertGreaterThan(look.rangeKm, 0)
    }

    func testObserverOnOppositeSideOfEarthSeesItBelowTheHorizon() throws {
        let propagator = try Propagator(record: Self.issRecord)
        let now = Date()
        let position = try propagator.position(at: now)
        let antipodalObserver = Observer(
            latitude: -position.latitudeDeg,
            longitude: position.longitudeDeg + 180,
            altitudeKm: 0
        )
        let look = try propagator.lookAngle(from: antipodalObserver, at: now)
        XCTAssertLessThan(look.elevationDeg, 0)
    }

    func testInvalidTLEThrows() {
        let badRecord = TLERecord(name: "BAD", noradID: 1, line1: "not a tle", line2: "not a tle")
        XCTAssertThrowsError(try Propagator(record: badRecord))
    }
}
