#import <Foundation/Foundation.h>

// Private CoreGraphics Server APIs — undocumented, present in SkyLight.framework.
// Verified working on macOS 15 Sequoia. May change between OS releases.

int _CGSDefaultConnection(void);
id CGSCopyManagedDisplaySpaces(int conn);
id CGSActiveMenuBarDisplayIdentifier(int conn);
int CGSManagedDisplaySetCurrentSpace(int cid, CFStringRef display, uint64_t spaceID);
#import "../Helpers/CGSHelpers.h"
#import "SpaceInvaderNSApplication.h"
