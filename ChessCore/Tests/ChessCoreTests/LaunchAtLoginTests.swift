import ChessCore
import ServiceManagement
import Testing

/// Stands in for the system's login item registration.
final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status
    /// The status the system reports after a successful `register()`.
    var statusAfterRegister: SMAppService.Status = .enabled
    var failure: (any Error)?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCalls += 1
        if let failure { throw failure }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCalls += 1
        if let failure { throw failure }
        status = .notRegistered
    }
}

struct SomeSystemError: Error {}

@Suite struct LaunchAtLoginTests {
    @Test(arguments: [
        (SMAppService.Status.enabled, LaunchAtLoginState.on),
        (.notRegistered, .off),
        (.requiresApproval, .needsApproval),
        // macOS reports an app that was never registered as not found, even in /Applications.
        (.notFound, .off),
    ])
    func stateFollowsTheSystemStatus(status: SMAppService.Status, state: LaunchAtLoginState) {
        #expect(LaunchAtLogin(service: FakeLoginItemService(status: status)).state == state)
    }

    @Test func enablingRegistersTheApp() throws {
        let service = FakeLoginItemService(status: .notRegistered)
        let state = try LaunchAtLogin(service: service).setEnabled(true)
        #expect(state == .on)
        #expect(service.registerCalls == 1)
    }

    @Test func enablingMayNeedApprovalInSystemSettings() throws {
        let service = FakeLoginItemService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        #expect(try LaunchAtLogin(service: service).setEnabled(true) == .needsApproval)
    }

    @Test func appNeverRegisteredBeforeCanBeEnabled() throws {
        let service = FakeLoginItemService(status: .notFound)
        #expect(try LaunchAtLogin(service: service).setEnabled(true) == .on)
        #expect(service.registerCalls == 1)
    }

    @Test func disablingUnregistersTheApp() throws {
        let service = FakeLoginItemService(status: .enabled)
        #expect(try LaunchAtLogin(service: service).setEnabled(false) == .off)
        #expect(service.unregisterCalls == 1)
    }

    @Test func disablingAWaitingApprovalWithdrawsIt() throws {
        let service = FakeLoginItemService(status: .requiresApproval)
        #expect(try LaunchAtLogin(service: service).setEnabled(false) == .off)
        #expect(service.unregisterCalls == 1)
    }

    @Test func nothingHappensWhenTheStateAlreadyMatches() throws {
        let on = FakeLoginItemService(status: .enabled)
        #expect(try LaunchAtLogin(service: on).setEnabled(true) == .on)
        let off = FakeLoginItemService(status: .notRegistered)
        #expect(try LaunchAtLogin(service: off).setEnabled(false) == .off)
        #expect(on.registerCalls + on.unregisterCalls + off.registerCalls + off.unregisterCalls == 0)
    }

    @Test func systemErrorIsPassedOnAndTheStateStays() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.failure = SomeSystemError()
        let launchAtLogin = LaunchAtLogin(service: service)
        #expect(throws: SomeSystemError.self) { try launchAtLogin.setEnabled(true) }
        #expect(launchAtLogin.state == .off)
    }
}
