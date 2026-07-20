import Foundation

struct Space: Identifiable, Equatable, Sendable {
    /// CGS space UUID — stable across reboots for the same display configuration.
    let id: String
    /// Raw CGS integer space ID — needed for window-to-space assignment APIs.
    let cgID: Int
    let displayID: String
    /// 1-based position across all spaces on all displays.
    let index: Int
    /// 1-based position among non-fullscreen spaces on this display; nil for fullscreen spaces.
    let desktopIndex: Int?
    let isActive: Bool
    let isFullscreen: Bool

    var displayLabel: String {
        if let d = desktopIndex { return "Space \(d)" }
        return "Fullscreen \(index)"
    }
}
