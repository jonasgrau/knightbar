import ChessCore
import Foundation
import Testing

@Suite struct AppVersionTests {
    @Test(arguments: [
        ("0.2.0", [0, 2, 0]),
        ("v1.10.3", [1, 10, 3]),
        ("2.1", [2, 1, 0]),
        ("3", [3, 0, 0]),
    ])
    func versionIsReadFromTagsAndVersionStrings(text: String, parts: [Int]) throws {
        let version = try #require(AppVersion(text))
        #expect([version.major, version.minor, version.patch] == parts)
    }

    @Test(arguments: ["", "v", "abc", "1.2.3.4", "1.x.0", "-1.0.0", "1..2"])
    func invalidVersionIsRejected(text: String) {
        #expect(AppVersion(text) == nil)
    }

    @Test func versionsCompareNumberByNumber() {
        #expect(AppVersion("0.10.0")! > AppVersion("0.9.9")!)
        #expect(AppVersion("1.0.0")! > AppVersion("0.99.99")!)
        #expect(AppVersion("0.2.1")! > AppVersion("0.2.0")!)
        #expect(AppVersion("v0.2.0")! == AppVersion("0.2")!)
    }

    @Test func versionIsWrittenWithThreeNumbers() {
        #expect(AppVersion("v2.1")!.description == "2.1.0")
    }
}

@Suite struct UpdateCheckerTests {
    static let latest = #"{"tag_name":"v0.3.0","name":"Knightbar 0.3.0","html_url":"https://github.com/jonasgrau/knightbar/releases/tag/v0.3.0","draft":false,"prerelease":false}"#

    private func checker(_ transport: FakeHTTPTransport) -> UpdateChecker {
        UpdateChecker(transport: transport, repository: "jonasgrau/knightbar", userAgent: "Knightbar/0.2.0")
    }

    @Test func newerReleaseIsReported() async throws {
        let transport = FakeHTTPTransport([ok(Self.latest)])
        let update = try await checker(transport).availableUpdate(current: AppVersion("0.2.0")!)
        #expect(update == AvailableUpdate(
            version: AppVersion("0.3.0")!,
            url: URL(string: "https://github.com/jonasgrau/knightbar/releases/tag/v0.3.0")!))
        #expect(transport.requests == [HTTPRequest(
            url: URL(string: "https://api.github.com/repos/jonasgrau/knightbar/releases/latest")!,
            headers: ["Accept": "application/vnd.github+json", "User-Agent": "Knightbar/0.2.0"])])
    }

    @Test func sameOrOlderReleaseMeansUpToDate() async throws {
        let same = try await checker(FakeHTTPTransport([ok(Self.latest)])).availableUpdate(current: AppVersion("0.3.0")!)
        #expect(same == nil)
        let older = try await checker(FakeHTTPTransport([ok(Self.latest)])).availableUpdate(current: AppVersion("1.0.0")!)
        #expect(older == nil)
    }

    @Test func repositoryWithoutReleasesMeansUpToDate() async throws {
        let update = try await checker(FakeHTTPTransport([status(404, #"{"message":"Not Found"}"#)]))
            .availableUpdate(current: AppVersion("0.2.0")!)
        #expect(update == nil)
    }

    @Test func rateLimitIsReported() async {
        for code in [403, 429] {
            let checker = checker(FakeHTTPTransport([status(code)]))
            await #expect(throws: UpdateCheckError.rateLimited) {
                try await checker.availableUpdate(current: AppVersion("0.2.0")!)
            }
        }
    }

    @Test func otherFailuresAreReported() async {
        let offline = checker(FakeHTTPTransport([.failure(URLError(.notConnectedToInternet))]))
        await #expect(throws: UpdateCheckError.offline) { try await offline.availableUpdate(current: AppVersion("0.2.0")!) }
        let broken = checker(FakeHTTPTransport([ok(#"{"tag_name":"latest"}"#)]))
        await #expect(throws: UpdateCheckError.invalidResponse) { try await broken.availableUpdate(current: AppVersion("0.2.0")!) }
        let server = checker(FakeHTTPTransport([status(502)]))
        await #expect(throws: UpdateCheckError.http(502)) { try await server.availableUpdate(current: AppVersion("0.2.0")!) }
    }
}

@Suite struct UpdateScheduleTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func firstCheckIsDueRightAway() {
        #expect(UpdateSchedule.isDue(lastCheck: nil, now: now))
    }

    @Test func checkIsDueOncePerDay() {
        #expect(!UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(-23 * 3_600), now: now))
        #expect(UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(-24 * 3_600), now: now))
    }

    @Test func lastCheckInTheFutureCountsAsDue() {
        // The clock was set back; do not wait for days.
        #expect(UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(3 * 86_400), now: now))
    }
}

@Suite struct InstallSourceTests {
    @Test func homebrewInstallIsRecognisedByItsCaskroomFolder() {
        let appleSilicon = InstallSource.detect(cask: "knightbar") { $0 == "/opt/homebrew/Caskroom/knightbar" }
        let intel = InstallSource.detect(cask: "knightbar") { $0 == "/usr/local/Caskroom/knightbar" }
        #expect(appleSilicon == .homebrew)
        #expect(intel == .homebrew)
    }

    @Test func everythingElseCountsAsDirectDownload() {
        #expect(InstallSource.detect(cask: "knightbar") { _ in false } == .download)
    }

    @Test func homebrewHintNamesTheUpgradeCommand() {
        #expect(InstallSource.homebrew.upgradeCommand(cask: "knightbar") == "brew upgrade --cask knightbar")
        #expect(InstallSource.download.upgradeCommand(cask: "knightbar") == nil)
    }
}
