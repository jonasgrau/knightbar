import AppKit
import AuthenticationServices
import Security
import UserNotifications

/// Where the Lichess access token is kept.
protocol TokenStore: Sendable {
    func load() -> String?
    func save(_ token: String)
    func delete()
}

/// Keeps the token in the login keychain, never in a file or in the user defaults.
struct KeychainTokenStore: TokenStore {
    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "Knightbar",
            kSecAttrAccount as String: "lichess-access-token",
        ]
    }

    func load() -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String) {
        delete()
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

/// Shows the Lichess login page and returns the URL Lichess redirects to.
@MainActor
protocol WebAuthenticator {
    func authenticate(at url: URL, callbackScheme: String) async throws -> URL
}

/// Uses the system's web authentication session, which opens the page in the default browser
/// and catches the redirect to the app's own URL scheme.
@MainActor
final class SystemWebAuthenticator: NSObject, WebAuthenticator, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authenticate(at url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            // The system calls this handler on a background thread, so it must not be tied to the main actor.
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { @Sendable callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? CancellationError())
                }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                continuation.resume(throwing: CancellationError())
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow() }
    }
}

/// Posts "your move" notifications.
enum MoveNotifier {
    /// Asks for permission to show notifications. Returns whether it was granted.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func notifyYourMove(opponent: String, gameID: String) {
        let content = UNMutableNotificationContent()
        content.title = "Your move"
        content.body = "\(opponent) has moved in your Lichess game."
        content.sound = .default
        // One notification per game: a newer one replaces the older one.
        let request = UNNotificationRequest(identifier: "lichess-\(gameID)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

extension MoveNotifier {
    static func notifyChessComMove(gameID: String) {
        let content = UNMutableNotificationContent()
        content.title = "Your move"
        content.body = "It is your move in a Chess.com daily game."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "chesscom-\(gameID)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

enum MenuBarIcon {
    /// The menu bar image, with a dot at the top right when the user is to move somewhere.
    @MainActor
    static func image(showsDot: Bool) -> NSImage {
        let knight = NSImage(named: "MenuBarIcon") ?? NSImage()
        guard showsDot else { return knight }
        let size = NSSize(width: knight.size.width + 5, height: knight.size.height)
        // Drawn right away rather than in a drawing handler, which AppKit may call on any thread.
        let scale = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return knight }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        knight.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: size.width - 6.5, y: size.height - 6.5, width: 6, height: 6)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        image.isTemplate = true
        return image
    }
}
