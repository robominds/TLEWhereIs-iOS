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
        let (data, _) = try await session.data(from: celestrakURL(for: identifier))
        guard let raw = String(data: data, encoding: .utf8) else {
            throw TLEFetchError.malformedResponse
        }
        return try resolve(identifier: identifier, from: raw)
    }
}
