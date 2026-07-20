import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private var popover: NSPopover?
    private var preferencesWindow: NSWindow?
    private let appState: AppState
    private let timeTracker: TimeTracker
    private var clickMonitor: Any?
    var onCheckForUpdates: (() -> Void)?

    // Cached spaces for building the popover view
    private var currentSpaces: [Space] = []

    init(appState: AppState, timeTracker: TimeTracker) {
        self.appState = appState
        self.timeTracker = timeTracker
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openPreferences),
            name: .openPreferences,
            object: nil
        )
    }

    func update(spaces: [Space]) {
        currentSpaces = spaces

        if let active = spaces.first(where: { $0.isActive }),
           let button = statusItem.button {
            let name = appState.name(for: active.id)
            let idx = active.desktopIndex ?? active.index
            let nsColor = NSColor(appState.resolvedColor(for: active))
            button.image = MenuBarImageRenderer.activeSpaceBadge(index: idx, name: name, color: nsColor)
            button.imagePosition = .imageOnly
        }

        // Refresh popover content if it's open
        if let pop = popover, pop.isShown {
            rebuildPopoverContent()
        }
    }

    // MARK: - Private

    private func configureButton() {
        statusItem.isVisible = true
        guard let button = statusItem.button else { return }
        button.image = MenuBarImageRenderer.spaceInvaderIcon()
        button.imagePosition = .imageOnly
        button.action = #selector(buttonClicked(_:))
        button.target = self
        // Receive both left and right clicks
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        if let pop = popover, pop.isShown {
            closePopover()
        } else {
            showPopover(from: sender)
        }
    }

    private func showPopover(from button: NSStatusBarButton) {
        let pop = NSPopover()
        pop.behavior = .applicationDefined  // we manage dismissal manually
        pop.animates = false
        rebuildContent(for: pop)
        popover = pop

        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Dismiss on click anywhere outside
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        popover?.close()
        popover = nil
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
    }

    private func rebuildPopoverContent() {
        guard let pop = popover else { return }
        rebuildContent(for: pop)
    }

    private func rebuildContent(for pop: NSPopover) {
        let view = StatusMenuView(
            spaces: currentSpaces,
            appState: appState,
            onSpaceSelect: { [weak self] (space: Space) in
                self?.closePopover()
                SpaceSwitcher.shared.switchToSpace(space)
            },
            onPreferences: { [weak self] in
                self?.closePopover()
                self?.openPreferences()
            },
            onCheckForUpdates: { [weak self] in
                self?.closePopover()
                self?.onCheckForUpdates?()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
        let vc = NSHostingController(rootView: view)
        // Let the SwiftUI view size the popover
        vc.view.layout()
        pop.contentViewController = vc
        pop.contentSize = vc.view.fittingSize
    }

    @objc private func openPreferences() {
        closePopover()
        if preferencesWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "SpaceInvader"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: PreferencesView()
                    .environmentObject(appState)
                    .environmentObject(timeTracker)
            )
            preferencesWindow = window
        }
        preferencesWindow?.center()
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

