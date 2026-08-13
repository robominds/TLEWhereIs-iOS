import BackgroundTasks
import SwiftUI

@main
struct TLEWhereIsApp: App {
    static let refreshTaskIdentifier = "com.robominds.tlewhereis.refresh"

    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                scheduleBackgroundRefresh()
            }
        }
        .backgroundTask(.appRefresh(Self.refreshTaskIdentifier)) {
            await model.refreshInBackground()
            await scheduleBackgroundRefresh()
        }
    }

    @MainActor
    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
