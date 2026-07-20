import AppKit

@MainActor
final class SpaceLabelController {
    private var panels:       [String: NSPanel] = [:]
    private var pinnedSpaces: Set<String>       = []
    private let appState: AppState
    nonisolated(unsafe) private var spaceChangeObserver: Any?
    private var fadeTasks:    [String: DispatchWorkItem] = [:]

    init(appState: AppState) {
        self.appState = appState
        observeSpaceChange()
    }

    deinit {
        if let o = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
    }

    // MARK: - Public interface

    func update(spaces: [Space]) {
        let liveIDs = Set(spaces.map { $0.id })
        for id in Array(panels.keys) where !liveIDs.contains(id) {
            panels[id]?.orderOut(nil)
            panels.removeValue(forKey: id)
            pinnedSpaces.remove(id)
        }
        let existingIDs = Set(panels.keys)
        let activeSpaceCGID = spaces.first(where: { $0.isActive })?.cgID ?? 0
        for space in spaces where !space.isFullscreen && !existingIDs.contains(space.id) {
            createAndPinPanel(for: space, activeSpaceCGID: activeSpaceCGID)
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
            guard let panel = panels[space.id], pinnedSpaces.contains(space.id) else { continue }
            fadeTasks[space.id]?.cancel()
            fadeTasks[space.id] = nil
            if space.isActive {
                // Flash the label on the newly active space, then fade it out.
                panel.alphaValue = 1
                let work = DispatchWorkItem { [weak panel] in
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.10
                        panel?.animator().alphaValue = 0
                    }
                }
                fadeTasks[space.id] = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
            } else {
                panel.alphaValue = 1
            }
        }
    }

    // MARK: - Observers

    private func observeSpaceChange() {
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.syncVisibility(spaces: self.appState.spaces)
            }
        }
    }

    // MARK: - Setup

    private func createAndPinPanel(for space: Space, activeSpaceCGID: Int) {
        let panel = makePanel(for: space)
        panels[space.id] = panel
        panel.alphaValue = 0
        panel.orderFront(nil)

        if space.isActive {
            pinnedSpaces.insert(space.id)
        } else {
            let spaceID   = space.id
            let isActive  = space.isActive
            let targetSID = UInt64(space.cgID)
            let sourceSID = UInt64(activeSpaceCGID)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak panel] in
                guard let self, let panel else { return }
                self.pinPanel(panel, toSpaceID: targetSID, fromSpaceID: sourceSID)
                self.pinnedSpaces.insert(spaceID)
                panel.alphaValue = isActive ? 0 : 1
            }
        }
    }

    private func pinPanel(_ panel: NSPanel, toSpaceID sid: UInt64, fromSpaceID: UInt64) {
        let wid = UInt32(panel.windowNumber)
        guard wid != 0, sid != 0, fromSpaceID != 0 else { return }
        let conn = _CGSDefaultConnection()
        SIMoveWindowToSpace(conn, wid, sid, fromSpaceID)
    }

    // MARK: - Panel factory

    private func makePanel(for space: Space) -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque        = false
        panel.hasShadow       = false
        panel.level           = NSWindow.Level(rawValue: 1)
        panel.collectionBehavior = [.ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate  = false
        updateContent(panel: panel, space: space)
        return panel
    }

    private func overlayRect(screen: NSScreen, text: String) -> NSRect {
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
        let rect = overlayRect(screen: screen, text: text)
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
