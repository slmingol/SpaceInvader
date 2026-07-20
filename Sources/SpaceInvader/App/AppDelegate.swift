import AppKit
import KeyboardShortcuts
import ApplicationServices
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var hudController: SpaceHUDController?
    private var quickSwitcherController: QuickSwitcherController?
    private var spaceLabelController: SpaceLabelController?
    private var spaceObserver: SpaceObserver?
    private let appState = AppState()
    private let timeTracker = TimeTracker()
    private var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        requestAccessibilityIfNeeded()

        statusBarController = StatusBarController(appState: appState, timeTracker: timeTracker)
        statusBarController?.onCheckForUpdates = { [weak self] in
            self?.updaterController?.checkForUpdates(nil)
        }
        hudController = SpaceHUDController(appState: appState)
        quickSwitcherController = QuickSwitcherController(appState: appState)
        spaceLabelController = SpaceLabelController(appState: appState)

        let observer = SpaceObserver { [weak self] spaces in
            guard let self else { return }
            self.appState.spaces = spaces
            self.spaceLabelController?.update(spaces: spaces)
            self.statusBarController?.update(spaces: spaces)
            if let active = spaces.first(where: { $0.isActive && !$0.isFullscreen }),
               let idx = active.desktopIndex {
                SpaceSwitcher.shared.activeDesktopIndex = idx
            }
            if let active = spaces.first(where: { $0.isActive }) {
                self.timeTracker.recordActiveSpace(active)
            }
        }
        spaceObserver = observer

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(spaceMetadataChanged),
            name: .spaceMetadataChanged,
            object: nil
        )

        setupHotkeys()
        observer.start()
    }

    @objc private func spaceMetadataChanged() {
        spaceLabelController?.refreshAll(spaces: appState.spaces)
    }

    private func setupHotkeys() {
        applyDefaultShortcutsIfNeeded()

        KeyboardShortcuts.onKeyDown(for: .quickSwitcher) { [weak self] in
            self?.quickSwitcherController?.show()
        }
        for i in 1 ... 10 {
            guard let name = KeyboardShortcuts.Name.jumpToSpace(i) else { continue }
            let index = i
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                guard let self else { return }
                self.hudController?.collapseNow()
                if let space = self.appState.spaces.first(where: {
                    !$0.isFullscreen && $0.desktopIndex == index
                }) {
                    SpaceSwitcher.shared.switchToSpace(space)
                }
            }
        }
    }

    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let key = "AXTrustedCheckOptionPrompt"
        let opts = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    private func applyDefaultShortcutsIfNeeded() {
        for i in 1 ... 9 {
            guard let name = KeyboardShortcuts.Name.jumpToSpace(i) else { continue }
            let key = "KeyboardShortcuts_\(name.rawValue)"
            if UserDefaults.standard.object(forKey: key) == nil {
                KeyboardShortcuts.reset(name)
            }
        }
    }
}
