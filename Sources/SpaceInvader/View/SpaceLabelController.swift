import AppKit

// One borderless panel per desktop space, pinned to that space via CGS.
//
// Pinning contract on macOS 26 (verified empirically on 26.6 / 25G72):
//
//  1. A window is NOT assigned to any space when -orderFront: returns. The
//     WindowServer publishes the assignment asynchronously, and only once the
//     main runloop turns — wall-clock delay alone is not enough. Pinning before
//     SIWindowIsSpaceRegistered() is true is a silent no-op (0/20 in testing):
//     the registration that lands afterwards overwrites the pin with whatever
//     space was current at the time.
//
//  2. Add-to-target + remove-from-source is not race-free. The source space is
//     sampled when the panel is built; if the user changes spaces before the
//     pin runs, the remove targets a space the window was never on and the
//     window is left on BOTH spaces. SIPinWindowToSpace does it in one call and
//     needs no source, so the race cannot occur.
//
//  3. orderOut: drops the pin. A panel ordered back in reverts to the current
//     space. Live panels are therefore never ordered out — they are hidden with
//     alphaValue only, and ordered out solely when destroyed.
//
//  4. Nothing guarantees the pin survives OS-side events (display changes,
//     space add/remove, WindowServer restarts), so every space change also runs
//     a reconcile pass that re-pins any panel that has drifted.
//
// Visibility: a panel on a space the user is NOT on stays at full alpha, which
// is what makes it appear in that space's Mission Control thumbnail. The panel
// on the *active* space flashes briefly and then fades out so it does not sit
// on top of the user's work.

@MainActor
final class SpaceLabelController {
    private static let pollInterval: Duration = .milliseconds(50)
    private static let maxAttempts  = 60          // ~3 s before giving up

    private var panels:    [String: NSPanel]          = [:]
    private var targets:   [String: UInt64]           = [:]   // space key -> desired id64
    private var pinTasks:  [String: Task<Void, Never>] = [:]
    private var unpinned:  Set<String>                = []    // pinning gave up; alpha-only
    private var fadeTasks:    [String: DispatchWorkItem] = [:]
    private var restoreTasks: [String: DispatchWorkItem] = [:]
    private let appState: AppState

    /// Schedules `body` and clears its own slot when it runs, so a later pass
    /// can tell "nothing pending" from "already ran".
    private func schedule(_ store: inout [String: DispatchWorkItem],
                          _ key: String,
                          after delay: TimeInterval,
                          _ body: @escaping @MainActor () -> Void) {
        var work: DispatchWorkItem!
        work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                body()
                if self?.fadeTasks[key]    === work { self?.fadeTasks[key]    = nil }
                if self?.restoreTasks[key] === work { self?.restoreTasks[key] = nil }
            }
        }
        store[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancel(_ store: inout [String: DispatchWorkItem], _ key: String) {
        store[key]?.cancel()
        store[key] = nil
    }

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Public interface

    func update(spaces: [Space]) {
        let liveIDs = Set(spaces.map { $0.id })
        for id in Array(panels.keys) where !liveIDs.contains(id) {
            destroyPanel(id)
        }

        let existingIDs = Set(panels.keys)
        for space in spaces where !space.isFullscreen && !existingIDs.contains(space.id) {
            createPanel(for: space)
        }

        reconcilePins(spaces: spaces)
        syncVisibility(spaces: spaces)
    }

    func refreshAll(spaces: [Space]) {
        for space in spaces {
            guard let panel = panels[space.id] else { continue }
            updateContent(panel: panel, space: space)
        }
    }

    // MARK: - Pinning

    /// Re-pins any panel that has drifted off its target space. Cheap: one CGS
    /// query per panel, and a pin call only when the assignment is actually wrong.
    private func reconcilePins(spaces: [Space]) {
        let conn = _CGSDefaultConnection()
        for space in spaces where !space.isFullscreen {
            guard
                let panel  = panels[space.id],
                let target = targets[space.id],
                pinTasks[space.id] == nil,          // a pin attempt is already in flight
                !unpinned.contains(space.id)
            else { continue }

            let wid = windowID(of: panel)
            guard wid != 0, SIWindowIsSpaceRegistered(conn, wid) else { continue }
            if SIWindowIsPinnedToSpace(conn, wid, target) { continue }

            startPinning(key: space.id, target: target)
        }
    }

    private func startPinning(key: String, target: UInt64) {
        pinTasks[key]?.cancel()
        pinTasks[key] = Task { @MainActor [weak self] in
            let conn = _CGSDefaultConnection()

            for _ in 0 ..< Self.maxAttempts {
                if Task.isCancelled { return }
                guard let self, let panel = self.panels[key] else { return }

                let wid = self.windowID(of: panel)
                // Step 1: wait for the WindowServer to register the window at all.
                // Step 2: once registered, pin and re-verify on a later pass.
                if wid != 0, SIWindowIsSpaceRegistered(conn, wid) {
                    if SIWindowIsPinnedToSpace(conn, wid, target) {
                        self.pinTasks[key] = nil
                        self.unpinned.remove(key)
                        return
                    }
                    _ = SIPinWindowToSpace(conn, wid, target)
                }

                // Yields to the runloop, which is what lets registration land.
                try? await Task.sleep(for: Self.pollInterval)
            }

            guard let self else { return }
            self.pinTasks[key] = nil
            self.abandonPinning(key: key)
        }
    }

    /// Pinning never took. Rather than leave a panel stranded on the wrong
    /// desktop, make it all-spaces and drive it purely with alpha, which is the
    /// behaviour that cannot misplace a label. Costs the Mission Control
    /// thumbnail for this one space only.
    private func abandonPinning(key: String) {
        guard let panel = panels[key] else { return }
        unpinned.insert(key)
        cancel(&restoreTasks, key)
        cancel(&fadeTasks, key)
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.alphaValue = 0
        NSLog("[SpaceInvader] pinning failed for space \(key); falling back to alpha-only")
    }

    private func windowID(of panel: NSPanel) -> UInt32 {
        let n = panel.windowNumber
        return n > 0 ? UInt32(truncatingIfNeeded: n) : 0
    }

    // MARK: - Visibility

    private func syncVisibility(spaces: [Space]) {
        for space in spaces {
            guard let panel = panels[space.id] else { continue }

            let key = space.id

            if space.isActive {
                // Flash on arrival, then get out of the way.
                cancel(&restoreTasks, key)
                cancel(&fadeTasks, key)
                panel.alphaValue = 1
                schedule(&fadeTasks, key, after: 0.4) { [weak panel] in
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.10
                        panel?.animator().alphaValue = 0
                    }
                }
            } else if unpinned.contains(key) {
                // Fallback panels live on every space; they must stay hidden.
                cancel(&restoreTasks, key)
                if fadeTasks[key] == nil { panel.alphaValue = 0 }
            } else if restoreTasks[key] == nil {
                // Pinned panels stay lit so the space's Mission Control
                // thumbnail carries the label. An in-flight arrival fade is
                // deliberately left to finish, and the restore is deferred past
                // the space-switch animation — otherwise the label pops back in
                // while the desktop the user just left is still sliding away.
                schedule(&restoreTasks, key, after: 0.8) { [weak panel] in
                    panel?.alphaValue = 1
                }
            }
        }
    }

    // MARK: - Panel lifecycle

    private func createPanel(for space: Space) {
        let panel = makePanel(for: space)
        panels[space.id]  = panel
        targets[space.id] = UInt64(space.cgID)
        panel.alphaValue  = 0
        panel.orderFront(nil)          // window ID is only meaningful after this
        startPinning(key: space.id, target: UInt64(space.cgID))
    }

    private func destroyPanel(_ id: String) {
        pinTasks[id]?.cancel()
        pinTasks.removeValue(forKey: id)
        cancel(&fadeTasks, id)
        cancel(&restoreTasks, id)
        unpinned.remove(id)
        targets.removeValue(forKey: id)
        panels[id]?.orderOut(nil)
        panels.removeValue(forKey: id)
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
        // No .canJoinAllSpaces: it is mutually exclusive with per-space pinning.
        panel.collectionBehavior = [.ignoresCycle]
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
