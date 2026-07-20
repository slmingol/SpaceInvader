import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var spaces: [Space] = []

    // Keyed by space UUID so settings survive reordering.
    @Published private(set) var spaceNames:  [String: String] = load("spaceNames")
    @Published private(set) var spaceColors: [String: String] = load("spaceColors")
    @Published private(set) var spaceEmojis: [String: String] = load("spaceEmojis")

    // MARK: Names

    func setName(_ name: String, for id: String) {
        spaceNames[id] = name.isEmpty ? nil : name
        save(spaceNames, key: "spaceNames")
        NotificationCenter.default.post(name: .spaceMetadataChanged, object: nil)
    }

    func name(for id: String) -> String { spaceNames[id] ?? "" }

    // MARK: Colors

    func setColor(_ color: Color?, for id: String) {
        spaceColors[id] = color?.hex
        save(spaceColors, key: "spaceColors")
        NotificationCenter.default.post(name: .spaceMetadataChanged, object: nil)
    }

    func color(for id: String) -> Color? {
        spaceColors[id].flatMap { Color(hex: $0) }
    }

    func resolvedColor(for space: Space) -> Color {
        if let hex = spaceColors[space.id], let color = Color(hex: hex) { return color }
        let palette = Color.spacePresets
        return palette[(space.index - 1) % palette.count]
    }

    // MARK: Emojis

    func setEmoji(_ emoji: String, for id: String) {
        spaceEmojis[id] = emoji.isEmpty ? nil : String(emoji.prefix(2))
        save(spaceEmojis, key: "spaceEmojis")
        NotificationCenter.default.post(name: .spaceMetadataChanged, object: nil)
    }

    func emoji(for id: String) -> String { spaceEmojis[id] ?? "" }

    // MARK: Palette

    func applyPalette(_ palette: SpacePalette) {
        let desktopSpaces = spaces.filter { !$0.isFullscreen }
        for (i, space) in desktopSpaces.enumerated() {
            spaceColors[space.id] = palette.colors[i % palette.colors.count].hex
        }
        save(spaceColors, key: "spaceColors")
        NotificationCenter.default.post(name: .spaceMetadataChanged, object: nil)
    }

    // MARK: Label shown in HUD

    func chipLabel(for space: Space) -> String {
        let e = emoji(for: space.id)
        if !e.isEmpty { return e }
        return space.desktopIndex.map { "\($0)" } ?? "F"
    }
}

private func load<V>(_ key: String) -> [String: V] {
    (UserDefaults.standard.dictionary(forKey: key) as? [String: V]) ?? [:]
}

private func save<V>(_ dict: [String: V?], key: String) {
    let compact = dict.compactMapValues { $0 }
    UserDefaults.standard.set(compact, forKey: key)
}
