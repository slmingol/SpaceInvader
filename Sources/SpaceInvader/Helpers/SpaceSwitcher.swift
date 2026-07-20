import AppKit
import ApplicationServices

final class SpaceSwitcher {
    nonisolated(unsafe) static let shared = SpaceSwitcher()
    private init() {}

    nonisolated(unsafe) var activeDesktopIndex: Int = 1

    func switchToSpace(_ space: Space) {
        guard let targetIdx = space.desktopIndex else {
            NSLog("[SpaceInvader] switchToSpace: space has no desktopIndex")
            return
        }
        let currentIdx = activeDesktopIndex
        SISwitchSpaceByGesture(UInt32(targetIdx - 1), UInt32(currentIdx - 1))
    }
}
