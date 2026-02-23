import SwiftUI

@main
struct ClaudeUsageApp: App {
    @StateObject private var settings: Settings
    @StateObject private var store: UsageStore

    init() {
        let s = Settings()
        _settings = StateObject(wrappedValue: s)
        _store = StateObject(wrappedValue: UsageStore(settings: s))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(settings)
        } label: {
            Text(store.menuBarLabel)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.menu)
    }
}
