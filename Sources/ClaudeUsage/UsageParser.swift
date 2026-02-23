import Foundation

enum UsageParser {

    // Strip ANSI escape codes (colors, cursor movement, etc.)
    static func stripANSI(_ text: String) -> String {
        let pattern = "\u{1B}(?:[@-Z\\\\-_]|\\[[0-?]*[ -/]*[@-~])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    // Extract first percentage from a string, returns 0.0–1.0
    static func parsePercent(_ text: String) -> Double? {
        let pattern = "(\\d+(?:\\.\\d+)?)%"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let value = Double(text[range]) else { return nil }
        return value / 100.0
    }

    // Extract reset time description.
    // Handles both "Resets in 1m" (relative) and "Resets Mar 1 at 10am (America/...)" (absolute).
    static func parseResetTime(_ text: String) -> String? {
        let lower = text.lowercased()
        // Relative: "resets? in <time>"
        let relPattern = "resets? in ([\\w ]+)"
        if let regex = try? NSRegularExpression(pattern: relPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            return String(text[range]).trimmingCharacters(in: .whitespaces)
        }
        // Absolute: "Resets <Month> <day> at <time>"
        let absPattern = "resets ([a-z]+ \\d+ at [^(]+)"
        if let regex = try? NSRegularExpression(pattern: absPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            return String(text[range]).trimmingCharacters(in: .whitespaces)
        }
        // If the line contains "resets" at all, return trimmed line minus leading/trailing noise
        if lower.contains("resets") || lower.contains("reses") {
            // strip timezone suffix in parens and return core
            let stripped = text.replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
            return stripped.trimmingCharacters(in: .whitespaces).isEmpty ? nil : stripped.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    static func parse(_ rawText: String) -> UsageSnapshot {
        let clean = stripANSI(rawText)
        // Normalize line endings: \r\n and \r become \n
        let normalized = clean.replacingOccurrences(of: "\r\n", with: "\n")
                               .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var fiveHourAll: Double? = nil
        var fiveHourOpus: Double? = nil
        var weeklyAll: Double? = nil
        var weeklyOpus: Double? = nil
        var fiveHourResetsAt: String? = nil
        var weeklyResetsAt: String? = nil

        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()

            // Detect section headers (the actual claude /usage output uses these)
            // "Current session" → 5-hour session limit
            let isFiveHour = lower.contains("current session") || lower.contains("session")
                          || lower.contains("5h") || lower.contains("5-hour")

            // "Current week" sections
            let isWeekly = lower.contains("week")

            // Opus / Sonnet distinctions within weekly
            // Actual output has "Sonnet only" and "all models" sections (no Opus standalone on Max plan)
            let isOpus   = lower.contains("opus")
            let isSonnet = lower.contains("sonnet")
            let isAll    = lower.contains("all model")

            // Percentage may be on the same line or on the very next non-empty line
            func percentForSection(startLine: Int) -> Double? {
                // Check same line first
                if let p = parsePercent(lines[startLine]) { return p }
                // Check next few lines for a percentage
                for j in (startLine + 1)..<min(startLine + 4, lines.count) {
                    let next = lines[j].trimmingCharacters(in: .whitespaces)
                    if next.isEmpty { continue }
                    if let p = parsePercent(next) { return p }
                    // Stop if we hit another section header
                    if next.lowercased().contains("current") { break }
                }
                return nil
            }

            func resetForSection(startLine: Int) -> String? {
                for j in (startLine + 1)..<min(startLine + 5, lines.count) {
                    let next = lines[j].trimmingCharacters(in: .whitespaces)
                    if next.isEmpty { continue }
                    let nl = next.lowercased()
                    if nl.contains("resets") || nl.contains("reses") || nl.contains("reset") {
                        return parseResetTime(next) ?? next
                    }
                    // Stop at next section header
                    if nl.contains("current") { break }
                }
                return nil
            }

            if isFiveHour && !isWeekly {
                if isOpus {
                    if fiveHourOpus == nil { fiveHourOpus = percentForSection(startLine: i) }
                } else {
                    if fiveHourAll == nil {
                        fiveHourAll = percentForSection(startLine: i)
                        if fiveHourResetsAt == nil { fiveHourResetsAt = resetForSection(startLine: i) }
                    }
                }
            } else if isWeekly {
                if isOpus {
                    // Opus-only weekly section
                    if weeklyOpus == nil { weeklyOpus = percentForSection(startLine: i) }
                    if weeklyResetsAt == nil { weeklyResetsAt = resetForSection(startLine: i) }
                } else if isSonnet && !isAll {
                    // "Current week (Sonnet only)" — treat as weeklyOpus slot for per-model data
                    if weeklyOpus == nil { weeklyOpus = percentForSection(startLine: i) }
                    if weeklyResetsAt == nil { weeklyResetsAt = resetForSection(startLine: i) }
                } else {
                    // "Current week (all models)"
                    if weeklyAll == nil {
                        weeklyAll = percentForSection(startLine: i)
                        if weeklyResetsAt == nil { weeklyResetsAt = resetForSection(startLine: i) }
                    }
                }
            }
        }

        return UsageSnapshot(
            fiveHourAll: fiveHourAll,
            fiveHourOpus: fiveHourOpus,
            weeklyAll: weeklyAll,
            weeklyOpus: weeklyOpus,
            fiveHourResetsAt: fiveHourResetsAt,
            weeklyResetsAt: weeklyResetsAt,
            fetchedAt: Date(),
            rawText: clean
        )
    }
}
