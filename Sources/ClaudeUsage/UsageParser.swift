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

    // Extract reset time description, e.g. "resets in 2h 15m"
    static func parseResetTime(_ text: String) -> String? {
        let pattern = "resets? in ([\\w ]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespaces)
    }

    static func parse(_ rawText: String) -> UsageSnapshot {
        let clean = stripANSI(rawText)
        let lines = clean.components(separatedBy: .newlines)

        var fiveHourAll: Double? = nil
        var fiveHourOpus: Double? = nil
        var weeklyAll: Double? = nil
        var weeklyOpus: Double? = nil
        var fiveHourResetsAt: String? = nil
        var weeklyResetsAt: String? = nil

        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()

            let isFiveHour = lower.contains("5h") || lower.contains("5-hour")
                          || lower.contains("current session") || lower.contains("session")
            let isWeekly = lower.contains("week")
            let isOpus = lower.contains("opus")

            if isFiveHour && !isWeekly {
                if isOpus {
                    if fiveHourOpus == nil { fiveHourOpus = parsePercent(line) }
                } else {
                    if fiveHourAll == nil {
                        fiveHourAll = parsePercent(line)
                        for j in (i+1)..<min(i+5, lines.count) {
                            if let t = parseResetTime(lines[j]) {
                                fiveHourResetsAt = t; break
                            }
                        }
                    }
                }
            } else if isWeekly {
                if isOpus {
                    if weeklyOpus == nil { weeklyOpus = parsePercent(line) }
                } else {
                    if weeklyAll == nil {
                        weeklyAll = parsePercent(line)
                        for j in (i+1)..<min(i+5, lines.count) {
                            if let t = parseResetTime(lines[j]) {
                                weeklyResetsAt = t; break
                            }
                        }
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
