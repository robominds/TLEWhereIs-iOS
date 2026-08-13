import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TrackingView()
                .tabItem { Label("Tracking", systemImage: "location.north.line.fill") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
