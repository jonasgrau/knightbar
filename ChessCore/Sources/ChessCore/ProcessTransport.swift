import Foundation

/// Runs an engine executable as a child process and talks to it through pipes.
public final class ProcessTransport: EngineTransport, @unchecked Sendable {
    public let lines: AsyncStream<String>
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()

    /// Splits the engine's output into lines. Only touched from the pipe's read handler.
    private final class LineBuffer: @unchecked Sendable {
        var pending = Data()

        func append(_ chunk: Data) -> [String] {
            pending.append(chunk)
            var lines: [String] = []
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
                pending.removeSubrange(pending.startIndex...newline)
                lines.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return lines
        }
    }

    /// Launches the executable. Throws if it cannot be started.
    public init(executableURL: URL) throws {
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        lines = stream

        process.executableURL = executableURL
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        // Writing to an engine that has already exited must fail with an error, not kill the app.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        let buffer = LineBuffer()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                continuation.finish()
                return
            }
            for line in buffer.append(chunk) where !line.isEmpty {
                continuation.yield(line)
            }
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            continuation.finish()
            throw error
        }
    }

    public func send(_ line: String) throws {
        try input.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8))
    }

    public func terminate() {
        if process.isRunning { process.terminate() }
    }
}
