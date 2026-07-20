import AppKit

final class SpaceObserver {
    private let onChange: @MainActor ([Space]) -> Void

    init(onChange: @escaping @MainActor ([Space]) -> Void) {
        self.onChange = onChange
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(refresh),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        refresh()
    }

    @objc func refresh() {
        let spaces = readSpaces()
        let handler = onChange
        Task { @MainActor in
            handler(spaces)
        }
    }

    private func readSpaces() -> [Space] {
        let conn = _CGSDefaultConnection()
        guard let rawDisplays = CGSCopyManagedDisplaySpaces(conn) as? [[String: Any]] else { return [] }
        return parseSpaces(from: rawDisplays)
    }

    private func parseSpaces(from displays: [[String: Any]]) -> [Space] {
        var result: [Space] = []
        var globalIndex = 1

        for display in displays {
            guard
                let rawSpaces = display["Spaces"] as? [[String: Any]],
                let currentSpace = display["Current Space"] as? [String: Any],
                let currentSpaceID = currentSpace["id64"] as? Int,
                let displayID = display["Display Identifier"] as? String
            else { continue }

            var desktopIndex = 1
            for rawSpace in rawSpaces {
                guard
                    let spaceID = rawSpace["id64"] as? Int,
                    let uuid = rawSpace["uuid"] as? String
                else { continue }

                let isFullscreen = (rawSpace["type"] as? Int ?? 0) != 0
                let isActive = spaceID == currentSpaceID

                result.append(Space(
                    id: uuid,
                    cgID: spaceID,
                    displayID: displayID,
                    index: globalIndex,
                    desktopIndex: isFullscreen ? nil : desktopIndex,
                    isActive: isActive,
                    isFullscreen: isFullscreen
                ))

                if !isFullscreen { desktopIndex += 1 }
                globalIndex += 1
            }
        }

        return result
    }
}
