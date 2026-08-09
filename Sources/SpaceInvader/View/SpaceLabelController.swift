import AppKit

// All panels use canJoinAllSpaces so they are present on every desktop.
// Visibility is controlled exclusively via alphaValue:
//   - active space arrival → flash (alphaValue 1 → 0 after 0.4 s)
//   - all other states     → alphaValue 0 (hidden)
// This avoids the class of bugs where CGS space-pinning silently fails
// and leaves a panel permanently visible on the wrong desktop.

@MainActor
final class SpaceLabelController {
    private var panels:    [String: NSPanel]          = [:]
    private var fadeTasks: [String: DispatchWorkItem] = [:]
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Public interface

    func update(spaces: [Space]) {
        let liveIDs = Set(spaces.map { $0.id })
        for id in Array(panels.keys) where !liveIDs.contains(id) {
            fadeTasks[id]?.cancel()
            fadeTasks.removeValue(forKey: id)
            panels[id]?.orderOut(nil)
            panels.removeValue(forKey: id)
        }
        let existingIDs = Set(panels.keys)
        for space in spaces where !space.isFullscreen && !existingIDs.contains(space.id) {
            createPanel(for: space)
        }
        syncVisibility(spaces: spaces)
    }

    func refreshAll(spaces: [Space]) {
        for space in spaces {
            guard let panel = panels[space.id] else { continue }
            updateContent(panel: panel, space: space)
        }
    }

    // MARK: - Visibility

    private func syncVisibility(spaces: [Space]) {
        for space in spaces {
            guard let panel = panels[space.id] else { continue }
            if space.isActive {
                fadeTasks[space.id]?.cancel()
                fadeTasks[space.id] = nil
                panel.alphaValue = 1
                let work = DispatchWorkItem { [weak panel] in
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.10
                        panel?.animator().alphaValue = 0
                    }
                }
                fadeTasks[space.id] = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
            } else if fadeTasks[space.id] == nil {
                panel.alphaValue = 0
            }
            // If a fade is in progress, let it complete.
        }
    }

    // MARK: - Panel factory

    private func createPanel(for space: Space) {
        let panel = makePanel(for: space)
        panels[space.id] = panel
        panel.alphaValue = 0
        panel.orderFront(nil)
    }

    private func makePanel(for space: Space) -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor    = .clear
        panel.isOpaque           = false
        panel.hasShadow          = false
        panel.level              = NSWindow.Level(rawValue: 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate  = false
        updateContent(panel: panel, space: space)
        return panel
    }

    private func overlayRect(screen: NSScreen) -> NSRect {
        let margin: CGFloat = 16
        let h:      CGFloat = 176
        return NSRect(
            x: screen.frame.minX + margin,
            y: screen.frame.minY + margin,
            width: screen.frame.width - margin * 2,
            height: h
        )
    }

    private func updateContent(panel: NSPanel, space: Space) {
        let text  = labelText(for: space)
        let color = NSColor(appState.resolvedColor(for: space))
        guard let screen = NSScreen.main else { return }
        let rect = overlayRect(screen: screen)
        panel.setFrame(rect, display: false)
        panel.contentView = OverlayView(
            text: text, color: color,
            frame: NSRect(origin: .zero, size: rect.size)
        )
    }

    private func labelText(for space: Space) -> String {
        let n = appState.name(for: space.id)
        return n.isEmpty ? space.displayLabel : n
    }
}

// MARK: - Overlay drawing

private final class OverlayView: NSView {
    private let text:  String
    private let color: NSColor

    init(text: String, color: NSColor, frame: NSRect) {
        self.text  = text
        self.color = color
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        color.withAlphaComponent(0.88).setFill()
        path.fill()

        let hPad: CGFloat = 24
        let str = text as NSString

        var fontSize = bounds.height * 0.95
        var font  = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        var sz    = str.size(withAttributes: attrs)
        if sz.width > bounds.width - hPad * 2 {
            fontSize *= (bounds.width - hPad * 2) / sz.width
            font      = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            attrs[.font] = font
            sz        = str.size(withAttributes: attrs)
        }

        str.draw(at: NSPoint(x: bounds.midX - sz.width  / 2,
                             y: bounds.midY - sz.height / 2),
                 withAttributes: attrs)
    }
}

extension Notification.Name {
    static let spaceMetadataChanged = Notification.Name("spaceMetadataChanged")
}
