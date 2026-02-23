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
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
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

    func fetch() async throws -> FetchResult {
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

        // Use /tmp so claude doesn't walk up the directory tree looking for .claude projects,
        // which would trigger macOS TCC permission dialogs for Desktop/network volumes.
        let probeDir = URL(fileURLWithPath: "/tmp/claudeusage-probe")
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

        // Wait for the CLI welcome screen to finish rendering.
        // Capture welcome text — it contains plan/model info (e.g. "Opus 4.6 · Claude Max").
        var welcomeData = Data()
        let readyDeadline = Date().addingTimeInterval(10)
        var lastActivity = Date()
        while Date() < readyDeadline {
            let chunk = drainFD(primaryFD)
            if !chunk.isEmpty {
                welcomeData.append(chunk)
                lastActivity = Date()
            } else if Date().timeIntervalSince(lastActivity) >= 0.6 {
                break  // CLI quiet for 600ms → ready
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        welcomeData.append(drainFD(primaryFD))  // final drain

        write(primaryFD, "/usage\r", 7)

        let stopStrings = [
            // These appear at end of the cost section — preferred stop points
            "last 30 days",
            "last month",
            // Fallback: weekly/session section headers (no cost in output)
            "current week (all models)",
            "current week (opus)",
            "current week (sonnet)",
            "current session",
            "failed to load usage data",
        ]

        var buffer = Data()
        let deadline = Date().addingTimeInterval(30)
        var lastEnterSent = Date()
        var lastNewDataAt = Date()
        var found = false

        while Date() < deadline {
            let chunk = drainFD(primaryFD)
            if !chunk.isEmpty {
                buffer.append(chunk)
                lastNewDataAt = Date()
                // Use lossy UTF-8 so invalid bytes never cause nil
                let text = String(decoding: buffer, as: UTF8.self)
                let lower = text.lowercased()
                if stopStrings.contains(where: { lower.contains($0) }) {
                    found = true
                    try await Task.sleep(nanoseconds: 500_000_000)
                    buffer.append(drainFD(primaryFD))
                    break
                }
            }

            // Fallback: % data present and CLI quiet for 2s (handles unknown output formats)
            if buffer.count > 100,
               Date().timeIntervalSince(lastNewDataAt) >= 2.0 {
                let text = String(decoding: buffer, as: UTF8.self)
                if text.contains("%") {
                    found = true
                    break
                }
            }

            if Date().timeIntervalSince(lastEnterSent) >= 0.8 {
                write(primaryFD, "\r", 1)
                lastEnterSent = Date()
            }
            try await Task.sleep(nanoseconds: 60_000_000)
        }

        // Always save raw buffer for debugging
        try? buffer.write(to: URL(fileURLWithPath: "/tmp/claude_usage_debug.txt"))

        guard found else { throw FetchError.timeout }
        guard !buffer.isEmpty else { throw FetchError.outputEmpty }
        let welcome = String(decoding: welcomeData, as: UTF8.self)
        let usage = String(data: buffer, encoding: .utf8) ?? ""
        return FetchResult(welcomeText: welcome, usageText: usage)
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
