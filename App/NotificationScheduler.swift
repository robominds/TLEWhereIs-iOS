import Foundation
import UserNotifications
import TLEWhereIsCore

@MainActor
final class NotificationScheduler {
    private static let identifierPrefix = "TLEWhereIs.pass."
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Cancels previously scheduled pass notifications and schedules new ones
    /// for the given satellite, one per predicted pass that crosses
    /// `thresholdDeg`, firing at the moment each pass rises above it.
    func reschedule(
        satelliteName: String,
        propagator: Propagator,
        observer: Observer,
        thresholdDeg: Double,
        lookaheadDays: Double = 5,
        maxPasses: Int = 20
    ) async throws {
        await cancelAll()

        let passes = try PassPredictor.predictPasses(
            propagator: propagator,
            observer: observer,
            thresholdDeg: thresholdDeg,
            from: Date(),
            duration: lookaheadDays * 86400,
            maxPasses: maxPasses
        )

        for pass in passes {
            let interval = pass.riseTime.timeIntervalSinceNow
            guard interval > 1 else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(satelliteName) is overhead"
            content.body = String(
                format: "Rising above %.0f°, peaking at %.0f° elevation.",
                thresholdDeg, pass.maxElevationDeg
            )
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.identifierPrefix + String(Int(pass.riseTime.timeIntervalSince1970)),
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }
}
