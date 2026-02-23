import Darwin
import Foundation

actor UsageFetcher {

    enum FetchError: LocalizedError {
        case claudeNotFound
        case ptyFailed(String)
        case timeout
        case outputEmpty

        var errorDescription: String? {
            switch self {
            case .claudeNotFound:    return "claude binary not found on PATH"
            case .ptyFailed(let m): return "PTY error: \(m)"
            case .timeout:           return "Timed out waiting for /usage output"
            case .outputEmpty:       return "claude produced no output"
            }
        }
    }

    private static func findClaude() -> String? {
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/bin/claude",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["claude"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return path
        }
        return nil
    }

    func fetch() async throws -> String {
        guard let claude = Self.findClaude() else {
            throw FetchError.claudeNotFound
        }

        var primaryFD: Int32 = -1
        var secondaryFD: Int32 = -1
        var win = winsize(ws_row: 50, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&primaryFD, &secondaryFD, nil, nil, &win) == 0 else {
            throw FetchError.ptyFailed("openpty failed: \(String(cString: strerror(errno)))")
        }
        _ = fcntl(primaryFD, F_SETFL, O_NONBLOCK)

        let secondaryHandle = FileHandle(fileDescriptor: secondaryFD, closeOnDealloc: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["-u", "CLAUDECODE", claude, "--allowed-tools", ""]
        process.standardInput  = secondaryHandle
        process.standardOutput = secondaryHandle
        process.standardError  = secondaryHandle

        let probeDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeUsage/probe")
        try? FileManager.default.createDirectory(at: probeDir, withIntermediateDirectories: true)
        process.currentDirectoryURL = probeDir

        var env = ProcessInfo.processInfo.environment
        env["CLAUDECODE"] = nil
        env["TERM"] = "xterm-256color"
        env["LANG"] = "en_US.UTF-8"
        for key in env.keys where key.hasPrefix("ANTHROPIC_") { env[key] = nil }
        process.environment = env

        try process.run()
        defer {
            try? secondaryHandle.close()
            close(primaryFD)
            if process.isRunning { process.terminate() }
        }

        try await Task.sleep(nanoseconds: 2_000_000_000)
        _ = drainFD(primaryFD)

        write(primaryFD, "/usage\r", 7)

        let stopStrings = [
            "current week (all models)",
            "current week (opus)",
            "current week (sonnet)",
            "current session",
            "failed to load usage data",
        ]

        var buffer = Data()
        let deadline = Date().addingTimeInterval(20)
        var lastEnterSent = Date()
        var found = false

        while Date() < deadline {
            let chunk = drainFD(primaryFD)
            if !chunk.isEmpty {
                buffer.append(chunk)
                if let text = String(data: buffer, encoding: .utf8) {
                    let lower = text.lowercased()
                    if stopStrings.contains(where: { lower.contains($0) }) {
                        found = true
                        try await Task.sleep(nanoseconds: 500_000_000)
                        buffer.append(drainFD(primaryFD))
                        break
                    }
                }
            }
            if Date().timeIntervalSince(lastEnterSent) >= 0.8 {
                write(primaryFD, "\r", 1)
                lastEnterSent = Date()
            }
            try await Task.sleep(nanoseconds: 60_000_000)
        }

        guard found else { throw FetchError.timeout }
        guard !buffer.isEmpty else { throw FetchError.outputEmpty }
        return String(data: buffer, encoding: .utf8) ?? ""
    }

    private func drainFD(_ fd: Int32) -> Data {
        var result = Data()
        var buf = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = read(fd, &buf, buf.count)
            guard n > 0 else { break }
            result.append(contentsOf: buf.prefix(n))
        }
        return result
    }
}
