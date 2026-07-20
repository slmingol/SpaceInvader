import AppKit
import Combine
import QuartzCore
import SwiftUI

// The HUD has two stable states:
//   collapsed  — a notch-sized pill fully behind the menu bar (invisible)
//   expanded   — a dark box from the top of the screen to below the tiles
//
// panelW is dynamic: computed from the current space count so there is no
// extra black space on the sides.  A Combine subscription rebuilds the frames
// and resizes the hosting view whenever spaces change.

@MainActor
final class SpaceHUDController {
    private var panel: NSPanel?
    private weak var hostingView: NSView?
    private weak var clipView: NSView?

    nonisolated(unsafe) private var globalMonitor: Any?
    nonisolated(unsafe) private var localMonitor: Any?
    nonisolated(unsafe) private var mouseDownMonitor: Any?
    private var spacesCancellable: AnyCancellable?

    private var dwellTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    private var hideDelayTask: Task<Void, Never>?
    private var hideAnimTask: Task<Void, Never>?

    private var finalFrame: NSRect = .zero
    private var notchFrame: NSRect = .zero
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        buildPanel()
        startTracking()

        // Rebuild frames and resize hosting view when the space list changes.
        spacesCancellable = appState.$spaces
            .dropFirst()
            .sink { [weak self] spaces in
                Task { @MainActor [weak self] in self?.spacesDidChange(spaces) }
            }
    }

    deinit {
        if let m = globalMonitor    { NSEvent.removeMonitor(m) }
        if let m = localMonitor     { NSEvent.removeMonitor(m) }
        if let m = mouseDownMonitor { NSEvent.removeMonitor(m) }
    }

    // Called externally (e.g. AppDelegate hotkey handlers) to collapse immediately.
    func collapseNow() {
        revealTask?.cancel(); revealTask = nil
        hideDelayTask?.cancel(); hideDelayTask = nil
        if hideAnimTask == nil { collapse() }
    }

    // MARK: - Panel

    private func buildPanel() {
        guard let screen = NSScreen.main else { return }
        updateFrames(for: screen)

        let p = NSPanel(
            contentRect: notchFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.alphaValue = 1

        let clip = NSView(frame: NSRect(origin: .zero, size: notchFrame.size))
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.layer?.cornerRadius = 14
        clip.layer?.cornerCurve = .continuous
        // Square top corners (against the screen edge); rounded bottom only.
        clip.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        clip.autoresizingMask = [.width, .height]

        let hv = NSHostingView(rootView: SpaceHUDView().environmentObject(appState))
        hv.frame = NSRect(origin: .zero, size: finalFrame.size)
        hv.autoresizingMask = []
        clip.addSubview(hv)

        p.contentView = clip
        p.setFrame(notchFrame, display: false)
        updateHostingPosition(panelSize: notchFrame.size)
        p.orderFront(nil)

        panel    = p
        hostingView = hv
        clipView    = clip
    }

    private func updateFrames(for screen: NSScreen) {
        let barH          = NSStatusBar.system.thickness
        let menuBarBottom = screen.frame.maxY - barH
        let panelW        = computePanelWidth(for: appState.spaces)

        // Collapsed pill is fully hidden behind the menu bar.
        let notchW: CGFloat = min(164, panelW)
        let notchH: CGFloat = 18
        notchFrame = NSRect(
            x: screen.frame.midX - notchW / 2,
            y: menuBarBottom,
            width: notchW, height: notchH
        )

        // Expanded box: top at screen top, tiles 10pt below menu bar.
        let tileH: CGFloat = 86, gap: CGFloat = 10
        let panelH = barH + gap + tileH
        finalFrame = NSRect(
            x: screen.frame.midX - panelW / 2,
            y: screen.frame.maxY - panelH,
            width: panelW, height: panelH
        )
    }

    // Width matches the content: each tile is 54pt, spacing 8pt, 20pt horizontal padding.
    // Multi-display groups add a 1pt separator between them.
    private func computePanelWidth(for spaces: [Space]) -> CGFloat {
        let tileW: CGFloat = 54, separatorW: CGFloat = 1
        let spacing: CGFloat = 8, hPad: CGFloat = 20

        let desktop = spaces.filter { !$0.isFullscreen }
        guard !desktop.isEmpty else { return 200 }

        var seen = Set<String>()
        var groupCount = 0
        for s in desktop {
            if seen.insert(s.displayID).inserted { groupCount += 1 }
        }
        let n = desktop.count
        // Items in the HStack: n tiles + (groupCount-1) separators, each
        // separated by `spacing`.
        let itemCount = n + (groupCount - 1)
        return CGFloat(n) * tileW
            + CGFloat(groupCount - 1) * separatorW
            + CGFloat(max(0, itemCount - 1)) * spacing
            + hPad
    }

    private func spacesDidChange(_ spaces: [Space]) {
        guard let screen = NSScreen.main else { return }
        let oldW = finalFrame.width
        updateFrames(for: screen)

        if abs(oldW - finalFrame.width) > 1 {
            hostingView?.frame.size = finalFrame.size
            // If the panel is resting at the expanded position, snap it to the new size.
            if revealTask == nil, hideAnimTask == nil, let panel {
                if panel.frame.width > notchFrame.width + 20 {
                    panel.setFrame(finalFrame, display: false)
                    updateHostingPosition(panelSize: finalFrame.size)
                }
            }
        }

        // On any space switch, force-collapse regardless of mouse position.
        // Keyboard switches don't generate mouse events so handleGlobalMouse never
        // fires; scheduleCollapse is unreliable here because a mouse drift near the
        // notch during the transition animation cancels the timer. Call collapse()
        // directly — if the panel is already at notch this is a no-op visually.
        revealTask?.cancel(); revealTask = nil
        hideDelayTask?.cancel(); hideDelayTask = nil
        if hideAnimTask == nil { collapse() }
    }

    // Bottom-align the hosting view in the clip so tiles stay at the panel bottom.
    private func updateHostingPosition(panelSize: NSSize) {
        guard let hv = hostingView else { return }
        hv.frame.origin = NSPoint(
            x: (panelSize.width - finalFrame.width) / 2,
            y: 0
        )
    }

    // MARK: - Mouse tracking

    private func startTracking() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleGlobalMouse() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor [weak self] in self?.handleLocalMouse() }
            return event
        }
        // SwiftUI buttons in nonactivating panels can fail to fire their action when
        // the app is not frontmost. Intercept leftMouseDown directly and handle the
        // space switch ourselves so it always works regardless of activation state.
        // Collapse the HUD first (matching status menu's close-then-switch pattern),
        // then switch asynchronously so the collapse animation isn't fighting the
        // space transition.
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let loc = event.locationInWindow
            let clickedWindow = event.window
            var handled = false
            MainActor.assumeIsolated {
                guard let self else { return }
                guard clickedWindow === self.panel else { return }
                guard let panel = self.panel, panel.frame.width > self.notchFrame.width + 20 else { return }
                guard let space = self.spaceForClick(at: loc) else { return }
                handled = true
                self.collapseNow()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    SpaceSwitcher.shared.switchToSpace(space)
                }
            }
            // Consume the event so the SwiftUI Button in SpaceTile doesn't also
            // call switchToSpace and trigger a double swipe.
            return handled ? nil : event
        }
    }

    // Hit-test the click location (in panel/clip-view coordinates) against the tile grid.
    // Returns the matching Space if the click lands on a tile, nil otherwise.
    private func spaceForClick(at loc: CGPoint) -> Space? {
        let tileH: CGFloat = 86
        guard loc.y < tileH else { return nil }  // Spacer area above tiles

        let desktop = appState.spaces.filter { !$0.isFullscreen }
        guard !desktop.isEmpty else { return nil }

        // Rebuild display groups in the same order as SpaceHUDView.displayGroups.
        var groups: [(String, [Space])] = []
        var seen: [String: Int] = [:]
        for space in desktop {
            if let i = seen[space.displayID] {
                groups[i].1.append(space)
            } else {
                seen[space.displayID] = groups.count
                groups.append((space.displayID, [space]))
            }
        }

        // Mirror the HStack layout: spacing=8, tiles=54pt, separators=1pt, hPad=10.
        let tileW: CGFloat = 54, spacing: CGFloat = 8, hPad: CGFloat = 10, sepW: CGFloat = 1
        var x: CGFloat = hPad

        for (gi, group) in groups.enumerated() {
            if gi > 0 { x += spacing + sepW + spacing }
            for (si, space) in group.1.enumerated() {
                if si > 0 { x += spacing }
                if loc.x >= x && loc.x < x + tileW { return space }
                x += tileW
            }
        }
        return nil
    }

    private func handleGlobalMouse() {
        let mouse = NSEvent.mouseLocation
        guard let panel else { return }

        if isNearNotch(mouse) {
            if hideAnimTask == nil {
                hideDelayTask?.cancel(); hideDelayTask = nil
            }
            if revealTask == nil && panel.frame.width < finalFrame.width - 20 {
                startDwell()
            }
        } else {
            cancelDwell()
            if panel.frame.width > notchFrame.width + 20 && hideAnimTask == nil {
                if !isJustBelowExpandedPanel(mouse) {
                    scheduleCollapse()
                }
            }
        }
    }

    // Returns true when the mouse has exited the panel bottom by no more than
    // 20pt — suppresses the collapse timer in that small grace zone.
    private func isJustBelowExpandedPanel(_ point: NSPoint) -> Bool {
        let buffer: CGFloat = 20
        return point.y > finalFrame.minY - buffer
            && point.y < finalFrame.minY
            && abs(point.x - finalFrame.midX) < finalFrame.width / 2
    }

    private func handleLocalMouse() {
        if hideAnimTask != nil {
            hideDelayTask?.cancel(); hideDelayTask = nil
            hideAnimTask?.cancel(); hideAnimTask = nil
            expand()
        } else {
            hideDelayTask?.cancel(); hideDelayTask = nil
        }
    }

    private func isNearNotch(_ point: NSPoint) -> Bool {
        guard let screen = NSScreen.main else { return false }
        let barH = NSStatusBar.system.thickness
        return abs(point.x - screen.frame.midX) < 160
            && point.y > screen.frame.maxY - barH - 40
            && point.y <= screen.frame.maxY
    }

    // MARK: - Dwell

    private func startDwell() {
        guard dwellTask == nil else { return }
        dwellTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self.dwellTask = nil
            self.expand()
        }
    }

    private func cancelDwell() {
        dwellTask?.cancel(); dwellTask = nil
    }

    // MARK: - Expand

    private func expand() {
        hideDelayTask?.cancel(); hideDelayTask = nil
        hideAnimTask?.cancel(); hideAnimTask = nil
        guard let panel, revealTask == nil else { return }

        let startRect = panel.frame
        let duration  = 0.25

        revealTask = Task { @MainActor in
            let startT = CACurrentMediaTime()
            while !Task.isCancelled {
                let progress = min(1.0, (CACurrentMediaTime() - startT) / duration)
                let eased    = 1 - pow(1 - progress, 3)

                guard let panel = self.panel else { break }
                let f = self.lerp(from: startRect, to: self.finalFrame, t: CGFloat(eased))
                panel.setFrame(f, display: false)
                self.updateHostingPosition(panelSize: f.size)

                if progress >= 1 {
                    panel.setFrame(self.finalFrame, display: false)
                    self.updateHostingPosition(panelSize: self.finalFrame.size)
                    break
                }
                try? await Task.sleep(nanoseconds: 16_666_667)
            }
            self.revealTask = nil
        }
    }

    // MARK: - Collapse

    private func scheduleCollapse() {
        guard hideDelayTask == nil, hideAnimTask == nil else { return }
        hideDelayTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self.hideDelayTask = nil
            self.collapse()
        }
    }

    private func collapse() {
        revealTask?.cancel(); revealTask = nil
        guard let panel, hideAnimTask == nil else { return }

        let startRect = panel.frame
        let duration  = 0.18

        hideAnimTask = Task { @MainActor in
            let startT = CACurrentMediaTime()
            while !Task.isCancelled {
                let progress = min(1.0, (CACurrentMediaTime() - startT) / duration)
                let eased    = progress * progress

                guard let panel = self.panel else { break }
                let f = self.lerp(from: startRect, to: self.notchFrame, t: CGFloat(eased))
                panel.setFrame(f, display: false)
                self.updateHostingPosition(panelSize: f.size)

                if progress >= 1 {
                    panel.setFrame(self.notchFrame, display: false)
                    self.updateHostingPosition(panelSize: self.notchFrame.size)
                    break
                }
                try? await Task.sleep(nanoseconds: 16_666_667)
            }
            self.hideAnimTask = nil
        }
    }

    // MARK: - Geometry

    private func lerp(from a: NSRect, to b: NSRect, t: CGFloat) -> NSRect {
        NSRect(
            x:      a.minX   + (b.minX   - a.minX)   * t,
            y:      a.minY   + (b.minY   - a.minY)   * t,
            width:  a.width  + (b.width  - a.width)  * t,
            height: a.height + (b.height - a.height) * t
        )
    }
}
