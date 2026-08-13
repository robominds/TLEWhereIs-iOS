import Foundation
import XCTest
@testable import TLEWhereIsCore

final class PassPredictorTests: XCTestCase {
    func testDetectsNoPassesWhenAlwaysBelowThreshold() {
        let start = Date(timeIntervalSince1970: 0)
        let passes = PassPredictor.findPasses(
            from: start, duration: 3600, stepSeconds: 60, thresholdDeg: 10
        ) { _ in -5 }
        XCTAssertTrue(passes.isEmpty)
    }

    func testDetectsSinglePassRiseAndSet() {
        let start = Date(timeIntervalSince1970: 0)
        let elevations: [Double] = [-5, -2, 2, 8, 15, 30, 45, 50, 45, 30, 15, 8, 2, -2, -5]
        let passes = PassPredictor.findPasses(
            from: start, duration: TimeInterval(elevations.count * 60), stepSeconds: 60, thresholdDeg: 10
        ) { date in
            elevations[Int(date.timeIntervalSince(start) / 60)]
        }
        XCTAssertEqual(passes.count, 1)
        XCTAssertEqual(passes[0].maxElevationDeg, 50)
        XCTAssertLessThan(passes[0].riseTime, passes[0].setTime)
    }

    func testDetectsMultiplePasses() {
        let start = Date(timeIntervalSince1970: 0)
        let elevations: [Double] = [-5, 20, -5, 30, -5]
        let passes = PassPredictor.findPasses(
            from: start, duration: TimeInterval(elevations.count * 60), stepSeconds: 60, thresholdDeg: 10
        ) { date in
            elevations[Int(date.timeIntervalSince(start) / 60)]
        }
        XCTAssertEqual(passes.count, 2)
    }

    func testRespectsMaxPassesCap() {
        let start = Date(timeIntervalSince1970: 0)
        let passes = PassPredictor.findPasses(
            from: start, duration: 3600, stepSeconds: 60, thresholdDeg: 10, maxPasses: 3
        ) { date in
            Int(date.timeIntervalSince(start) / 60) % 2 == 0 ? 20.0 : -20.0
        }
        XCTAssertEqual(passes.count, 3)
    }

    func testInProgressPassAtWindowEndIsClosedAtEndTime() {
        let start = Date(timeIntervalSince1970: 0)
        let elevations: [Double] = [-5, 20, 30, 40]
        let duration = TimeInterval(elevations.count * 60)
        let passes = PassPredictor.findPasses(
            from: start, duration: duration, stepSeconds: 60, thresholdDeg: 10
        ) { date in
            elevations[Int(date.timeIntervalSince(start) / 60)]
        }
        XCTAssertEqual(passes.count, 1)
        XCTAssertEqual(passes[0].setTime, start.addingTimeInterval(duration))
    }

    private func lookAngle(elevation: Double, range: Double) -> LookAngle {
        LookAngle(azimuthDeg: 180, elevationDeg: elevation, rangeKm: range)
    }

    func testFindsNextClosestApproachAtRangeMinimum() {
        let start = Date(timeIntervalSince1970: 0)
        // Range descends to a minimum at minute 5, then rises again.
        let ranges: [Double] = [900, 700, 500, 350, 250, 200, 250, 350, 500, 700, 900]
        let result = PassPredictor.findNextClosestApproach(
            from: start, duration: TimeInterval(ranges.count * 60),
            coarseStepSeconds: 60, refinedStepSeconds: 60
        ) { date in
            self.lookAngle(elevation: 10, range: ranges[Int(date.timeIntervalSince(start) / 60)])
        }
        let approach = try! XCTUnwrap(result)
        XCTAssertEqual(approach.lookAngle.rangeKm, 200)
        XCTAssertEqual(approach.time, start.addingTimeInterval(5 * 60))
    }

    func testClosestApproachIsNotGatedOnElevation() {
        // Never rises above the horizon, but still has a well-defined
        // minimum range -- closest approach isn't the same thing as a pass.
        let start = Date(timeIntervalSince1970: 0)
        let ranges: [Double] = [2000, 1500, 1200, 1500, 2000]
        let result = PassPredictor.findNextClosestApproach(
            from: start, duration: TimeInterval(ranges.count * 60),
            coarseStepSeconds: 60, refinedStepSeconds: 60
        ) { date in
            self.lookAngle(elevation: -10, range: ranges[Int(date.timeIntervalSince(start) / 60)])
        }
        let approach = try! XCTUnwrap(result)
        XCTAssertEqual(approach.lookAngle.rangeKm, 1200)
        XCTAssertLessThan(approach.lookAngle.elevationDeg, 0)
    }

    func testReturnsNilWhenRangeNeverTurnsAroundWithinWindow() {
        let start = Date(timeIntervalSince1970: 0)
        // Monotonically decreasing for the whole window -- no local minimum yet.
        let ranges: [Double] = [900, 800, 700, 600, 500]
        let result = PassPredictor.findNextClosestApproach(
            from: start, duration: TimeInterval(ranges.count * 60),
            coarseStepSeconds: 60, refinedStepSeconds: 60
        ) { date in
            self.lookAngle(elevation: 5, range: ranges[Int(date.timeIntervalSince(start) / 60)])
        }
        XCTAssertNil(result)
    }

    func testRefinementFindsAMinimumBetweenCoarseSamples() {
        let start = Date(timeIntervalSince1970: 0)
        // Coarse samples every 60s; true minimum sits at t=90s (150 km),
        // invisible at 60s resolution alone (100 -> 100 looks flat).
        func trueRange(secondsFromStart: Double) -> Double {
            abs(secondsFromStart - 90) * 2 + 150
        }
        let result = PassPredictor.findNextClosestApproach(
            from: start, duration: 240,
            coarseStepSeconds: 60, refinedStepSeconds: 5
        ) { date in
            self.lookAngle(elevation: 10, range: trueRange(secondsFromStart: date.timeIntervalSince(start)))
        }
        let approach = try! XCTUnwrap(result)
        XCTAssertEqual(approach.lookAngle.rangeKm, 150, accuracy: 1.0)
        XCTAssertEqual(approach.time.timeIntervalSince(start), 90, accuracy: 5)
    }

    /// End-to-end sanity check against a real propagator: the found time
    /// should be a genuine local minimum of range, not just some sample.
    func testNextClosestApproachFindsARealMinimumForISS() throws {
        let record = TLERecord(
            name: "ISS (ZARYA)",
            noradID: 25544,
            line1: "1 25544U 98067A   26225.14877410  .00003778  00000+0  75606-4 0  9991",
            line2: "2 25544  51.6324  18.1827 0007533  41.6914 318.4648 15.49426097580580"
        )
        let propagator = try Propagator(record: record)
        let observer = Observer(latitude: 37.7749, longitude: -122.4194, altitudeKm: 0)
        let start = Date()

        let result = try PassPredictor.nextClosestApproach(propagator: propagator, observer: observer, from: start)
        let approach = try XCTUnwrap(result)

        XCTAssertGreaterThan(approach.time, start)
        XCTAssertLessThan(approach.time.timeIntervalSince(start), 24 * 3600)
        XCTAssertGreaterThan(approach.lookAngle.rangeKm, 0)

        let before = try propagator.lookAngle(from: observer, at: approach.time.addingTimeInterval(-120))
        let after = try propagator.lookAngle(from: observer, at: approach.time.addingTimeInterval(120))
        XCTAssertLessThanOrEqual(approach.lookAngle.rangeKm, before.rangeKm)
        XCTAssertLessThanOrEqual(approach.lookAngle.rangeKm, after.rangeKm)
    }
}
