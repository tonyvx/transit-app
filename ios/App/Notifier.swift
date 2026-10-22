import Foundation
import UserNotifications

/// Local notifications only. Nothing is sent to a server, so reminders fire on schedule rather than from live conditions.
enum Notifier {
    /// Shows banners while the app is open, and records taps.
    final class Delegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }
    }

    static let delegate = Delegate()

    static func install() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    /// Asks the first time it is needed. Returns whether notifications are allowed.
    static func authorize() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default: return false
        }
    }

    static func leaveReminderId(_ itineraryKey: String) -> String { "leave.\(itineraryKey)" }
    static func commuteReminderId(_ tripId: UUID, weekday: Int) -> String { "commute.\(tripId.uuidString).\(weekday)" }

    /// One-off reminder before the rider needs to set off. Returns false when the time has already passed.
    @discardableResult
    static func scheduleLeaveReminder(key: String, leaveBy: Date, minutesBefore: Int, destination: String) async -> Bool {
        let fire = leaveBy.addingTimeInterval(-Double(minutesBefore) * 60)
        guard fire > Date().addingTimeInterval(5), await authorize() else { return false }
        let content = UNMutableNotificationContent()
        content.title = minutesBefore == 0 ? "Time to leave" : "Leave in \(minutesBefore) min"
        content.body = "To reach \(destination) as planned, set off at \(leaveBy.formatted(date: .omitted, time: .shortened)). Open the app to check live times."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
        let req = UNNotificationRequest(identifier: leaveReminderId(key), content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        do { try await UNUserNotificationCenter.current().add(req); return true } catch { return false }
    }

    static func cancelLeaveReminder(key: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [leaveReminderId(key)])
    }

    static func hasLeaveReminder(key: String) async -> Bool {
        await UNUserNotificationCenter.current().pendingNotificationRequests().contains { $0.identifier == leaveReminderId(key) }
    }

    /// Repeating Monday to Friday reminder for a saved trip.
    static func scheduleCommuteReminder(_ trip: SavedTrip) async -> Bool {
        guard let minutes = trip.reminderMinutes, await authorize() else { return false }
        cancelCommuteReminder(trip)
        for weekday in 2...6 {
            let content = UNMutableNotificationContent()
            content.title = "Check your trip to \(trip.toName)"
            content.body = "Open Boston Transit for live departures and delays."
            content.sound = .default
            var comps = DateComponents()
            comps.weekday = weekday
            comps.hour = minutes / 60
            comps.minute = minutes % 60
            let req = UNNotificationRequest(identifier: commuteReminderId(trip.id, weekday: weekday), content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))
            try? await UNUserNotificationCenter.current().add(req)
        }
        return true
    }

    static func cancelCommuteReminder(_ trip: SavedTrip) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: (2...6).map { commuteReminderId(trip.id, weekday: $0) })
    }
}
