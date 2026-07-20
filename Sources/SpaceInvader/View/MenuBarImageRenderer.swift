import AppKit

enum MenuBarImageRenderer {
    private static let spaceWidth: CGFloat = 8
    private static let spaceHeight: CGFloat = 12
    private static let gap: CGFloat = 2
    private static let displayGap: CGFloat = 4
    private static let hPad: CGFloat = 1
    private static let vPad: CGFloat = 2

    static func render(spaces: [Space]) -> NSImage {
        let displayIDs = uniqueDisplayIDs(from: spaces)
        let extraGap = CGFloat(max(0, displayIDs.count - 1)) * displayGap
        let count = CGFloat(spaces.count)
        let width = count * spaceWidth + max(0, count - 1) * gap + extraGap + hPad * 2

        let size = NSSize(width: max(width, spaceWidth), height: 16)
        let image = NSImage(size: size)
        image.lockFocus()

        var x = hPad
        var lastDisplayID: String?

        for space in spaces {
            if let last = lastDisplayID, last != space.displayID {
                x += displayGap
            }
            lastDisplayID = space.displayID

            let rect = NSRect(x: x, y: vPad, width: spaceWidth, height: spaceHeight)
            drawSpace(space, in: rect)
            x += spaceWidth + gap
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func drawSpace(_ space: Space, in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        (space.isActive ? NSColor.labelColor : NSColor.tertiaryLabelColor).setFill()
        path.fill()
    }

    // Classic crab-type Space Invader sprite (11×8 pixels).
    static func spaceInvaderIcon() -> NSImage {
        let sprite: [[UInt8]] = [
            [0,0,1,0,0,0,0,0,1,0,0],
            [0,0,0,1,0,0,0,1,0,0,0],
            [0,0,1,1,1,1,1,1,1,0,0],
            [0,1,1,0,1,1,1,0,1,1,0],
            [1,1,1,1,1,1,1,1,1,1,1],
            [1,0,1,1,1,1,1,1,1,0,1],
            [1,0,1,0,0,0,0,0,1,0,1],
            [0,0,0,1,1,0,1,1,0,0,0],
        ]
        let px: CGFloat = 1.5
        let cols = CGFloat(sprite[0].count)
        let rows = CGFloat(sprite.count)
        let image = NSImage(size: NSSize(width: cols * px, height: rows * px))
        image.lockFocus()
        NSColor.black.setFill()
        for (r, row) in sprite.enumerated() {
            for (c, on) in row.enumerated() where on == 1 {
                NSRect(x: CGFloat(c) * px,
                       y: (rows - CGFloat(r) - 1) * px,
                       width: px, height: px).fill()
            }
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // Small square badge used for individual NSMenu space items.
    static func spaceMenuBadge(index: Int, color: NSColor) -> NSImage {
        let sz: CGFloat = 18
        let image = NSImage(size: NSSize(width: sz, height: sz), flipped: false) { _ in
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: sz - 2, height: sz - 2),
                         xRadius: 5, yRadius: 5).fill()
            let str = "\(index)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let s = str.size(withAttributes: attrs)
            str.draw(at: NSPoint(x: (sz - s.width) / 2, y: (sz - s.height) / 2), withAttributes: attrs)
            return true
        }
        image.isTemplate = false
        return image
    }

    // Renders the "1 Main" style badge shown in the menu bar.
    // Uses a colored rounded-rect for the number and label-color text for the name
    // so it adapts to both light and dark menu bars.
    static func activeSpaceBadge(index: Int, name: String, color: NSColor) -> NSImage {
        let numStr = "\(index)"
        let displayName = name.isEmpty ? "Space \(index)" : name

        let h: CGFloat = 16
        let badgeW: CGFloat = 18
        let gap: CGFloat = 4
        let hPad: CGFloat = 2

        let numFont = NSFont.systemFont(ofSize: 10, weight: .bold)
        let numAttrs: [NSAttributedString.Key: Any] = [.font: numFont, .foregroundColor: NSColor.white]

        let nameFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let nameAttrs: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: NSColor.labelColor]
        let nameSize = (displayName as NSString).size(withAttributes: nameAttrs)

        let totalW = hPad + badgeW + gap + nameSize.width + hPad
        let size = NSSize(width: max(totalW, badgeW + 2 * hPad), height: h)

        let image = NSImage(size: size, flipped: false) { _ in
            let badgeRect = NSRect(x: hPad, y: (h - badgeW) / 2, width: badgeW, height: badgeW)
            color.withSystemEffect(.none).setFill()
            NSBezierPath(roundedRect: badgeRect, xRadius: 5, yRadius: 5).fill()

            let numSize = (numStr as NSString).size(withAttributes: numAttrs)
            let numPoint = NSPoint(x: hPad + (badgeW - numSize.width) / 2,
                                   y: (h - numSize.height) / 2)
            (numStr as NSString).draw(at: numPoint, withAttributes: numAttrs)

            let namePoint = NSPoint(x: hPad + badgeW + gap, y: (h - nameSize.height) / 2)
            (displayName as NSString).draw(at: namePoint, withAttributes: nameAttrs)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func uniqueDisplayIDs(from spaces: [Space]) -> [String] {
        var seen = Set<String>()
        return spaces.compactMap { space in
            guard !seen.contains(space.displayID) else { return nil }
            seen.insert(space.displayID)
            return space.displayID
        }
    }
}
