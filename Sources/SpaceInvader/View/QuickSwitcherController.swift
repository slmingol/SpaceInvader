import AppKit
import SwiftUI

@MainActor
final class QuickSwitcherController {
    private var panel: NSPanel?
    private let appState: AppState
    // Saved so we can restore focus when the panel closes, preventing our app
    // from staying frontmost (which would make the local mouse monitor fire everywhere).
    private var previousApp: NSRunningApplication?

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        if panel == nil { buildPanel() }
        guard let panel, let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let barH = NSStatusBar.system.thickness
        previousApp = NSWorkspace.shared.frontmostApplication
        // Drop from top-right, just below the menu bar.
        panel.setFrameOrigin(NSPoint(
            x: screen.frame.maxX - size.width - 10,
            y: screen.frame.maxY - barH - size.height - 4
        ))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
        previousApp?.activate(options: [])
        previousApp = nil
    }

    private func buildPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .transient]
        p.contentView = NSHostingView(
            rootView: QuickSwitcherView(onDismiss: { [weak self] in self?.hide() })
                .environmentObject(appState)
        )
        panel = p
    }
}
