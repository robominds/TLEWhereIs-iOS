import SwiftUI
import TLEWhereIsCore

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [TLERecord] = []
    @State private var isSearching = false
    @State private var searchErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let searchErrorMessage {
                    Text(searchErrorMessage).foregroundStyle(.secondary)
                }
                ForEach(results, id: \.noradID) { record in
                    Button {
                        Task { await model.track(identifier: String(record.noradID)) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.name).font(.headline)
                            Text("NORAD \(record.noradID)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Satellite name or NORAD ID")
            .onSubmit(of: .search, runSearch)
            .overlay {
                if isSearching { ProgressView() }
            }
        }
    }

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searchErrorMessage = nil
        isSearching = true
        Task {
            defer { isSearching = false }
            do {
                results = try await TLEFetcher.fetchCandidates(identifier: trimmed)
            } catch {
                results = []
                searchErrorMessage = Self.describe(error, query: trimmed)
            }
        }
    }

    private static func describe(_ error: Error, query: String) -> String {
        switch error {
        case TLEFetchError.noMatches:
            return "No satellite found matching \"\(query)\"."
        case TLEFetchError.malformedResponse:
            return "Celestrak returned an unexpected response. Try again in a moment."
        case let urlError as URLError:
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "No internet connection."
            case .timedOut:
                return "Search timed out — check your connection and try again."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Could not reach Celestrak. Check your connection and try again."
            default:
                return "Search failed: \(urlError.localizedDescription)"
            }
        default:
            return "Search failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    SearchView()
        .environment(AppModel())
}
