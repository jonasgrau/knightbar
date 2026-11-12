import Foundation

enum AppInfo {
    /// The app's visible name. It is defined in `Config/App.xcconfig`.
    static let displayName: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? ProcessInfo.processInfo.processName
}
