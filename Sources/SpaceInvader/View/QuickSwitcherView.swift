import SwiftUI

struct QuickSwitcherView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedIndex: Int = 0
    var onDismiss: () -> Void

    private var spaces: [Space] { appState.spaces }

    private var activeSpace: Space? { spaces.first(where: { $0.isActive }) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)
            spaceList
            Divider().opacity(0.2)
            footer
        }
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.97))
        )
        .onAppear { selectedIndex = spaces.firstIndex(where: { $0.isActive }) ?? 0 }
        .onKeyPress(.escape)    { onDismiss(); return .handled }
        .onKeyPress(.upArrow)   { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.return)    { jump(); return .handled }
        .onKeyPress(phases: .down) { press in
            if let n = Int(press.characters), n >= 1, n <= 9 {
                if n <= spaces.count {
                    SpaceSwitcher.shared.switchToSpace(spaces[n - 1])
                    onDismiss()
                }
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var header: some View {
        if let active = activeSpace {
            HStack(spacing: 12) {
                spaceNumberBadge(active, size: 48, fontSize: 22, cornerRadius: 11)

                VStack(alignment: .leading, spacing: 3) {
                    Text("CURRENT SPACE")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                    Text(displayName(for: active))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var spaceList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(Array(spaces.enumerated()), id: \.element.id) { i, space in
                    SpaceRow(
                        space: space,
                        isSelected: i == selectedIndex,
                        appState: appState
                    ) {
                        SpaceSwitcher.shared.switchToSpace(space)
                        onDismiss()
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 420)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Button {
                NotificationCenter.default.post(name: .openPreferences, object: nil)
                onDismiss()
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Text("^↔ switch")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)

            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func displayName(for space: Space) -> String {
        let n = appState.name(for: space.id)
        return n.isEmpty ? space.displayLabel : n
    }

    private func spaceNumberBadge(_ space: Space, size: CGFloat, fontSize: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(appState.resolvedColor(for: space))
            Text("\(space.desktopIndex ?? space.index)")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    private func move(_ delta: Int) {
        guard !spaces.isEmpty else { return }
        selectedIndex = max(0, min(spaces.count - 1, selectedIndex + delta))
    }

    private func jump() {
        guard selectedIndex < spaces.count else { return }
        SpaceSwitcher.shared.switchToSpace(spaces[selectedIndex])
        onDismiss()
    }
}

private struct SpaceRow: View {
    let space: Space
    let isSelected: Bool
    let appState: AppState
    let action: () -> Void

    private var accent: Color { appState.resolvedColor(for: space) }

    private var spaceName: String {
        let n = appState.name(for: space.id)
        return n.isEmpty ? space.displayLabel : n
    }

    private var shortcutLabel: String {
        guard let idx = space.desktopIndex, idx <= 10 else { return "" }
        return "^\(idx == 10 ? 0 : idx)"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(accent)
                    Text("\(space.desktopIndex ?? space.index)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)

                Text(spaceName)
                    .font(.system(size: 14, weight: space.isActive ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !shortcutLabel.isEmpty {
                    Text(shortcutLabel)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(isSelected ? .white.opacity(0.6) : .secondary)
                }

                // Active indicator dot (always occupies space to prevent row width jumping)
                Circle()
                    .fill(space.isActive ? (isSelected ? Color.white : accent) : Color.clear)
                    .frame(width: 7, height: 7)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.85) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
