import Foundation

public enum TLEFetchError: Error, Equatable {
    case noMatches(identifier: String)
    case ambiguousMatches(identifier: String, candidates: [String])
    case malformedResponse
}

public enum TLEFetcher {
    /// Builds the Celestrak GP query URL. Numeric identifiers are treated as a
    /// NORAD catalog number (CATNR, always a single unambiguous match);
    /// anything else is a name search (NAME, a substring match that can
    /// return several satellites).
    public static func celestrakURL(for identifier: String) -> URL {
        var components = URLComponents(string: "https://celestrak.org/NORAD/elements/gp.php")!
        let isNumeric = !identifier.isEmpty && identifier.allSatisfy(\.isNumber)
        components.queryItems = [
            URLQueryItem(name: isNumeric ? "CATNR" : "NAME", value: identifier),
            URLQueryItem(name: "FORMAT", value: "TLE"),
        ]
        return components.url!
    }

    /// Parses Celestrak's TLE-format text response into (name, line1, line2)
    /// triplets. `name` is nil when a data-line pair appears without a
    /// preceding name line.
    static func parseTriplets(_ raw: String) -> [(name: String?, line1: String, line2: String)] {
        let lines = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var results: [(name: String?, line1: String, line2: String)] = []
        for i in 0..<lines.count {
            guard i + 1 < lines.count else { continue }
            guard lines[i].hasPrefix("1 "), lines[i + 1].hasPrefix("2 ") else { continue }
            let precedingIsData = i > 0 && (lines[i - 1].hasPrefix("1 ") || lines[i - 1].hasPrefix("2 "))
            let name = (i > 0 && !precedingIsData) ? lines[i - 1] : nil
            results.append((name: name, line1: lines[i], line2: lines[i + 1]))
        }
        return results
    }

    /// Resolves `identifier` against a raw Celestrak response, matching the
    /// CLI's disambiguation rule: an exact (case-insensitive) name match wins
    /// outright; otherwise a single match is accepted, but multiple
    /// non-exact matches (e.g. "ISS" substring-matching several catalog
    /// entries) are rejected rather than silently picking the first one.
    static func resolve(identifier: String, from raw: String) throws -> TLERecord {
        let triplets = parseTriplets(raw)
        guard !triplets.isEmpty else { throw TLEFetchError.noMatches(identifier: identifier) }

        let normalizedID = identifier.trimmingCharacters(in: .whitespaces).lowercased()
        if let exact = triplets.first(where: {
            ($0.name ?? "").trimmingCharacters(in: .whitespaces).lowercased() == normalizedID
        }) {
            return try makeRecord(name: exact.name ?? identifier, line1: exact.line1, line2: exact.line2)
        }
        if triplets.count == 1 {
            let only = triplets[0]
            return try makeRecord(name: only.name ?? identifier, line1: only.line1, line2: only.line2)
        }
        throw TLEFetchError.ambiguousMatches(
            identifier: identifier,
            candidates: triplets.map { $0.name ?? identifier }
        )
    }

    private static func makeRecord(name: String, line1: String, line2: String) throws -> TLERecord {
        guard line1.count >= 7,
              let noradID = Int(line1.dropFirst(2).prefix(5).trimmingCharacters(in: .whitespaces))
        else {
            throw TLEFetchError.malformedResponse
        }
        return TLERecord(name: name, noradID: noradID, line1: line1, line2: line2)
    }

    /// Fetches and resolves the TLE for `identifier` from Celestrak.
    public static func fetch(identifier: String, session: URLSession = .shared) async throws -> TLERecord {
        let raw = try await fetchRaw(identifier: identifier, session: session)
        return try resolve(identifier: identifier, from: raw)
    }

    /// Fetches every satellite matching `identifier` from Celestrak without
    /// resolving ambiguity, for presenting as a picker in a search UI
    /// (unlike `fetch`, which is the single-result, disambiguation-required
    /// entry point used by the CLI-style "track this satellite" flow).
    public static func fetchCandidates(identifier: String, session: URLSession = .shared) async throws -> [TLERecord] {
        let raw = try await fetchRaw(identifier: identifier, session: session)
        let triplets = parseTriplets(raw)
        guard !triplets.isEmpty else { throw TLEFetchError.noMatches(identifier: identifier) }
        return try triplets.map { try makeRecord(name: $0.name ?? identifier, line1: $0.line1, line2: $0.line2) }
    }

    // Some CDNs/WAFs in front of public-data APIs treat iOS's default
    // CFNetwork User-Agent as bot/scraper traffic and return an empty (but
    // 200 OK) body, while a browser UA passes through untouched -- observed
    // on-device where Safari succeeded against the same URL but URLSession
    // with no custom header came back with zero parseable TLE lines.
    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private static func fetchRaw(identifier: String, session: URLSession) async throws -> String {
        // TLEs go stale in days and Celestrak's NAME search result depends on
        // the exact query string, so a cached response -- especially a bad
        // or empty one from a transient failure -- must never be replayed.
        var request = URLRequest(url: celestrakURL(for: identifier))
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        guard let raw = String(data: data, encoding: .utf8) else {
            throw TLEFetchError.malformedResponse
        }
        return raw
    }
}
