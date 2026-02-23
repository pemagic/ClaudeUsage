import Foundation

enum UsageParser {

    // Strip ANSI escape codes; cursor-right sequences replaced with space to preserve word boundaries.
    static func stripANSI(_ text: String) -> String {
        // Step 1: replace ESC[NC (cursor right N) with a space, so words separated by cursor moves stay separated.
        var result = text
        if let rx = try? NSRegularExpression(pattern: "\u{1B}\\[\\d+C") {
            result = rx.stringByReplacingMatches(in: result,
                                                  range: NSRange(result.startIndex..., in: result),
                                                  withTemplate: " ")
        }
        // Step 2: strip all remaining escape sequences.
        let pattern = "\u{1B}(?:[@-Z\\\\-_]|\\[[0-?]*[ -/]*[@-~])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        return regex.stringByReplacingMatches(in: result,
                                               range: NSRange(result.startIndex..., in: result),
                                               withTemplate: "")
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
    static func parseResetTime(_ text: String) -> String? {
        let lower = text.lowercased()
        let relPattern = "resets? in ([\\w ]+)"
        if let regex = try? NSRegularExpression(pattern: relPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            return String(text[range]).trimmingCharacters(in: .whitespaces)
        }
        let absPattern = "resets ([a-z]+ \\d+ at [^(]+)"
        if let regex = try? NSRegularExpression(pattern: absPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            return String(text[range]).trimmingCharacters(in: .whitespaces)
        }
        if lower.contains("resets") || lower.contains("reses") || lower.contains("rese") {
            let stripped = text.replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
            return stripped.trimmingCharacters(in: .whitespaces).isEmpty ? nil : stripped.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Parse a reset time string into a Date (for pace calculations and countdown display).
    /// Handles relative ("6d 11h", "2h 42m") and absolute ("Mar 1 at 10am") formats.
    static func parseResetDate(from resetString: String) -> Date? {
        let s = resetString.lowercased()

        // Relative format: "6d 11h", "2h 42m", "1m", etc.
        var totalSeconds: TimeInterval = 0
        var matched = false
        let pairs: [(String, TimeInterval)] = [
            (#"(\d+)\s*d"#, 86400),
            (#"(\d+)\s*h"#, 3600),
            (#"(\d+)\s*m(?:in|s)?"#, 60),
        ]
        for (pattern, multiplier) in pairs {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               let r = Range(m.range(at: 1), in: s),
               let n = Double(s[r]) {
                totalSeconds += n * multiplier
                matched = true
            }
        }
        if matched && totalSeconds > 0 { return Date().addingTimeInterval(totalSeconds) }

        // Absolute format: "Mar 1 at 10am", "Feb 28 at 10:30am", etc.
        // Strip timezone suffix in parens, then try DateFormatter.
        let stripped = resetString
            .replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        let formats = ["MMM d 'at' h:mma", "MMM d 'at' ha", "MMM dd 'at' h:mma", "MMM dd 'at' ha"]
        let cal = Calendar.current
        let thisYear = cal.component(.year, from: Date())
        for fmt in formats {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = fmt
            df.defaultDate = cal.date(from: DateComponents(year: thisYear)) ?? Date()
            if var d = df.date(from: stripped) {
                // If parsed date is already in the past, bump to next year
                if d < Date() {
                    var c = cal.dateComponents([.month, .day, .hour, .minute], from: d)
                    c.year = thisYear + 1
                    d = cal.date(from: c) ?? d
                }
                return d
            }
        }

        // Time-only format: extract "12:59am" or "1pm" from strings like "Rese s 12:59am"
        let timePattern = #"(\d{1,2}(?::\d{2})?[ap]m)"#
        if let rx = try? NSRegularExpression(pattern: timePattern, options: .caseInsensitive),
           let m = rx.firstMatch(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)),
           let r = Range(m.range(at: 1), in: stripped) {
            let timeStr = String(stripped[r])
            let timeFormats = ["h:mma", "ha"]
            for fmt in timeFormats {
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.dateFormat = fmt
                if let parsed = df.date(from: timeStr) {
                    // Apply parsed hour/minute to today
                    let comps = cal.dateComponents([.hour, .minute], from: parsed)
                    var target = cal.dateComponents([.year, .month, .day], from: Date())
                    target.hour = comps.hour
                    target.minute = comps.minute
                    target.second = 0
                    if var d = cal.date(from: target) {
                        // If already past, it means tomorrow
                        if d < Date() { d = d.addingTimeInterval(86400) }
                        return d
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Cost parsing

    /// Extract dollar amount from a line, returns e.g. "30.87"
    private static func extractDollar(_ line: String) -> String? {
        let pattern = #"\$\s*([\d,]+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let r = Range(m.range(at: 1), in: line) else { return nil }
        return String(line[r]).replacingOccurrences(of: ",", with: "")
    }

    /// Extract token count from a line, e.g. "309M" or "1.2B"
    private static func extractTokens(_ line: String) -> String? {
        let pattern = #"([\d,.]+)\s*([kmgbKMGB])\s*tokens"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let numR = Range(m.range(at: 1), in: line),
              let unitR = Range(m.range(at: 2), in: line) else {
            // Fallback: plain number + tokens
            let p2 = #"([\d,.]+)\s*tokens"#
            if let rx = try? NSRegularExpression(pattern: p2, options: .caseInsensitive),
               let m2 = rx.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let r2 = Range(m2.range(at: 1), in: line) {
                return String(line[r2]).replacingOccurrences(of: ",", with: "")
            }
            return nil
        }
        let num = String(line[numR])
        let unit = String(line[unitR]).uppercased()
        return "\(num)\(unit)"
    }

    // MARK: - Plan info from welcome screen

    /// Parse "Opus 4.6 · Claude Max" from the welcome screen.
    static func parsePlanInfo(_ welcomeRaw: String) -> (model: String?, plan: String?) {
        let clean = stripANSI(welcomeRaw)
        // Pattern: "ModelName · PlanName" e.g. "Opus 4.6 · Claude Max"
        let pattern = #"((?:Opus|Sonnet|Haiku)\s+[\d.]+)\s*[·•]\s*(Claude\s+\w+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)) else {
            return (nil, nil)
        }
        let model = Range(match.range(at: 1), in: clean).map { String(clean[$0]).trimmingCharacters(in: .whitespaces) }
        let plan = Range(match.range(at: 2), in: clean).map { String(clean[$0]).trimmingCharacters(in: .whitespaces) }
        return (model, plan)
    }

    // MARK: - Main parse

    static func parse(_ result: FetchResult) -> UsageSnapshot {
        let clean = stripANSI(result.usageText)
        let normalized = clean.replacingOccurrences(of: "\r\n", with: "\n")
                               .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var fiveHourAll: Double? = nil
        var fiveHourOpus: Double? = nil
        var weeklyAll: Double? = nil
        var weeklyOpus: Double? = nil
        var fiveHourResetsAt: String? = nil
        var weeklyResetsAt: String? = nil
        var fiveHourResetsDate: Date? = nil
        var weeklyResetsDate: Date? = nil

        var todayCost: String? = nil
        var todayTokens: String? = nil
        var monthlyCost: String? = nil
        var monthlyTokens: String? = nil

        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()

            // Detect section headers
            let isFiveHour = lower.contains("current session") || lower.contains("session")
                          || lower.contains("5h") || lower.contains("5-hour")
            let isWeekly = lower.contains("week")
            let isOpus   = lower.contains("opus")
            let isSonnet = lower.contains("sonnet")
            let isAll    = lower.contains("all model")

            func percentForSection(startLine: Int) -> Double? {
                if let p = parsePercent(lines[startLine]) { return p }
                for j in (startLine + 1)..<min(startLine + 4, lines.count) {
                    let next = lines[j].trimmingCharacters(in: .whitespaces)
                    if next.isEmpty { continue }
                    if let p = parsePercent(next) { return p }
                    if next.lowercased().contains("current") { break }
                }
                return nil
            }

            func resetForSection(startLine: Int) -> String? {
                for j in (startLine + 1)..<min(startLine + 5, lines.count) {
                    let next = lines[j].trimmingCharacters(in: .whitespaces)
                    if next.isEmpty { continue }
                    let nl = next.lowercased()
                    if nl.contains("resets") || nl.contains("reses") || nl.contains("reset") || nl.contains("rese") {
                        return parseResetTime(next) ?? next
                    }
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
                        if fiveHourResetsAt == nil {
                            fiveHourResetsAt = resetForSection(startLine: i)
                            if let r = fiveHourResetsAt { fiveHourResetsDate = parseResetDate(from: r) }
                        }
                    }
                }
            } else if isWeekly {
                if isOpus {
                    if weeklyOpus == nil { weeklyOpus = percentForSection(startLine: i) }
                    if weeklyResetsAt == nil {
                        weeklyResetsAt = resetForSection(startLine: i)
                        if let r = weeklyResetsAt { weeklyResetsDate = parseResetDate(from: r) }
                    }
                } else if isSonnet && !isAll {
                    if weeklyOpus == nil { weeklyOpus = percentForSection(startLine: i) }
                    if weeklyResetsAt == nil {
                        weeklyResetsAt = resetForSection(startLine: i)
                        if let r = weeklyResetsAt { weeklyResetsDate = parseResetDate(from: r) }
                    }
                } else {
                    if weeklyAll == nil {
                        weeklyAll = percentForSection(startLine: i)
                        if weeklyResetsAt == nil {
                            weeklyResetsAt = resetForSection(startLine: i)
                            if let r = weeklyResetsAt { weeklyResetsDate = parseResetDate(from: r) }
                        }
                    }
                }
            }

            // Cost parsing — look for today/monthly cost lines
            let isToday = lower.contains("today") && lower.contains("$")
            let isMonthly = (lower.contains("last 30") || lower.contains("last month") ||
                             lower.contains("monthly") || lower.contains("this month")) && lower.contains("$")

            if isToday && todayCost == nil {
                todayCost = extractDollar(line)
                todayTokens = extractTokens(line)
            }
            if isMonthly && monthlyCost == nil {
                monthlyCost = extractDollar(line)
                monthlyTokens = extractTokens(line)
            }
        }

        let planInfo = parsePlanInfo(result.welcomeText)

        return UsageSnapshot(
            fiveHourAll: fiveHourAll,
            fiveHourOpus: fiveHourOpus,
            weeklyAll: weeklyAll,
            weeklyOpus: weeklyOpus,
            fiveHourResetsAt: fiveHourResetsAt,
            weeklyResetsAt: weeklyResetsAt,
            fiveHourResetsDate: fiveHourResetsDate,
            weeklyResetsDate: weeklyResetsDate,
            todayCost: todayCost,
            todayTokens: todayTokens,
            monthlyCost: monthlyCost,
            monthlyTokens: monthlyTokens,
            modelName: planInfo.model,
            planName: planInfo.plan,
            fetchedAt: Date(),
            rawText: clean
        )
    }
}
