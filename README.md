# SpaceInvader

A macOS menu bar app for managing Mission Control spaces. Assign names, colors, and keyboard shortcuts to each space, switch between them instantly, and see colored overlays in Mission Control thumbnails.

## Features

- **Menu bar indicator** — shows the active space name and color at a glance
- **HUD** — floating space switcher that appears when switching; click any tile to jump directly
- **Quick Switcher** — keyboard-driven palette for jumping to any space by name or number
- **Space labels** — colored overlay strip visible in Mission Control thumbnails for each non-active space
- **Per-space customization** — name, color, emoji, and dedicated keyboard shortcut for each space
- **No Accessibility permission required** — space switching uses the private CGS API (`CGSManagedDisplaySetCurrentSpace`) rather than simulated keyboard input

## How it works

SpaceInvader reads the current space layout from the private `CGSCopyManagedDisplaySpaces` API, which returns the live list of spaces, their CGS IDs, and which one is active. This is polled via `NSWorkspace.activeSpaceDidChangeNotification`.

Space switching calls `CGSManagedDisplaySetCurrentSpace` directly on the Window Server connection — the same mechanism the system uses internally — which makes switches instant and requires no Accessibility permission.

The MC overlay panels are `NSPanel` windows (borderless, non-activating, ignoring mouse events) pinned to their respective spaces using `CGSAddWindowsToSpaces` / `CGSRemoveWindowsFromSpaces`. Each panel sits at window level 1, is always visible on its non-active space, and syncs visibility on every space change.

On macOS 26 (Tahoe), distributed notifications from the Dock for Mission Control open events (`com.apple.dock.willShowSpaces` and related) are no longer delivered to third-party processes. As a result, overlays cannot be shown exclusively during Mission Control — they remain always-visible on non-active spaces, which achieves the same effect in MC thumbnails.

## Lineage

SpaceInvader draws heavily on two earlier projects:

- **[SpaceJump](https://www.getspacejump.com)** — the primary inspiration for Mission Control label overlays, the CGS space-pinning approach, and the overall UX model of named/colored spaces
- **[Spaceman](https://github.com/Jaysce/Spaceman)** — open-source macOS menu bar spaces indicator; informed the menu bar rendering and space observation approach

## Requirements

- macOS 13 Ventura or later
- Mission Control must have "Displays have separate Spaces" enabled (System Settings → Desktop & Dock)

## Building

Open `SpaceInvader.xcodeproj` in Xcode and build the `SpaceInvader` scheme. No external package manager is required beyond Swift Package Manager (dependencies are resolved automatically).

## Dependencies

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — global hotkey registration
- [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin-Modern) — login item management
