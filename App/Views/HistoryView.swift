import SwiftUI
import TLEWhereIsCore

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List(model.state.history) { satellite in
                Button {
                    Task { await model.selectFromHistory(satellite) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(satellite.name).font(.headline)
                            Text("NORAD \(satellite.noradID) · last tracked \(satellite.lastTracked.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if satellite.noradID == model.state.currentNoradID {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if model.state.history.isEmpty {
                    ContentUnavailableView(
                        "No History Yet",
                        systemImage: "clock",
                        description: Text("Satellites you track will show up here.")
                    )
                }
            }
            .navigationTitle("History")
        }
    }
}

#Preview {
    HistoryView()
        .environment(AppModel())
}
