import Foundation

/// A version number such as 0.2.0. Missing parts count as zero; a leading "v" (as in tags) is ignored.
public struct AppVersion: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ text: String) {
        var text = Substring(text)
        if text.first == "v" { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber), let number = Int(part) else {
                return nil
            }
            numbers.append(number)
        }
        while numbers.count < 3 { numbers.append(0) }
        (major, minor, patch) = (numbers[0], numbers[1], numbers[2])
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

/// A newer release than the one running.
public struct AvailableUpdate: Hashable, Sendable {
    public let version: AppVersion
    /// The release page, where the downloads are.
    public let url: URL

    public init(version: AppVersion, url: URL) {
        self.version = version
        self.url = url
    }
}

public enum UpdateCheckError: Error, Equatable, Sendable {
    /// GitHub allows 60 requests per hour without login.
    case rateLimited
    case http(Int)
    case offline
    case invalidResponse
}

/// Asks GitHub for the latest release of the app. Drafts and pre-releases are never "latest".
public struct UpdateChecker: Sendable {
    private let transport: any HTTPTransport
    private let repository: String
    private let userAgent: String

    /// `repository` is "owner/name" on GitHub.
    public init(transport: any HTTPTransport = URLSessionTransport(), repository: String, userAgent: String) {
        self.transport = transport
        self.repository = repository
        self.userAgent = userAgent
    }

    /// The latest release if it is newer than `current`, otherwise `nil`.
    public func availableUpdate(current: AppVersion) async throws(UpdateCheckError) -> AvailableUpdate? {
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        let response: HTTPResponse
        do {
            response = try await transport.send(HTTPRequest(
                url: url, headers: ["Accept": "application/vnd.github+json", "User-Agent": userAgent]))
        } catch {
            throw .offline
        }

        switch response.status {
        case 200:
            break
        case 404:
            return nil          // no release published yet
        case 403, 429:
            throw .rateLimited
        default:
            throw .http(response.status)
        }

        struct Release: Decodable {
            let tag_name: String
            let html_url: URL
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: response.body),
              let version = AppVersion(release.tag_name)
        else { throw .invalidResponse }
        return version > current ? AvailableUpdate(version: version, url: release.html_url) : nil
    }
}

public enum UpdateSchedule {
    /// Automatic checks run at most once a day.
    public static let interval: TimeInterval = 24 * 60 * 60

    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck, lastCheck <= now else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }
}

/// How the app got onto this Mac, which decides how it gets updated.
public enum InstallSource: Hashable, Sendable {
    /// Installed with `brew install --cask`; Homebrew should do the update too.
    case homebrew
    /// Downloaded from the release page.
    case download

    /// Recognises a Homebrew install by the cask's folder in the Caskroom
    /// (/opt/homebrew on Apple Silicon, /usr/local on Intel).
    public static func detect(cask: String, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> InstallSource {
        let folders = ["/opt/homebrew/Caskroom/\(cask)", "/usr/local/Caskroom/\(cask)"]
        return folders.contains(where: fileExists) ? .homebrew : .download
    }

    /// The command that updates a Homebrew install, `nil` for a download.
    public func upgradeCommand(cask: String) -> String? {
        self == .homebrew ? "brew upgrade --cask \(cask)" : nil
    }
}
