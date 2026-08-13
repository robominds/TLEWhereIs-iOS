import Foundation

/// A resolved TLE (two-line element set) for one satellite, plus the catalog
/// name it was matched under and when it was fetched.
public struct TLERecord: Codable, Sendable, Equatable {
    public let name: String
    public let noradID: Int
    public let line1: String
    public let line2: String
    public let fetchedAt: Date

    public init(name: String, noradID: Int, line1: String, line2: String, fetchedAt: Date = Date()) {
        self.name = name
        self.noradID = noradID
        self.line1 = line1
        self.line2 = line2
        self.fetchedAt = fetchedAt
    }
}
