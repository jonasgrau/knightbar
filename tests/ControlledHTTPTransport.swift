import ChessCore
import Foundation

/// Delays replies until the test releases them, even if the caller has cancelled.
actor ControlledHTTPTransport: HTTPTransport {
    private var pending: [String: [CheckedContinuation<HTTPResponse, any Error>]] = [:]
    private var counts: [String: Int] = [:]

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        counts[request.url.path, default: 0] += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[request.url.path, default: []].append(continuation)
        }
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPStream {
        throw URLError(.unsupportedURL)
    }

    func count(_ path: String) -> Int { counts[path, default: 0] }

    func reply(_ path: String, body: String) {
        pending[path]!.removeFirst().resume(returning: HTTPResponse(status: 200, body: Data(body.utf8)))
    }

    func fail(_ path: String) {
        pending[path]!.removeFirst().resume(throwing: URLError(.notConnectedToInternet))
    }

    func finish() {
        for continuations in pending.values {
            for continuation in continuations { continuation.resume(throwing: CancellationError()) }
        }
        pending = [:]
    }
}

struct RegressionFailure: Error, CustomStringConvertible { let description: String }

@MainActor
func requireRegression(_ condition: Bool, _ description: String) throws {
    guard condition else { throw RegressionFailure(description: description) }
}

@MainActor
func waitForRegression(_ description: String, until condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !(await condition()), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    try requireRegression(await condition(), "Timed out: \(description)")
}

/// Check for unwanted changes during a bounded period after releasing a late response.
@MainActor
func remainsTrue(_ description: String, _ condition: () -> Bool) async throws {
    for _ in 0..<10 {
        try await Task.sleep(for: .milliseconds(10))
        try requireRegression(condition(), description)
    }
}
