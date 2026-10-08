import Cocoa
import UserNotifications

enum NotificationPref: String, CaseIterable {
    case inputLost     = "notifyInputLost"
    case inputRestored = "notifyInputRestored"
    case lowBattery    = "notifyLowBattery"
    case fullCharge    = "notifyFullCharge"

    var isOn: Bool { UserDefaults.standard.bool(forKey: rawValue) }
}

/// Notifications of the same topic share an identifier, so a newer one replaces the
/// older banner in Notification Center instead of piling up.
enum NotificationTopic: String {
    case input, battery, connection, app
}

enum Notifier {
    private static var didSurfaceFailure = false
    private static let presenter = Presenter()
    private static let deniedMessage = "Notifications are disabled in System Settings → Notifications → EFStatus."

    static func configure() {
        UserDefaults.standard.register(defaults: Dictionary(
            uniqueKeysWithValues: NotificationPref.allCases.map { ($0.rawValue, true) }))
        UNUserNotificationCenter.current().delegate = presenter
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if (!granted || error != nil) && userWantsNotifications {
                surfaceFailureOnce(reason: error?.localizedDescription ?? deniedMessage)
            }
        }
    }

    static var userWantsNotifications: Bool { NotificationPref.allCases.contains { $0.isOn } }

    static func send(_ topic: NotificationTopic, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = "EFStatus"
        content.body  = body
        content.sound = .default
        content.threadIdentifier = "efstatus"
        let req = UNNotificationRequest(identifier: "efstatus.\(topic.rawValue)", content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .denied:
                if userWantsNotifications { surfaceFailureOnce(reason: deniedMessage) }
            default:
                center.add(req) { error in
                    if let error, userWantsNotifications { surfaceFailureOnce(reason: error.localizedDescription) }
                }
            }
        }
    }

    static func authorizationDeniedMessage(_ completion: @escaping (String?) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus == .denied && userWantsNotifications ? deniedMessage : nil)
            }
        }
    }

    static func requestAndExplain(_ completion: @escaping (String?) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            DispatchQueue.main.async {
                completion(granted ? nil : (error?.localizedDescription ?? deniedMessage))
            }
        }
    }

    private static func surfaceFailureOnce(reason: String) {
        DispatchQueue.main.async {
            guard !didSurfaceFailure else { return }
            didSurfaceFailure = true
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "EFStatus notifications"
            alert.informativeText = reason
            alert.alertStyle = .informational
            alert.runModal()
        }
    }

    // Without a delegate macOS silently drops banners while the app counts as active
    // (e.g. with the popup open).
    private final class Presenter: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .list, .sound])
        }
    }
}
