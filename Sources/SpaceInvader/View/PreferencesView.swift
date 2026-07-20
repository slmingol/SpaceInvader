import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin

// MARK: - Root

struct PreferencesView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var timeTracker: TimeTracker
    @State private var selection: NavItem = .spaces

    enum NavItem: String, CaseIterable, Hashable {
        case spaces       = "Spaces"
        case timeTracking = "Time Tracking"
        case settings     = "Settings"
        case about        = "About"

        var systemImage: String {
            switch self {
            case .spaces:       return "rectangle.3.group"
            case .timeTracking: return "clock"
            case .settings:     return "gear"
            case .about:        return "info.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebarColumn
            Divider()
            contentColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 680, height: 700)
    }

    // MARK: Sidebar

    private var sidebarColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            Divider()
            List(NavItem.allCases, id: \.self, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.systemImage)
                    .font(.system(size: 13))
                    .tag(item)
            }
            .listStyle(.sidebar)
        }
        .frame(width: 170)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 36, height: 36)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("SpaceInvader")
                    .font(.system(size: 13, weight: .semibold))
                Text("Settings")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: Content

    @ViewBuilder
    private var contentColumn: some View {
        if selection == .spaces {
            SpacesPage()
        } else if selection == .timeTracking {
            TimeTrackingPage()
        } else if selection == .settings {
            GeneralSettingsPage()
        } else {
            AboutPage()
        }
    }
}

// MARK: - Page header

private struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }
}

// MARK: - Spaces page

private struct SpacesPage: View {
    @EnvironmentObject private var appState: AppState

    private var desktopSpaces: [Space] {
        appState.spaces.filter { !$0.isFullscreen }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Spaces", subtitle: "Names, colors & icons")
            Divider()
            PalettePickerBar()
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    if desktopSpaces.isEmpty {
                        Text("No spaces detected")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(40)
                    } else {
                        ForEach(Array(desktopSpaces.enumerated()), id: \.element.id) { i, space in
                            SpaceSettingsRow(space: space)
                            if i < desktopSpaces.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }
            Divider()
            HStack {
                Button {
                    for space in appState.spaces {
                        appState.setName("", for: space.id)
                    }
                } label: {
                    Label("Reset Names", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Palette picker

private struct PalettePickerBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Apply palette to all spaces")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(SpacePalette.all) { palette in
                    PaletteCard(palette: palette) {
                        appState.applyPalette(palette)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

private struct PaletteCard: View {
    let palette: SpacePalette
    let onApply: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onApply) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 2) {
                    ForEach(Array(palette.preview.enumerated()), id: \.offset) { _, color in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(color)
                            .frame(width: 9, height: 9)
                    }
                }
                Text(palette.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered
                          ? Color(NSColor.controlBackgroundColor)
                          : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Space row

private struct SpaceSettingsRow: View {
    let space: Space
    @EnvironmentObject private var appState: AppState
    @State private var name: String = ""

    private var idx: Int { space.desktopIndex ?? space.index }

    var body: some View {
        HStack(spacing: 12) {
            SpaceMenuBadge(
                index: idx,
                color: appState.resolvedColor(for: space),
                size: 30
            )

            EmojiPickerButton(
                emoji: Binding(
                    get: { appState.emoji(for: space.id) },
                    set: { appState.setEmoji($0, for: space.id) }
                )
            )

            TextField("Space \(idx)", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 130)
                .onChange(of: name) { _, new in appState.setName(new, for: space.id) }

            ColorSwatchPicker(
                autoColor: appState.resolvedColor(for: space),
                selectedColor: Binding(
                    get: { appState.color(for: space.id) },
                    set: { appState.setColor($0, for: space.id) }
                )
            )

            if let shortcutName = KeyboardShortcuts.Name.jumpToSpace(space.index) {
                KeyboardShortcuts.Recorder("", name: shortcutName)
                    .frame(width: 110)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .onAppear {
            name = appState.name(for: space.id)
        }
    }
}

// MARK: - Emoji picker

private let emojiCategories: [(String, [String])] = [
    ("Work",     ["💼", "💻", "🖥", "📱", "⌨️", "🖱", "📝", "📊", "📈", "📉"]),
    ("Focus",    ["🎯", "🚀", "🏆", "⭐", "🌟", "🔥", "⚡", "💡", "✅", "🔖"]),
    ("Objects",  ["🔧", "⚙️", "🔑", "🗝", "📚", "🗂", "📌", "📎", "🗺", "🔍"]),
    ("Creative", ["🎨", "🎸", "🎮", "🎵", "🎬", "🎤", "🎭", "🎲", "✏️", "📐"]),
    ("Nature",   ["🌿", "🌸", "🌊", "🌙", "🌈", "🍀", "🌺", "🦋", "🌴", "⛰"]),
    ("Animals",  ["🐶", "🐱", "🦊", "🦁", "🐉", "🦅", "🐺", "🦌", "🐘", "🦒"]),
    ("Hearts",   ["❤️", "🧡", "💛", "💚", "💙", "💜", "🤍", "🖤", "♾️", "🔮"]),
]

private struct EmojiPickerButton: View {
    @Binding var emoji: String
    @State private var showPicker = false

    var body: some View {
        Button { showPicker = true } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .frame(width: 36, height: 26)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
                if emoji.isEmpty {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Text(emoji)
                        .font(.system(size: 15))
                }
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            EmojiGrid(selected: $emoji, isPresented: $showPicker)
        }
    }
}

private struct EmojiGrid: View {
    @Binding var selected: String
    @Binding var isPresented: Bool
    @State private var typed: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Type-in field — also accepts emoji via Ctrl+Cmd+Space system picker
            HStack(spacing: 6) {
                TextField("Or type an emoji…", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 18))
                    .frame(maxWidth: .infinity)
                    .onChange(of: typed) { _, new in
                        guard let first = new.first else { return }
                        let cluster = String(first)
                        let isEmoji = cluster.unicodeScalars.contains {
                            $0.properties.isEmoji && $0.value > 127
                        }
                        if isEmoji {
                            selected = cluster
                            isPresented = false
                        } else if new.count > 4 {
                            typed = ""
                        }
                    }
                if !typed.isEmpty {
                    Button { typed = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            ForEach(emojiCategories, id: \.0) { name, emojis in
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(34), spacing: 2), count: 10),
                        spacing: 2
                    ) {
                        ForEach(emojis, id: \.self) { e in
                            Button {
                                selected = e
                                isPresented = false
                            } label: {
                                Text(e)
                                    .font(.system(size: 20))
                                    .frame(width: 34, height: 34)
                                    .background(
                                        selected == e
                                            ? Color.accentColor.opacity(0.25)
                                            : Color.clear
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Divider()

            Button("Clear") {
                selected = ""
                isPresented = false
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(12)
        .frame(width: 380)
    }
}

// MARK: - Color swatch picker

private struct ColorSwatchPicker: View {
    let autoColor: Color
    @Binding var selectedColor: Color?
    @State private var showPopover = false

    var body: some View {
        Button { showPopover = true } label: {
            Circle()
                .fill(selectedColor ?? autoColor)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Color")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("Reset") {
                        selectedColor = nil
                        showPopover = false
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(28), spacing: 5), count: 7),
                    spacing: 5
                ) {
                    ForEach(Array(Color.spacePresets.enumerated()), id: \.offset) { _, color in
                        Button {
                            selectedColor = color
                            showPopover = false
                        } label: {
                            ZStack {
                                Circle().fill(color).frame(width: 24, height: 24)
                                if selectedColor?.hex == color.hex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(10)
            .frame(width: 240)
        }
    }
}

// MARK: - Time Tracking page

private struct TimeTrackingPage: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var timeTracker: TimeTracker
    @State private var showWeek = false

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var weekAgo: Date { Date().addingTimeInterval(-7 * 24 * 3600) }
    private var desktopSpaces: [Space] { appState.spaces.filter { !$0.isFullscreen } }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Time Tracking", subtitle: "Time spent per space")
            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Picker("", selection: $showWeek) {
                    Text("Today").tag(false)
                    Text("7 Days").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                let _ = timeTracker.lastRefresh
                let since = showWeek ? weekAgo : today
                let totals = timeTracker.spaceTotals(since: since, spaceIDs: desktopSpaces.map { $0.id })
                let maxSecs = totals.first?.seconds ?? 1

                if totals.isEmpty {
                    Text("No data yet — switch spaces to start tracking")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(totals, id: \.spaceID) { entry in
                                if let space = desktopSpaces.first(where: { $0.id == entry.spaceID }) {
                                    SpaceTimeRow(
                                        space: space,
                                        seconds: entry.seconds,
                                        maxSeconds: maxSecs,
                                        appState: appState
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SpaceTimeRow: View {
    let space: Space
    let seconds: TimeInterval
    let maxSeconds: TimeInterval
    let appState: AppState

    private var displayName: String {
        let n = appState.name(for: space.id)
        return n.isEmpty ? space.displayLabel : n
    }

    private var timeString: String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                SpaceMenuBadge(
                    index: space.desktopIndex ?? space.index,
                    color: appState.resolvedColor(for: space),
                    size: 22
                )
                Text(displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(timeString)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(NSColor.separatorColor).opacity(0.25))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(appState.resolvedColor(for: space).opacity(0.75))
                        .frame(width: geo.size.width * CGFloat(seconds / maxSeconds))
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - General Settings

private struct GeneralSettingsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Settings", subtitle: "General preferences")
            Divider()
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    LaunchAtLogin.Toggle()
                    Divider()
                    HStack {
                        Text("Quick Switcher")
                            .font(.subheadline)
                        Spacer()
                        KeyboardShortcuts.Recorder("", name: .quickSwitcher)
                    }
                }
                .padding(.vertical, 4)
            } label: {
                Label("General", systemImage: "gear")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - About

private struct AboutPage: View {
    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    }
    private var build: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "About", subtitle: "SpaceInvader for macOS")
            Divider()
            VStack(alignment: .leading, spacing: 20) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 72, height: 72)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("SpaceInvader")
                        .font(.system(size: 18, weight: .bold))
                    Text("Version \(version) (\(build))")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Built on the shoulders of giants:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Link("SpaceJump — getspacejump.com",
                         destination: URL(string: "https://www.getspacejump.com")!)
                        .font(.system(size: 13))
                    Link("Spaceman — github.com/Jaysce/Spaceman",
                         destination: URL(string: "https://github.com/Jaysce/Spaceman")!)
                        .font(.system(size: 13))
                }
            }
            .padding(20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
