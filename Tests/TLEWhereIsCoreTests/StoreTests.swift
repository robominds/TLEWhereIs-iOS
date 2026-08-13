import Foundation
import XCTest
@testable import TLEWhereIsCore

final class StoreTests: XCTestCase {
    private func makeTempStore() -> Store {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return Store(directory: dir)
    }

    func testLoadReturnsEmptyStateWhenNoFileExists() {
        let state = makeTempStore().load()
        XCTAssertTrue(state.history.isEmpty)
        XCTAssertNil(state.currentNoradID)
    }

    func testTrackSatelliteInsertsAtFrontAndSetsCurrent() throws {
        let store = makeTempStore()
        let record = TLERecord(name: "OTTER PUP 2", noradID: 64537, line1: "1", line2: "2")
        let state = try store.trackSatellite(record)
        XCTAssertEqual(state.currentNoradID, 64537)
        XCTAssertEqual(state.history.first?.noradID, 64537)
        XCTAssertEqual(state.current?.name, "OTTER PUP 2")
    }

    func testTrackingExistingSatelliteMovesItToFrontWithoutDuplicating() throws {
        let store = makeTempStore()
        let first = TLERecord(name: "A", noradID: 1, line1: "1", line2: "2")
        let second = TLERecord(name: "B", noradID: 2, line1: "1", line2: "2")
        _ = try store.trackSatellite(first)
        _ = try store.trackSatellite(second)
        let state = try store.trackSatellite(first)
        XCTAssertEqual(state.history.count, 2)
        XCTAssertEqual(state.history.first?.noradID, 1)
        XCTAssertEqual(state.currentNoradID, 1)
    }

    func testStateRoundTripsThroughDisk() throws {
        let store = makeTempStore()
        let record = TLERecord(name: "OTTER PUP 2", noradID: 64537, line1: "1", line2: "2")
        _ = try store.trackSatellite(record)
        let reloaded = store.load()
        XCTAssertEqual(reloaded.currentNoradID, 64537)
        XCTAssertEqual(reloaded.history.first?.cachedTLE?.name, "OTTER PUP 2")
    }

    func testUpdateSettingsPersists() throws {
        let store = makeTempStore()
        let state = try store.updateSettings { $0.elevationThresholdDeg = 25 }
        XCTAssertEqual(state.settings.elevationThresholdDeg, 25)
        XCTAssertEqual(store.load().settings.elevationThresholdDeg, 25)
    }
}
