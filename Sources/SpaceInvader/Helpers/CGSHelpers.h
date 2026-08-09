#import <Foundation/Foundation.h>

/// YES once the WindowServer has registered this window against at least one
/// space. A window is NOT registered the instant -orderFront: returns; the
/// assignment is published asynchronously and only lands after the main runloop
/// turns. Pinning before this returns YES is a silent no-op — the server-side
/// registration that follows overwrites the pin with the then-current space.
/// Measured latency on macOS 26.6: 6-26 ms of runloop time.
BOOL SIWindowIsSpaceRegistered(int conn, uint32_t windowID);

/// YES if `windowID` is on exactly one space and that space is `spaceID`.
BOOL SIWindowIsPinnedToSpace(int conn, uint32_t windowID, uint64_t spaceID);

/// Pins a window to exactly one space, removing it from every other space in a
/// single WindowServer round trip. Prefer this over add-then-remove: the paired
/// calls need a source space ID, and if the user changes spaces between the
/// window being created and the pin being applied, the stale source makes the
/// remove a no-op and the window is left on two spaces at once.
/// Caller must have confirmed SIWindowIsSpaceRegistered first, and must verify
/// the result on a later runloop pass — see SIWindowIsPinnedToSpace.
/// Must be called on the main thread.
BOOL SIPinWindowToSpace(int conn, uint32_t windowID, uint64_t spaceID);

/// Space id64s this window currently belongs to. Returns an empty array while
/// the window is still unregistered. Diagnostics only.
NSArray<NSNumber *> *SICopySpacesForWindow(int conn, uint32_t windowID);

/// Moves a window from one CGS space to another.
/// - windowID:      CGWindowID (32-bit), obtained after the window is on-screen.
/// - targetSpaceID: id64 of the destination space.
/// - sourceSpaceID: id64 of the space the window currently lives on
///                  (i.e. the active space at the time of creation).
/// Must be called on the main thread.
/// Deprecated: not race-free. Use SIPinWindowToSpace.
BOOL SIMoveWindowToSpace(int conn,
                         uint32_t windowID,
                         uint64_t targetSpaceID,
                         uint64_t sourceSpaceID);

/// Switches spaces by posting synthetic Dock horizontal-swipe gesture events.
/// Both indices are 0-based desktop-space indices.
/// Requires Accessibility permission (AXIsProcessTrusted).
/// Returns YES if the events were posted; does not guarantee the switch completed.
BOOL SISwitchSpaceByGesture(unsigned int targetIndex, unsigned int currentIndex);
