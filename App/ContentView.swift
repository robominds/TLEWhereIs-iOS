import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TrackingView()
                .tabItem { Label("Tracking", systemImage: "location.north.line.fill") }
                .tag(0)
            SatelliteMapView()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(1)
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(2)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
                .tag(3)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(4)
        }
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
