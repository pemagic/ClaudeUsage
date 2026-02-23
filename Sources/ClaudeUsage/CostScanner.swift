import Foundation

struct CostData {
    let todayCostUSD: Double
    let todayTokens: Int
    let last30DaysCostUSD: Double
    let last30DaysTokens: Int

    static let empty = CostData(todayCostUSD: 0, todayTokens: 0, last30DaysCostUSD: 0, last30DaysTokens: 0)

    var formattedTodayCost: String { Self.fmtCost(todayCostUSD) }
    var formattedTodayTokens: String { Self.fmtTokens(todayTokens) }
    var formattedMonthlyCost: String { Self.fmtCost(last30DaysCostUSD) }
    var formattedMonthlyTokens: String { Self.fmtTokens(last30DaysTokens) }

    private static func fmtCost(_ usd: Double) -> String {
        if usd >= 100 { return String(format: "$%.0f", usd) }
        return String(format: "$%.2f", usd)
    }

    private static func fmtTokens(_ count: Int) -> String {
        if count >= 1_000_000_000 {
            return String(format: "%.1fB", Double(count) / 1_000_000_000)
        }
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.0fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

enum CostScanner {

    // MARK: - Pricing (per token, USD) — aligned with CodexBar

    private struct Pricing {
        let inputPerToken: Double
        let outputPerToken: Double
        let cacheCreatePerToken: Double
        let cacheReadPerToken: Double
        // Tiered pricing (Sonnet 200K+)
        let thresholdTokens: Int?
        let inputAbove: Double?
        let outputAbove: Double?
        let cacheCreateAbove: Double?
        let cacheReadAbove: Double?
    }

    // Per-token costs, keyed by normalized model name
    private static let pricing: [String: Pricing] = [
        // Opus 4.5 / 4.6 — $5/$25 per MTok
        "claude-opus-4-6": Pricing(
            inputPerToken: 5e-6, outputPerToken: 2.5e-5,
            cacheCreatePerToken: 6.25e-6, cacheReadPerToken: 5e-7,
            thresholdTokens: nil, inputAbove: nil, outputAbove: nil,
            cacheCreateAbove: nil, cacheReadAbove: nil),
        "claude-opus-4-5": Pricing(
            inputPerToken: 5e-6, outputPerToken: 2.5e-5,
            cacheCreatePerToken: 6.25e-6, cacheReadPerToken: 5e-7,
            thresholdTokens: nil, inputAbove: nil, outputAbove: nil,
            cacheCreateAbove: nil, cacheReadAbove: nil),
        // Opus 4.1 (legacy) — $15/$75 per MTok
        "claude-opus-4-1": Pricing(
            inputPerToken: 1.5e-5, outputPerToken: 7.5e-5,
            cacheCreatePerToken: 1.875e-5, cacheReadPerToken: 1.5e-6,
            thresholdTokens: nil, inputAbove: nil, outputAbove: nil,
            cacheCreateAbove: nil, cacheReadAbove: nil),
        // Sonnet 4.5 / 4.6 / 4 — $3/$15 per MTok, tiered above 200K
        "claude-sonnet-4-6": Pricing(
            inputPerToken: 3e-6, outputPerToken: 1.5e-5,
            cacheCreatePerToken: 3.75e-6, cacheReadPerToken: 3e-7,
            thresholdTokens: 200_000,
            inputAbove: 6e-6, outputAbove: 2.25e-5,
            cacheCreateAbove: 7.5e-6, cacheReadAbove: 6e-7),
        "claude-sonnet-4-5": Pricing(
            inputPerToken: 3e-6, outputPerToken: 1.5e-5,
            cacheCreatePerToken: 3.75e-6, cacheReadPerToken: 3e-7,
            thresholdTokens: 200_000,
            inputAbove: 6e-6, outputAbove: 2.25e-5,
            cacheCreateAbove: 7.5e-6, cacheReadAbove: 6e-7),
        "claude-sonnet-4": Pricing(
            inputPerToken: 3e-6, outputPerToken: 1.5e-5,
            cacheCreatePerToken: 3.75e-6, cacheReadPerToken: 3e-7,
            thresholdTokens: 200_000,
            inputAbove: 6e-6, outputAbove: 2.25e-5,
            cacheCreateAbove: 7.5e-6, cacheReadAbove: 6e-7),
        // Haiku 4.5 — $1/$5 per MTok
        "claude-haiku-4-5": Pricing(
            inputPerToken: 1e-6, outputPerToken: 5e-6,
            cacheCreatePerToken: 1.25e-6, cacheReadPerToken: 1e-7,
            thresholdTokens: nil, inputAbove: nil, outputAbove: nil,
            cacheCreateAbove: nil, cacheReadAbove: nil),
        "claude-haiku": Pricing(
            inputPerToken: 1e-6, outputPerToken: 5e-6,
            cacheCreatePerToken: 1.25e-6, cacheReadPerToken: 1e-7,
            thresholdTokens: nil, inputAbove: nil, outputAbove: nil,
            cacheCreateAbove: nil, cacheReadAbove: nil),
    ]

    /// Normalize model name: strip date suffix and try to find a matching key.
    private static func findPricing(for model: String) -> Pricing? {
        // Exact match
        if let p = pricing[model] { return p }
        // Strip date suffix: "claude-sonnet-4-5-20250929" → "claude-sonnet-4-5"
        if let dateRange = model.range(of: #"-\d{8}$"#, options: .regularExpression) {
            let base = String(model[..<dateRange.lowerBound])
            if let p = pricing[base] { return p }
        }
        // Prefix match (longest first)
        let sorted = pricing.keys.sorted { $0.count > $1.count }
        for key in sorted {
            if model.hasPrefix(key) { return pricing[key] }
        }
        return nil
    }

    /// Tiered cost: base rate below threshold, higher rate above.
    private static func tieredCost(tokens: Int, base: Double, above: Double?, threshold: Int?) -> Double {
        guard let threshold, let above else { return Double(max(0, tokens)) * base }
        let below = min(max(0, tokens), threshold)
        let over = max(0, tokens - threshold)
        return Double(below) * base + Double(over) * above
    }

    // MARK: - Scan

    static func scan() -> CostData {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let roots = ["\(home)/.claude/projects", "\(home)/.config/claude/projects"]

        let now = Date()
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        let cutoff = cal.date(byAdding: .day, value: -30, to: todayStart)!

        var best: [String: MsgUsage] = [:]

        let tf1 = ISO8601DateFormatter()
        tf1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tf2 = ISO8601DateFormatter()
        tf2.formatOptions = [.withInternetDateTime]

        for root in roots {
            guard let enumerator = fm.enumerator(atPath: root) else { continue }
            while let rel = enumerator.nextObject() as? String {
                guard rel.hasSuffix(".jsonl") else { continue }
                let path = "\(root)/\(rel)"
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let mdate = attrs[.modificationDate] as? Date,
                      mdate >= cutoff else { continue }
                scanFile(path: path, cutoff: cutoff, tf1: tf1, tf2: tf2, best: &best)
            }
        }

        // Aggregate with tiered pricing
        var todayCost = 0.0, todayTok = 0
        var totalCost = 0.0, totalTok = 0

        for (_, u) in best {
            guard let p = findPricing(for: u.model) else { continue }
            let cost = tieredCost(tokens: u.input, base: p.inputPerToken,
                                  above: p.inputAbove, threshold: p.thresholdTokens)
                     + tieredCost(tokens: u.output, base: p.outputPerToken,
                                  above: p.outputAbove, threshold: p.thresholdTokens)
                     + tieredCost(tokens: u.cacheRead, base: p.cacheReadPerToken,
                                  above: p.cacheReadAbove, threshold: p.thresholdTokens)
                     + tieredCost(tokens: u.cacheCreate, base: p.cacheCreatePerToken,
                                  above: p.cacheCreateAbove, threshold: p.thresholdTokens)
            let tok = u.total

            totalCost += cost
            totalTok += tok

            if u.date >= todayStart {
                todayCost += cost
                todayTok += tok
            }
        }

        return CostData(todayCostUSD: todayCost, todayTokens: todayTok,
                        last30DaysCostUSD: totalCost, last30DaysTokens: totalTok)
    }

    // MARK: - File scanner (line-by-line, memory-efficient)

    private struct MsgUsage {
        let model: String
        let input: Int
        let output: Int
        let cacheRead: Int
        let cacheCreate: Int
        let date: Date
        var total: Int { input + output + cacheRead + cacheCreate }
    }

    private static func scanFile(path: String, cutoff: Date,
                                  tf1: ISO8601DateFormatter, tf2: ISO8601DateFormatter,
                                  best: inout [String: MsgUsage]) {
        guard let fh = fopen(path, "r") else { return }
        defer { fclose(fh) }

        var buf = [CChar](repeating: 0, count: 524_288)
        while fgets(&buf, Int32(buf.count), fh) != nil {
            let line = String(cString: buf)
            guard line.contains("\"assistant\""), line.contains("\"usage\"") else { continue }

            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let msg = obj["message"] as? [String: Any],
                  let usage = msg["usage"] as? [String: Any],
                  let model = msg["model"] as? String, !model.isEmpty,
                  let msgId = msg["id"] as? String, !msgId.isEmpty,
                  let tsStr = obj["timestamp"] as? String,
                  let ts = tf1.date(from: tsStr) ?? tf2.date(from: tsStr),
                  ts >= cutoff
            else { continue }

            let u = MsgUsage(
                model: model,
                input: usage["input_tokens"] as? Int ?? 0,
                output: usage["output_tokens"] as? Int ?? 0,
                cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
                cacheCreate: usage["cache_creation_input_tokens"] as? Int ?? 0,
                date: ts
            )

            if let existing = best[msgId] {
                if u.total > existing.total { best[msgId] = u }
            } else {
                best[msgId] = u
            }
        }
    }
}
