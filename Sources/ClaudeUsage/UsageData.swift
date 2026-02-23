import Foundation

struct UsageSnapshot {
    // Utilization as 0.0–1.0 (e.g. 0.73 = 73% used)
    let fiveHourAll: Double?
    let fiveHourOpus: Double?
    let weeklyAll: Double?
    let weeklyOpus: Double?
    let fiveHourResetsAt: String?
    let weeklyResetsAt: String?
    let fetchedAt: Date
    let rawText: String   // kept for debugging

    var isValid: Bool { fiveHourAll != nil || weeklyAll != nil }
}
