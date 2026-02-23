import Foundation

// Smoke test the parser with a simulated /usage output
let sample = """
\u{1B}[2J\u{1B}[H
╭─────────────────────────────────────────╮
│              Usage                      │
├─────────────────────────────────────────┤
│  Current session                        │
│    5h (all models):    73% used         │
│    Resets in 2h 15m                     │
│    5h (Opus):          45% used         │
├─────────────────────────────────────────┤
│  Current week (all models)              │
│    Weekly limit:       55% used         │
│    Resets in 3d 2h                      │
│    Weekly (Opus):      80% used         │
╰─────────────────────────────────────────╯
"""

let snap = UsageParser.parse(sample)
print("5h all:   \(snap.fiveHourAll.map { "\(Int($0*100))%" } ?? "nil")")
print("5h opus:  \(snap.fiveHourOpus.map { "\(Int($0*100))%" } ?? "nil")")
print("weekly:   \(snap.weeklyAll.map { "\(Int($0*100))%" } ?? "nil")")
print("w. opus:  \(snap.weeklyOpus.map { "\(Int($0*100))%" } ?? "nil")")
print("5h reset: \(snap.fiveHourResetsAt ?? "nil")")
print("wk reset: \(snap.weeklyResetsAt ?? "nil")")
