import ChessCore
import Foundation

@main
struct ChessComModelRegression {
    static let oldPath = "/pub/player/old/games/to-move"
    static let newPath = "/pub/player/new/games/to-move"
    static let games = #"{"games":[{"url":"https://www.chess.com/game/daily/123"}]}"#

    @MainActor
    static func main() async throws {
        for oldFails in [false, true] { try await usernameSwitch(oldFails: oldFails) }
        try await usernameRoundTrip()
        print("ChessComModel request switching regressions passed.")
    }

    @MainActor
    static func usernameSwitch(oldFails: Bool) async throws {
        let suite = "Knightbar.ChessComRegression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("old", forKey: "chessComUsername")
        defaults.set(true, forKey: "lichessNotifyOnMove")
        let transport = ControlledHTTPTransport()
        var notifications: [String] = []
        let model = ChessComModel(client: ChessComClient(transport: transport, userAgent: "RegressionTest"),
                                  defaults: defaults, notify: { notifications.append($0) })
        try await waitForRegression("old username request") { await transport.count(oldPath) == 1 }
        model.username = "new"
        try await waitForRegression("new username request") { await transport.count(newPath) == 1 }
        model.refresh()
        if oldFails { await transport.fail(oldPath) }
        else { await transport.reply(oldPath, body: games) }
        try await remainsTrue("Old username response changed current state") {
            model.isLoading && model.games.isEmpty && model.message == nil
        }
        await transport.reply(newPath, body: games)
        try await waitForRegression("new username loaded") { !model.isLoading && model.games.count == 1 }
        try requireRegression(notifications.isEmpty, "Initial games for a new username notified")
        try requireRegression(await transport.count(newPath) == 1, "Duplicate username fetch")
        // A late failure must not overwrite an already successful replacement either.
        model.username = "old"
        try await waitForRegression("second old request") { await transport.count(oldPath) == 2 }
        model.username = "new"
        try await waitForRegression("second new request") { await transport.count(newPath) == 2 }
        await transport.reply(newPath, body: games)
        try await waitForRegression("replacement completed") { !model.isLoading && model.games.count == 1 }
        await transport.fail(oldPath)
        try await remainsTrue("Late failure overwrote a successful replacement") {
            !model.isLoading && model.games.count == 1 && model.message == nil
        }
        model.username = ""
        await transport.finish()
        print("PASS: username switch with old request \(oldFails ? "failing" : "succeeding")")
    }

    @MainActor
    static func usernameRoundTrip() async throws {
        let suite = "Knightbar.ChessComRoundTrip.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("old", forKey: "chessComUsername")
        let transport = ControlledHTTPTransport()
        let model = ChessComModel(client: ChessComClient(transport: transport, userAgent: "RegressionTest"),
                                  defaults: defaults, notify: { _ in })
        try await waitForRegression("initial username") { await transport.count(oldPath) == 1 }
        model.username = "new"
        try await waitForRegression("intermediate username") { await transport.count(newPath) == 1 }
        model.username = "old"
        try await waitForRegression("return to old username") { await transport.count(oldPath) == 2 }
        await transport.reply(oldPath, body: games)
        await transport.fail(newPath)
        try await remainsTrue("Cancelled same-username response was accepted") {
            model.isLoading && model.games.isEmpty && model.message == nil
        }
        // Clearing the username cancels the newest request without leaving a loading indicator.
        model.username = " "
        try requireRegression(!model.isLoading && !model.hasUsername, "Empty username remains loading")
        await transport.reply(oldPath, body: games)
        try await remainsTrue("Cleared username received stale data") {
            !model.isLoading && model.games.isEmpty && model.message == nil
        }
        await transport.finish()
        print("PASS: username round trip and clearing during a request")
    }
}
