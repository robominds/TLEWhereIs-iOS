import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            TrackingView()
                .tabItem { Label("Tracking", systemImage: "location.north.line.fill") }
            SatelliteMapView()
                .tabItem { Label("Map", systemImage: "map") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
