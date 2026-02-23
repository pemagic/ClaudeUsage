import AppKit
import SwiftUI

// MARK: - Desktop Widget Window

final class DesktopWidgetWindow: NSWindow {
    private let store: UsageStore
    private let settings: Settings

    init(store: UsageStore, settings: Settings) {
        self.store = store
        self.settings = settings

        let size = settings.widgetMode == 1
            ? NSSize(width: 180, height: 190)
            : NSSize(width: 340, height: 160)

        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        level = .init(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden

        // Frosted glass background
        let visualEffect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 16
        visualEffect.layer?.masksToBounds = true

        // SwiftUI content
        let rootView: AnyView
        if settings.widgetMode == 1 {
            rootView = AnyView(
                SmallWidgetView()
                    .environmentObject(store)
                    .environmentObject(settings)
            )
        } else {
            rootView = AnyView(
                MediumWidgetView()
                    .environmentObject(store)
                    .environmentObject(settings)
            )
        }

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]

        // Layer the views: visual effect behind, hosting view on top
        visualEffect.addSubview(hostingView)
        contentView = visualEffect

        // Restore saved position or center on screen
        restorePosition()
    }

    // MARK: - Position persistence

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        savePosition()
    }

    private func savePosition() {
        UserDefaults.standard.set(frame.origin.x, forKey: "widgetX")
        UserDefaults.standard.set(frame.origin.y, forKey: "widgetY")
    }

    private func restorePosition() {
        let x = UserDefaults.standard.object(forKey: "widgetX") as? CGFloat
        let y = UserDefaults.standard.object(forKey: "widgetY") as? CGFloat

        if let x, let y {
            setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            center()
        }
    }

    // MARK: - Prevent activation stealing

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Widget Manager

@MainActor
final class WidgetManager {
    private var window: DesktopWidgetWindow?

    func update(store: UsageStore, settings: Settings) {
        let mode = settings.widgetMode

        if mode == 0 {
            dismiss()
            return
        }

        // Recreate window if mode changed or window doesn't exist
        if window == nil || currentMode() != mode {
            dismiss()
            window = DesktopWidgetWindow(store: store, settings: settings)
            window?.orderFront(nil)
        }
    }

    func close() {
        dismiss()
    }

    /// Hide and release the window without triggering close animations
    /// that cause use-after-free in _NSWindowTransformAnimation.
    private func dismiss() {
        window?.orderOut(nil)
        window = nil
    }

    private func currentMode() -> Int {
        // Check current window size to determine mode
        guard let w = window else { return 0 }
        return w.frame.width < 250 ? 1 : 2
    }
}
