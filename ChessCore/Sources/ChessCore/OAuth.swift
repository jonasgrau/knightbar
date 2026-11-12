import CryptoKit
import Foundation

public enum OAuthError: Error, Equatable, Sendable {
    /// The user or Lichess refused. Carries the description from the callback, if any.
    case denied(String?)
    /// The callback does not belong to this request.
    case stateMismatch
    case missingCode
}

/// One Lichess login attempt: OAuth 2 authorization code flow with PKCE.
///
/// Lichess needs no app registration. `clientID` is a free identifier of the app.
public struct OAuthRequest: Sendable {
    public let clientID: String
    public let redirectURI: String
    public let scopes: [String]
    /// The secret that proves, when fetching the token, that the login was started here.
    public let codeVerifier: String
    public let state: String

    public init(clientID: String, redirectURI: String, scopes: [String],
                randomBytes: (Int) -> [UInt8] = OAuthRequest.secureRandomBytes) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scopes = scopes
        codeVerifier = Self.base64URL(randomBytes(48))
        state = Self.base64URL(randomBytes(16))
    }

    public static func secureRandomBytes(_ count: Int) -> [UInt8] {
        var generator = SystemRandomNumberGenerator()
        return (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
    }

    private static func base64URL(_ bytes: some Sequence<UInt8>) -> String {
        Data(bytes).base64EncodedString()
            .replacing("+", with: "-").replacing("/", with: "_").replacing("=", with: "")
    }

    /// `BASE64URL(SHA256(verifier))`, as PKCE's S256 method defines it.
    public static func codeChallenge(for verifier: String) -> String {
        base64URL(SHA256.hash(data: Data(verifier.utf8)))
    }

    /// The Lichess page to send the user to.
    public var authorizationURL: URL {
        var components = URLComponents(string: "https://lichess.org/oauth")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: codeVerifier)),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// Extracts the authorization code from the URL Lichess redirected to.
    public func authorizationCode(fromCallback url: URL) throws(OAuthError) -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        guard value("state") == state else { throw .stateMismatch }
        if value("error") != nil { throw .denied(value("error_description")) }
        guard let code = value("code"), !code.isEmpty else { throw .missingCode }
        return code
    }
}
