import Foundation

struct UsageSnapshot {
    // Utilization as 0.0–1.0 (e.g. 0.73 = 73% used)
    let fiveHourAll: Double?
    let fiveHourOpus: Double?
    let weeklyAll: Double?
    let weeklyOpus: Double?
    let fiveHourResetsAt: String?
    let weeklyResetsAt: String?

    // Parsed reset dates for countdown display and pace calculation
    let fiveHourResetsDate: Date?
    let weeklyResetsDate: Date?

    // Cost data from CLI (nil when not present in output)
    let todayCost: String?       // e.g. "30.87"
    let todayTokens: String?     // e.g. "309M"
    let monthlyCost: String?
    let monthlyTokens: String?

    // Plan info from welcome screen (e.g. "Opus 4.6 · Claude Max")
    let modelName: String?       // e.g. "Opus 4.6"
    let planName: String?        // e.g. "Claude Max"

    let fetchedAt: Date
    let rawText: String   // kept for debugging

    var isValid: Bool { fiveHourAll != nil || weeklyAll != nil }
}

/// Raw output from the CLI containing both welcome screen and /usage data.
struct FetchResult {
    let welcomeText: String
    let usageText: String
}
