import AppKit
import SwiftUI

// MARK: - Cat menu bar icon (NSImage template)

private func makeCatIcon() -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size, flipped: true) { rect in
        let w = rect.width, h = rect.height
        let path = NSBezierPath()

        // Left ear
        path.move(to: NSPoint(x: w * 0.10, y: h * 0.33))
        path.line(to: NSPoint(x: w * 0.06, y: h * 0.01))
        path.line(to: NSPoint(x: w * 0.38, y: h * 0.22))
        path.close()

        // Right ear
        path.move(to: NSPoint(x: w * 0.90, y: h * 0.33))
        path.line(to: NSPoint(x: w * 0.94, y: h * 0.01))
        path.line(to: NSPoint(x: w * 0.62, y: h * 0.22))
        path.close()

        // Head
        path.appendOval(in: NSRect(x: w * 0.08, y: h * 0.20, width: w * 0.84, height: h * 0.80))

        NSColor.black.setFill()
        path.fill()
        return true
    }
    image.isTemplate = true
    return image
}

// MARK: - App entry point

@main
struct ClaudeUsageApp: App {
    @StateObject private var settings: Settings
    @StateObject private var store: UsageStore
    @State private var widgetManager = WidgetManager()

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
                .onAppear { widgetManager.update(store: store, settings: settings) }
                .onReceive(settings.$widgetMode) { _ in
                    widgetManager.update(store: store, settings: settings)
                }
        } label: {
            HStack(spacing: 3) {
                Image(nsImage: makeCatIcon())
                Text(store.menuBarLabel)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
