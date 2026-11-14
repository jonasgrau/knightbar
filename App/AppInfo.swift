import Foundation

enum AppInfo {
    /// The app's visible name. It is defined in `Config/App.xcconfig`.
    static let displayName: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? ProcessInfo.processInfo.processName

    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    static let userAgent = "\(displayName)/\(version ?? "0")"

    /// Shared by both online providers. Keep the stored key for existing preferences.
    static let moveNotificationsKey = "lichessNotifyOnMove"
}
