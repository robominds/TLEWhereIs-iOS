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
}
