import SwiftUI

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6 else { return nil }
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            red:   Double((int >> 16) & 0xFF) / 255,
            green: Double((int >>  8) & 0xFF) / 255,
            blue:  Double( int        & 0xFF) / 255
        )
    }

    var hex: String {
        let r = Int((NSColor(self).redComponent   * 255).rounded())
        let g = Int((NSColor(self).greenComponent * 255).rounded())
        let b = Int((NSColor(self).blueComponent  * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

extension Color {
    // 28 colors — 4 rows × 7 columns in the individual swatch picker.
    static let spacePresets: [Color] = [
        // Blues
        Color(hex: "0077B6")!, Color(hex: "0096C7")!, Color(hex: "48CAE4")!,
        Color(hex: "89B4F8")!, Color(hex: "7DCEF5")!, Color(hex: "ADE8F4")!,
        Color(hex: "5B8DEF")!,
        // Greens
        Color(hex: "2DC653")!, Color(hex: "52B788")!, Color(hex: "72D9A0")!,
        Color(hex: "95D5B2")!, Color(hex: "B5E48C")!, Color(hex: "D4E09B")!,
        Color(hex: "C7F2A4")!,
        // Yellows / Oranges
        Color(hex: "FFE066")!, Color(hex: "FFD166")!, Color(hex: "FFAB40")!,
        Color(hex: "FFB07A")!, Color(hex: "FF8C42")!, Color(hex: "F4845F")!,
        Color(hex: "E76F51")!,
        // Pinks / Reds / Purples / Slate
        Color(hex: "FF9494")!, Color(hex: "FF6B6B")!, Color(hex: "FF9EC0")!,
        Color(hex: "F72585")!, Color(hex: "BAA7F5")!, Color(hex: "7B5EA7")!,
        Color(hex: "A0AABB")!,
    ]
}

// MARK: - Palettes

struct SpacePalette: Identifiable {
    let id: String
    let name: String
    let colors: [Color]

    var preview: [Color] { Array(colors.prefix(5)) }
}

extension SpacePalette {
    static let all: [SpacePalette] = [pastel, vibrant, neon, earth, ocean, sunset, monochrome]

    static let pastel = SpacePalette(id: "pastel", name: "Pastel", colors: [
        Color(hex: "89B4F8")!, Color(hex: "72D9A0")!, Color(hex: "FFB07A")!,
        Color(hex: "FF9494")!, Color(hex: "BAA7F5")!, Color(hex: "FF9EC0")!,
        Color(hex: "7DCEF5")!, Color(hex: "FFE066")!, Color(hex: "A0AABB")!,
    ])

    static let vibrant = SpacePalette(id: "vibrant", name: "Vibrant", colors: [
        Color(hex: "5B8DEF")!, Color(hex: "2DC653")!, Color(hex: "FFAB40")!,
        Color(hex: "FF6B6B")!, Color(hex: "F72585")!, Color(hex: "7B5EA7")!,
        Color(hex: "00B4D8")!, Color(hex: "FFD166")!, Color(hex: "E76F51")!,
    ])

    static let neon = SpacePalette(id: "neon", name: "Neon", colors: [
        Color(hex: "00F5FF")!, Color(hex: "00FF88")!, Color(hex: "FFD700")!,
        Color(hex: "FF6EC7")!, Color(hex: "FF3366")!, Color(hex: "4D9FFF")!,
        Color(hex: "FF6600")!, Color(hex: "ADFF2F")!, Color(hex: "FF00AA")!,
    ])

    static let earth = SpacePalette(id: "earth", name: "Earth", colors: [
        Color(hex: "8B5E3C")!, Color(hex: "C17F54")!, Color(hex: "D4A574")!,
        Color(hex: "8FA67B")!, Color(hex: "6B8C6B")!, Color(hex: "A5896B")!,
        Color(hex: "7A6345")!, Color(hex: "5C7A5C")!, Color(hex: "B8956A")!,
    ])

    static let ocean = SpacePalette(id: "ocean", name: "Ocean", colors: [
        Color(hex: "023E8A")!, Color(hex: "0077B6")!, Color(hex: "0096C7")!,
        Color(hex: "00B4D8")!, Color(hex: "48CAE4")!, Color(hex: "5B8DEF")!,
        Color(hex: "90E0EF")!, Color(hex: "2BC0E4")!, Color(hex: "ADE8F4")!,
    ])

    static let sunset = SpacePalette(id: "sunset", name: "Sunset", colors: [
        Color(hex: "FF6B6B")!, Color(hex: "FF8E72")!, Color(hex: "FFB347")!,
        Color(hex: "FFD700")!, Color(hex: "FF69B4")!, Color(hex: "F4845F")!,
        Color(hex: "E76F51")!, Color(hex: "FF9EC0")!, Color(hex: "FF6600")!,
    ])

    static let monochrome = SpacePalette(id: "monochrome", name: "Mono", colors: [
        Color(hex: "2D3142")!, Color(hex: "4F5D75")!, Color(hex: "7A8BA6")!,
        Color(hex: "9EAFC2")!, Color(hex: "BCC9D8")!, Color(hex: "5C6C7C")!,
        Color(hex: "3D4F61")!, Color(hex: "6D7F90")!, Color(hex: "8E9EAD")!,
    ])
}
