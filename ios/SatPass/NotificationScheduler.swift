import Foundation
import UserNotifications

/// Local notifications: a 10-minute heads-up before AOS for every pass whose
/// max elevation meets Mike's 40° alert threshold. Purely local — no push
/// server, no background modes. Rescheduled on every pass refresh.
enum NotificationScheduler {
    private static let idPrefix = "satpass-pass-"

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// Clears all SatPass notifications and schedules fresh ones for prime
    /// passes. Call on the main actor after a pass refresh.
    static func refresh(passes: [SatPass], threshold: Double) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.filter { $0.identifier.hasPrefix(idPrefix) }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ours)

        let now = Date()
        for pass in passes where pass.maxEl >= threshold {
            let fireDate = pass.notifyDate
            guard fireDate > now else { continue }
            // Don't pile up alerts for passes more than 48h out.
            guard fireDate < now.addingTimeInterval(48 * 3600) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "🛰 \(pass.guide.shortName) pass in 10 minutes"
            content.body = "Max \(Int(pass.maxEl.rounded()))° at \(pass.tca.passTimeString). \(pass.guide.alertLine)"
            content.sound = .default

            var comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: fireDate)
            comps.second = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(idPrefix)\(pass.id)",
                content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    static func pendingCount() async -> Int {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return pending.filter { $0.identifier.hasPrefix(idPrefix) }.count
    }

    static func clearAll() {
        let center = UNUserNotificationCenter.current()
        Task {
            let pending = await center.pendingNotificationRequests()
            let ours = pending.filter { $0.identifier.hasPrefix(idPrefix) }.map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
    }
}
