#import "SpaceInvaderNSApplication.h"
#import <objc/runtime.h>

// When CGSAddWindowsToSpaces assigns a window to a space, the window server sends
// an async Mach IPC notification back to AppKit. AppKit processes it in _DPSNextEvent
// and throws an ObjC exception when its internal model is out of sync with CGS.
// The throw site is deep inside AppKit/CoreGraphics — no SpaceInvader frame in the stack.
//
// AppKit's default exception path: NSRunLoop catch → reportException: → _crashOnException: → brk #0x1
// We intercept at every point in that chain and suppress exceptions whose call stack
// contains no SpaceInvader frames (= background IPC notification, not a real bug).
// Exceptions with SpaceInvader frames in the stack indicate genuine bugs and abort normally.

static BOOL isBackgroundIPCException(NSException *exception) {
    NSArray<NSString *> *stack = exception.callStackSymbols;
    for (NSString *sym in stack) {
        if ([sym containsString:@"SpaceInvader"]) return NO;
    }
    return YES;  // No user code in stack → safe to drop
}

@interface NSApplication (PrivateCrash)
- (void)_crashOnException:(NSException *)exception;
+ (void)_crashOnException:(NSException *)exception;
@end

@implementation SpaceInvaderNSApplication

// Called by NSRunLoop before _crashOnException:
- (void)reportException:(NSException *)exception {
    if (isBackgroundIPCException(exception)) {
        NSLog(@"[SpaceInvader] reportException: suppressed — %@: %@",
              exception.name, exception.reason);
        return;
    }
    [super reportException:exception];
}

// Class-method variant (what Xcode shows as +[NSApplication _crashOnException:])
+ (void)_crashOnException:(NSException *)exception {
    if (isBackgroundIPCException(exception)) {
        NSLog(@"[SpaceInvader] +_crashOnException: suppressed — %@: %@",
              exception.name, exception.reason);
        return;
    }
    NSLog(@"[SpaceInvader] +_crashOnException: aborting on user-code exception — %@: %@",
          exception.name, exception.reason);
    abort();
}

// Instance-method variant (fallback)
- (void)_crashOnException:(NSException *)exception {
    if (isBackgroundIPCException(exception)) {
        NSLog(@"[SpaceInvader] -_crashOnException: suppressed — %@: %@",
              exception.name, exception.reason);
        return;
    }
    NSLog(@"[SpaceInvader] -_crashOnException: aborting on user-code exception — %@: %@",
          exception.name, exception.reason);
    abort();
}

@end
