import Foundation

public struct Settings: Codable, Sendable, Equatable {
    public enum LocationMode: String, Codable, Sendable {
        case gps
        case manual
    }

    public var elevationThresholdDeg: Double
    public var locationMode: LocationMode
    public var manualObserver: Observer?
    public var notificationsEnabled: Bool

    public init(
        elevationThresholdDeg: Double = 10,
        locationMode: LocationMode = .gps,
        manualObserver: Observer? = nil,
        notificationsEnabled: Bool = false
    ) {
        self.elevationThresholdDeg = elevationThresholdDeg
        self.locationMode = locationMode
        self.manualObserver = manualObserver
        self.notificationsEnabled = notificationsEnabled
    }
}

public struct TrackedSatellite: Codable, Sendable, Equatable, Identifiable {
    public var id: Int { noradID }
    public var name: String
    public var noradID: Int
    public var lastTracked: Date
    public var cachedTLE: TLERecord?

    public init(name: String, noradID: Int, lastTracked: Date = Date(), cachedTLE: TLERecord? = nil) {
        self.name = name
        self.noradID = noradID
        self.lastTracked = lastTracked
        self.cachedTLE = cachedTLE
    }
}

public struct AppState: Codable, Sendable, Equatable {
    /// Most-recently-tracked first.
    public var history: [TrackedSatellite]
    public var currentNoradID: Int?
    public var settings: Settings

    public init(history: [TrackedSatellite] = [], currentNoradID: Int? = nil, settings: Settings = Settings()) {
        self.history = history
        self.currentNoradID = currentNoradID
        self.settings = settings
    }

    public var current: TrackedSatellite? {
        guard let id = currentNoradID else { return nil }
        return history.first { $0.noradID == id }
    }
}

/// JSON-file-backed persistence for tracked-satellite history, the currently
/// tracked satellite, per-satellite TLE cache, and settings. Plain
/// `Codable` + a file rather than SwiftData/UserDefaults: the data model is
/// small and simple, but per-satellite TLE cache entries can grow past what
/// `UserDefaults` is meant for.
public final class Store: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "TLEWhereIsCore.Store")

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("state.json")
    }

    public convenience init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TLEWhereIs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(directory: dir)
    }

    public func load() -> AppState {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return AppState() }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return (try? decoder.decode(AppState.self, from: data)) ?? AppState()
        }
    }

    public func save(_ state: AppState) throws {
        try queue.sync {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: .atomic)
        }
    }

    /// Marks `record` as the currently tracked satellite: moves it to the
    /// front of history (inserting it if new) with a refreshed TLE cache
    /// entry and timestamp.
    @discardableResult
    public func trackSatellite(_ record: TLERecord) throws -> AppState {
        var state = load()
        state.history.removeAll { $0.noradID == record.noradID }
        state.history.insert(
            TrackedSatellite(name: record.name, noradID: record.noradID, lastTracked: Date(), cachedTLE: record),
            at: 0
        )
        state.currentNoradID = record.noradID
        try save(state)
        return state
    }

    @discardableResult
    public func updateSettings(_ transform: (inout Settings) -> Void) throws -> AppState {
        var state = load()
        transform(&state.settings)
        try save(state)
        return state
    }
}
