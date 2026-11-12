import ServiceManagement

/// The system's registration of an app as a login item. `SMAppService` provides it; tests use a stand-in.
public protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

public enum LaunchAtLoginState: Hashable, Sendable {
    case on
    case off
    /// Registered, but the user still has to allow it under System Settings → General → Login Items.
    case needsApproval
}

/// Whether the app opens by itself when the user logs in.
///
/// The system keeps this setting, and the user can change it in System Settings at any time,
/// so it is read from there every time instead of being stored by the app.
public struct LaunchAtLogin {
    private let service: any LoginItemService

    public init(service: any LoginItemService = SMAppService.mainApp) {
        self.service = service
    }

    public var state: LaunchAtLoginState {
        switch service.status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
        // macOS also reports an app that was never registered as not found, even in /Applications.
        case .notRegistered, .notFound: .off
        @unknown default: .off
        }
    }

    /// Registers or unregisters the app and returns the resulting state.
    /// Throws the system's error if that fails; the state is then unchanged.
    @discardableResult
    public func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginState {
        let isRegistered = state == .on || state == .needsApproval
        if enabled, !isRegistered {
            try service.register()
        } else if !enabled, isRegistered {
            try service.unregister()
        }
        return state
    }
}
