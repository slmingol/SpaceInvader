#import "CGSHelpers.h"
#import <CoreGraphics/CoreGraphics.h>
#import <ApplicationServices/ApplicationServices.h>
#import <float.h>

// Private CGEvent field IDs for Dock swipe gesture events.
// Verified against InstantSpaceSwitcher / yabai tracing on macOS 12+.
static const CGEventField kSIEventTypeField            = (CGEventField)55;
static const CGEventField kSIEventGestureHIDType       = (CGEventField)110;
static const CGEventField kSIEventGestureSwipeMotion   = (CGEventField)123;
static const CGEventField kSIEventGestureSwipeProgress = (CGEventField)124;
static const CGEventField kSIEventGestureVelocityX     = (CGEventField)129;
static const CGEventField kSIEventGestureVelocityY     = (CGEventField)130;
static const CGEventField kSIEventGesturePhase         = (CGEventField)132;

static const int32_t  kSIDockControlEventType    = 30;  // kCGSEventDockControl
static const uint32_t kSIHIDTypeDockSwipe        = 23;  // kIOHIDEventTypeDockSwipe
static const uint16_t kSIGestureMotionHorizontal = 1;
static const uint8_t  kSIGesturePhaseBegan       = 1;
static const uint8_t  kSIGesturePhaseChanged     = 2;
static const uint8_t  kSIGesturePhaseEnded       = 4;

static BOOL postDockSwipePhase(uint8_t phase, BOOL goRight, double velocity) {
    double vel      = goRight ? velocity : -velocity;
    double progress = goRight ? (double)FLT_TRUE_MIN : -(double)FLT_TRUE_MIN;

    // HIDSystemState source makes the event appear to originate from hardware.
    // NULL source creates a private-state event the Dock may filter.
    CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef ev = CGEventCreate(src);
    if (src) CFRelease(src);
    if (!ev) return NO;

    CGEventSetIntegerValueField(ev, kSIEventTypeField,            kSIDockControlEventType);
    CGEventSetIntegerValueField(ev, kSIEventGestureHIDType,       kSIHIDTypeDockSwipe);
    CGEventSetIntegerValueField(ev, kSIEventGesturePhase,         phase);
    CGEventSetDoubleValueField(ev,  kSIEventGestureSwipeProgress, progress);
    CGEventSetIntegerValueField(ev, kSIEventGestureSwipeMotion,   kSIGestureMotionHorizontal);
    CGEventSetDoubleValueField(ev,  kSIEventGestureVelocityX,     vel);
    CGEventSetDoubleValueField(ev,  kSIEventGestureVelocityY,     vel);

    CGEventPost(kCGSessionEventTap, ev);
    CFRelease(ev);
    return YES;
}

BOOL SISwitchSpaceByGesture(unsigned int targetIndex, unsigned int currentIndex) {
    if (targetIndex == currentIndex) return YES;

    BOOL goRight = (targetIndex > currentIndex);
    unsigned int steps = goRight ? (targetIndex - currentIndex) : (currentIndex - targetIndex);
    double velocity = 15000.0;

    for (unsigned int i = 0; i < steps; i++) {
        if (!postDockSwipePhase(kSIGesturePhaseBegan,   goRight, velocity)) return NO;
        if (!postDockSwipePhase(kSIGesturePhaseChanged, goRight, velocity)) return NO;
        if (!postDockSwipePhase(kSIGesturePhaseEnded,   goRight, velocity)) return NO;
    }
    return YES;
}

// Contract (verified via yabai/Amethyst usage on macOS 15):
//   windows — CFArray of CFNumber(kCFNumberSInt32Type)  CGWindowID
//   spaces  — CFArray of CFNumber(kCFNumberSInt64Type)  id64
// Passing 64-bit Swift Ints in the windows array writes garbage into the
// 32-bit CGWindowID field the server reads → async IPC abort.
extern int CGSAddWindowsToSpaces(int conn, CFArrayRef windows, CFArrayRef spaces);
extern int CGSRemoveWindowsFromSpaces(int conn, CFArrayRef windows, CFArrayRef spaces);

static CFArrayRef makeWindowArray(uint32_t windowID) {
    CFNumberRef n = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &windowID);
    if (!n) return NULL;
    CFArrayRef a = CFArrayCreate(kCFAllocatorDefault, (const void **)&n, 1, &kCFTypeArrayCallBacks);
    CFRelease(n);
    return a;
}

static CFArrayRef makeSpaceArray(uint64_t spaceID) {
    int64_t sid = (int64_t)spaceID;
    CFNumberRef n = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &sid);
    if (!n) return NULL;
    CFArrayRef a = CFArrayCreate(kCFAllocatorDefault, (const void **)&n, 1, &kCFTypeArrayCallBacks);
    CFRelease(n);
    return a;
}

BOOL SIMoveWindowToSpace(int conn,
                         uint32_t windowID,
                         uint64_t targetSpaceID,
                         uint64_t sourceSpaceID) {
    CFArrayRef wins = makeWindowArray(windowID);
    if (!wins) return NO;

    CFArrayRef tSpcs = makeSpaceArray(targetSpaceID);
    if (!tSpcs) { CFRelease(wins); return NO; }

    CFArrayRef sSpcs = makeSpaceArray(sourceSpaceID);
    if (!sSpcs) { CFRelease(tSpcs); CFRelease(wins); return NO; }

    @try {
        CGSAddWindowsToSpaces(conn, wins, tSpcs);
        CGSRemoveWindowsFromSpaces(conn, wins, sSpcs);
    } @catch (NSException *e) {
        NSLog(@"[SpaceInvader] SIMoveWindowToSpace exception: %@", e);
        CFRelease(sSpcs); CFRelease(tSpcs); CFRelease(wins);
        return NO;
    }

    CFRelease(sSpcs);
    CFRelease(tSpcs);
    CFRelease(wins);
    return YES;
}
