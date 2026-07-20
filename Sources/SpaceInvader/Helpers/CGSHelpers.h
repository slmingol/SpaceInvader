#import <Foundation/Foundation.h>

/// Moves a window from one CGS space to another.
/// - windowID:      CGWindowID (32-bit), obtained after the window is on-screen.
/// - targetSpaceID: id64 of the destination space.
/// - sourceSpaceID: id64 of the space the window currently lives on
///                  (i.e. the active space at the time of creation).
/// Must be called on the main thread.
BOOL SIMoveWindowToSpace(int conn,
                         uint32_t windowID,
                         uint64_t targetSpaceID,
                         uint64_t sourceSpaceID);

/// Switches spaces by posting synthetic Dock horizontal-swipe gesture events.
/// Both indices are 0-based desktop-space indices.
/// Requires Accessibility permission (AXIsProcessTrusted).
/// Returns YES if the events were posted; does not guarantee the switch completed.
BOOL SISwitchSpaceByGesture(unsigned int targetIndex, unsigned int currentIndex);
