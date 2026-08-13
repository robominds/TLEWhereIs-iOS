import Foundation
import XCTest
@testable import TLEWhereIsCore

final class TLEFetcherTests: XCTestCase {
    func testCelestrakURLUsesCatnrForNumericIdentifier() {
        let url = TLEFetcher.celestrakURL(for: "25544")
        let query = url.query ?? ""
        XCTAssertTrue(query.contains("CATNR=25544"))
        XCTAssertFalse(query.contains("NAME="))
    }

    func testCelestrakURLUsesNameForNonNumericIdentifier() {
        let url = TLEFetcher.celestrakURL(for: "ISS (ZARYA)")
        let query = url.query ?? ""
        XCTAssertTrue(query.contains("NAME="))
        XCTAssertFalse(query.contains("CATNR="))
    }

    func testParseTripletsExtractsNameAndLines() {
        let raw = """
        OTTER PUP 2
        1 64537U 25151A   26224.50000000  .00001234  00000-0  12345-4 0  9991
        2 64537  97.5000 123.4567 0001234  90.0000 270.0000 15.20000000 12345
        """
        let triplets = TLEFetcher.parseTriplets(raw)
        XCTAssertEqual(triplets.count, 1)
        XCTAssertEqual(triplets[0].name, "OTTER PUP 2")
        XCTAssertTrue(triplets[0].line1.hasPrefix("1 64537"))
        XCTAssertTrue(triplets[0].line2.hasPrefix("2 64537"))
    }

    func testParseTripletsSurvivesCRLFAndInterspersedBlankLines() {
        // Reproduces a real device response: CRLF line endings, and a blank
        // line inserted after every real line (observed with a carrier's
        // transparent compression proxy re-encoding the gzip response).
        let raw = "OTTER PUP 2             \r\n\r\n"
            + "1 64537U 25151A   26224.50000000  .00001234  00000-0  12345-4 0  9991\r\n\r\n"
            + "2 64537  97.5000 123.4567 0001234  90.0000 270.0000 15.20000000 12345\r\n\r\n"
        let triplets = TLEFetcher.parseTriplets(raw)
        XCTAssertEqual(triplets.count, 1)
        XCTAssertEqual(triplets[0].name, "OTTER PUP 2")
        XCTAssertTrue(triplets[0].line1.hasPrefix("1 64537"))
        XCTAssertTrue(triplets[0].line2.hasPrefix("2 64537"))
    }

    func testParseTripletsHandlesMultipleSatellites() {
        let raw = """
        UME (ISS)
        1 08709U 76019A   26224.62323090 -.00000051  00000+0  12495-5 0  9990
        2 08709  69.6749  18.5368 0012623 233.7595 210.0410 13.71750134524838
        ISS (ZARYA)
        1 25544U 98067A   26225.14877410  .00003778  00000+0  75606-4 0  9991
        2 25544  51.6324  18.1827 0007533  41.6914 318.4648 15.49426097580580
        """
        let triplets = TLEFetcher.parseTriplets(raw)
        XCTAssertEqual(triplets.count, 2)
        XCTAssertEqual(triplets.map(\.name), ["UME (ISS)", "ISS (ZARYA)"])
    }

    func testResolveExactNameMatchWinsOverSubstringMatches() throws {
        let raw = """
        UME (ISS)
        1 08709U 76019A   26224.62323090 -.00000051  00000+0  12495-5 0  9990
        2 08709  69.6749  18.5368 0012623 233.7595 210.0410 13.71750134524838
        ISS (ZARYA)
        1 25544U 98067A   26225.14877410  .00003778  00000+0  75606-4 0  9991
        2 25544  51.6324  18.1827 0007533  41.6914 318.4648 15.49426097580580
        """
        let record = try TLEFetcher.resolve(identifier: "ISS (ZARYA)", from: raw)
        XCTAssertEqual(record.noradID, 25544)
        XCTAssertEqual(record.name, "ISS (ZARYA)")
    }

    func testResolveSingleMatchSucceedsEvenWithoutExactName() throws {
        let raw = """
        OTTER PUP 2
        1 64537U 25151A   26224.50000000  .00001234  00000-0  12345-4 0  9991
        2 64537  97.5000 123.4567 0001234  90.0000 270.0000 15.20000000 12345
        """
        let record = try TLEFetcher.resolve(identifier: "64537", from: raw)
        XCTAssertEqual(record.noradID, 64537)
    }

    func testResolveAmbiguousNonExactMatchesThrowsWithCandidates() {
        let raw = """
        UME (ISS)
        1 08709U 76019A   26224.62323090 -.00000051  00000+0  12495-5 0  9990
        2 08709  69.6749  18.5368 0012623 233.7595 210.0410 13.71750134524838
        ISS (ZARYA)
        1 25544U 98067A   26225.14877410  .00003778  00000+0  75606-4 0  9991
        2 25544  51.6324  18.1827 0007533  41.6914 318.4648 15.49426097580580
        """
        XCTAssertThrowsError(try TLEFetcher.resolve(identifier: "ISS", from: raw)) { error in
            guard case .ambiguousMatches(let identifier, let candidates) = error as? TLEFetchError else {
                return XCTFail("expected .ambiguousMatches, got \(error)")
            }
            XCTAssertEqual(identifier, "ISS")
            XCTAssertEqual(candidates.count, 2)
        }
    }

    func testResolveNoMatchesThrows() {
        XCTAssertThrowsError(try TLEFetcher.resolve(identifier: "NOTHING", from: ""))
    }
}
