import SwiftUI

struct SpaceHUDView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            // Top spacer fills the notch/menu-bar area above the tiles.
            // The clip view (in SpaceHUDController) masks this to the current
            // panel size; the dark background extends to fill whatever is revealed.
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(displayGroups, id: \.id) { group in
                    if group.id != displayGroups.first?.id {
                        Rectangle()
                            .fill(.white.opacity(0.12))
                            .frame(width: 1, height: 54)
                    }
                    ForEach(group.spaces) { space in
                        SpaceTile(space: space).environmentObject(appState)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contextMenu {
                Button("Preferences...") {
                    NotificationCenter.default.post(name: .openPreferences, object: nil)
                }
                Divider()
                Button("Quit SpaceInvader") { NSApp.terminate(nil) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Single dark fill covers the entire frame — the spacer above and the
        // tile area below share one seamless background.  Rounded corners come
        // from the clip view's CALayer so they track the animation frame.
        .background(Color.black.opacity(0.78))
    }

    private var displayGroups: [DisplayGroup] {
        var groups: [DisplayGroup] = []
        var seen: [String: Int] = [:]
        for space in appState.spaces {
            if let i = seen[space.displayID] {
                groups[i].spaces.append(space)
            } else {
                seen[space.displayID] = groups.count
                groups.append(DisplayGroup(id: space.displayID, spaces: [space]))
            }
        }
        return groups
    }
}

private struct DisplayGroup { let id: String; var spaces: [Space] }

private struct SpaceTile: View {
    let space: Space
    @EnvironmentObject private var appState: AppState

    private var accent: Color { appState.resolvedColor(for: space) }
    private var chipLabel: String { appState.chipLabel(for: space) }
    private var spaceName: String {
        let n = appState.name(for: space.id)
        return n.isEmpty ? space.displayLabel : n
    }

    var body: some View {
        Button {
            // Space switching is handled by SpaceHUDController's mouseDownMonitor,
            // which intercepts the click before it reaches SwiftUI. This action
            // fires only when the monitor doesn't consume the event (e.g. no hit).
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(accent.opacity(space.isActive ? 1 : 0.72))
                    Text(chipLabel)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 50, height: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(.white, lineWidth: 2.5)
                        .opacity(space.isActive ? 1 : 0)
                )

                Text(spaceName)
                    .font(.system(size: 12, weight: .medium))
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    .foregroundStyle(.white.opacity(space.isActive ? 1 : 0.7))
                    .lineLimit(1)
                    .frame(width: 54)
            }
        }
        .buttonStyle(.plain)
    }
}

extension Notification.Name {
    static let openPreferences = Notification.Name("openPreferences")
    static let showQuickSwitcher = Notification.Name("showQuickSwitcher")
}
