import SwiftUI

// Custom dropdown menu shown when the status bar item is clicked.
// Replaces the standard NSMenu with a dark panel matching the SpaceJump-style design.
struct StatusMenuView: View {
    let spaces: [Space]
    let appState: AppState
    var onSpaceSelect: (Space) -> Void
    var onPreferences: () -> Void
    var onQuit: () -> Void

    private var activeSpace: Space? { spaces.first(where: { $0.isActive }) }
    private var desktopSpaces: [Space] { spaces.filter { !$0.isFullscreen } }

    var body: some View {
        VStack(spacing: 0) {
            header
            menuDivider
            spaceList
            menuDivider
            toolbar
        }
        .frame(width: 300)
        .background(Color(NSColor(white: 0.12, alpha: 1)))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            if let active = activeSpace {
                SpaceMenuBadge(
                    index: active.desktopIndex ?? active.index,
                    color: appState.resolvedColor(for: active),
                    size: 34
                )
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("CURRENT SPACE")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.8)
                Text(activeSpaceName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var spaceList: some View {
        VStack(spacing: 0) {
            ForEach(desktopSpaces) { space in
                StatusMenuSpaceRow(space: space, appState: appState) {
                    onSpaceSelect(space)
                }
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Button(action: onPreferences) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("^↔")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)

            Spacer()

            Button(action: onQuit) {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(white: 1, opacity: 0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var menuDivider: some View {
        Rectangle()
            .fill(Color(white: 1, opacity: 0.08))
            .frame(height: 1)
    }

    private var activeSpaceName: String {
        guard let active = activeSpace else { return "—" }
        let n = appState.name(for: active.id)
        return n.isEmpty ? active.displayLabel : n
    }
}

// MARK: - Row

private struct StatusMenuSpaceRow: View {
    let space: Space
    let appState: AppState
    let onSelect: () -> Void

    @State private var isHovered = false

    private var idx: Int { space.desktopIndex ?? space.index }
    private var displayName: String {
        let n = appState.name(for: space.id)
        return n.isEmpty ? space.displayLabel : n
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                SpaceMenuBadge(
                    index: idx,
                    color: appState.resolvedColor(for: space),
                    size: 28
                )

                Text(displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                if idx <= 9 {
                    Text("^\(idx)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                if space.isActive {
                    Circle()
                        .fill(appState.resolvedColor(for: space))
                        .frame(width: 6, height: 6)
                } else {
                    // Reserve width so names stay left-aligned
                    Color.clear.frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                space.isActive
                    ? Color(white: 1, opacity: 0.08)
                    : (isHovered ? Color(white: 1, opacity: 0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Badge

struct SpaceMenuBadge: View {
    let index: Int
    let color: Color
    let size: CGFloat

    var body: some View {
        Text("\(index)")
            .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(color)
            )
    }
}
