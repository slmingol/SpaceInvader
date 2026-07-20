#!/usr/bin/env bash
# Automated screenshot capture for SpaceInvader README docs.
#
# Usage:
#   bash scripts/take_screenshots.sh
#
# Requirements:
#   - Screen Recording permission granted to the calling terminal app
#     (System Settings → Privacy & Security → Screen Recording)
#   - Accessibility permission for osascript/System Events
#   - Pillow:  pip3 install pillow
#   - Xcode command-line tools (for swiftc — compiles the mouse-event helper)
#   - SpaceInvader must be running (or installed at /Applications/SpaceInvader.app)
#
# Why bash for screencapture?
#   macOS TCC resolves Screen Recording against the first app bundle in the
#   process tree.  When Python subprocess calls screencapture, TCC finds
#   Python.app (Homebrew bundle) before the terminal app, and Python.app has no
#   Screen Recording permission.  Running screencapture directly from bash skips
#   the Python.app boundary entirely.

set -euo pipefail
cd "$(dirname "$0")/.."  # run from repo root

SHOTS="docs/screenshots"
TMP="/tmp/si_shots"
mkdir -p "$SHOTS" "$TMP"

# ── pre-flight ───────────────────────────────────────────────────────────────

if ! screencapture -x "$TMP/check.png" 2>/dev/null; then
    echo "ERROR: screencapture failed — Screen Recording permission required."
    echo
    echo "Grant it to your terminal app (or to Claude Code if using ! prefix):"
    echo "  System Settings → Privacy & Security → Screen Recording"
    echo
    rm -f "$TMP/check.png"
    exit 1
fi
rm -f "$TMP/check.png"

if ! python3 -c "from PIL import Image" 2>/dev/null; then
    echo "ERROR: Pillow not installed.  Run: pip3 install pillow"
    exit 1
fi

# ── Swift mouse-event helper (compiled once) ─────────────────────────────────
#
# CGWarpMouseCursorPosition only moves the cursor visually — it does NOT fire
# NSEvent global monitors (which the HUD dwell timer listens to).
# CGEventPost(.cghidEventTap) DOES fire them.

MOVER="$TMP/move_mouse"
if [[ ! -f "$MOVER" ]]; then
    echo "Compiling move_mouse helper …"
    cat > "$TMP/move_mouse.swift" << 'SWIFT'
import CoreGraphics
let a = CommandLine.arguments
let p = CGPoint(x: Double(a[1])!, y: Double(a[2])!)
let src = CGEventSource(stateID: .hidSystemState)
let ev  = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                  mouseCursorPosition: p, mouseButton: .left)!
ev.post(tap: .cghidEventTap)
SWIFT
    swiftc "$TMP/move_mouse.swift" -o "$MOVER"
fi

SENDKEY="$TMP/send_key"
# send_key <keyCode> [ctrl] [shift] [cmd] [alt]
# Uses CGEventPost — more reliable than osascript for system-level shortcuts.
SENDKEY_VER=2   # bump when swift source changes to force recompile
if [[ ! -f "$SENDKEY" || ! -f "$TMP/send_key.ver" || "$(cat "$TMP/send_key.ver")" != "$SENDKEY_VER" ]]; then
    echo "$SENDKEY_VER" > "$TMP/send_key.ver"
    echo "Compiling send_key helper …"
    cat > "$TMP/send_key.swift" << 'SWIFT'
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let keyCode = CGKeyCode(UInt16(a[1])!)
var flags: CGEventFlags = []
for arg in a.dropFirst(2) {
    if arg == "ctrl"  { flags.insert(.maskControl) }
    if arg == "shift" { flags.insert(.maskShift) }
    if arg == "cmd"   { flags.insert(.maskCommand) }
    if arg == "alt"   { flags.insert(.maskAlternate) }
}
let src = CGEventSource(stateID: .hidSystemState)
let dn  = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)!
let up  = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)!
dn.flags = flags; up.flags = flags
dn.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.05)
up.post(tap: .cghidEventTap)
SWIFT
    swiftc "$TMP/send_key.swift" -o "$SENDKEY"
fi

# trigger_mc — simulates the actual trackpad swipe gesture event sequence.
# NSEventTypeSwipe (type 31) bracketed by BeginGesture (61) / EndGesture (62)
# is what the multi-touch driver generates for 3-finger swipes.  DockSwipe
# (type 30) opens MC in a degraded mode without thumbnail content; this path
# goes through the real gesture recognizer and triggers full thumbnail rendering.
TRIGGERMC="$TMP/trigger_mc"
TRIGGERMC_VER=3
if [[ ! -f "$TRIGGERMC" || ! -f "$TMP/trigger_mc.ver" || "$(cat "$TMP/trigger_mc.ver")" != "$TRIGGERMC_VER" ]]; then
    echo "$TRIGGERMC_VER" > "$TMP/trigger_mc.ver"
    echo "Compiling trigger_mc helper …"
    cat > "$TMP/trigger_mc.swift" << 'SWIFT'
import CoreGraphics
import Foundation

// open (default) → swipe up = Mission Control
// dismiss        → swipe down = exit Mission Control
let open = CommandLine.arguments.count < 2 || CommandLine.arguments[1] != "dismiss"

let src = CGEventSource(stateID: .hidSystemState)

// axis1 = deltaY (+1 up / -1 down), axis2 = deltaX
func post(type: UInt32, axis1: Double = 0, axis2: Double = 0) {
    guard let ev = CGEvent(source: src) else { return }
    ev.type = CGEventType(rawValue: type)!
    if axis1 != 0 { ev.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: axis1) }
    if axis2 != 0 { ev.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: axis2) }
    ev.post(tap: .cghidEventTap)
}

let dy: Double = open ? 1.0 : -1.0

post(type: 61)              // NSEventTypeBeginGesture
Thread.sleep(forTimeInterval: 0.02)
post(type: 31, axis1: dy)   // NSEventTypeSwipe  (+1 = up = MC, -1 = down = dismiss)
Thread.sleep(forTimeInterval: 0.02)
post(type: 62)              // NSEventTypeEndGesture
SWIFT
    swiftc "$TMP/trigger_mc.swift" -o "$TRIGGERMC"
fi

# ── screen geometry ──────────────────────────────────────────────────────────

read -r GX GY SW SH < <(python3 - << 'PYEOF'
import ctypes
class P(ctypes.Structure):
    _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]
class S(ctypes.Structure):
    _fields_ = [("width", ctypes.c_double), ("height", ctypes.c_double)]
class R(ctypes.Structure):
    _fields_ = [("origin", P), ("size", S)]
cg = ctypes.cdll.LoadLibrary('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
cg.CGMainDisplayID.restype = ctypes.c_uint32
cg.CGDisplayBounds.restype = R
cg.CGDisplayBounds.argtypes = [ctypes.c_uint32]
b = cg.CGDisplayBounds(cg.CGMainDisplayID())
print(int(b.origin.x), int(b.origin.y), int(b.size.width), int(b.size.height))
PYEOF
)
echo "Main display: ${SW}x${SH} at global (${GX},${GY})"

MID_X=$(( GX + SW / 2 ))

# ── helpers ──────────────────────────────────────────────────────────────────

capture() { screencapture -x "$1"; }

move_mouse() { "$MOVER" "$1" "$2"; }

osa_escape() {
    osascript -e 'tell application "System Events" to key code 53'
}

# diff_crop  <before>  <after>  <output>  [sx1 sy1 sx2 sy2]
#
# Finds the bounding box of pixels that changed above threshold 20 and saves
# that region (plus padding) from <after>.
#
# The optional search region (sx1 sy1 sx2 sy2) constrains which part of the
# image is diffed.  Use this to avoid false positives from menu bar clock
# updates, live wallpaper, or other unrelated screen changes.
diff_crop() {
    python3 - "$1" "$2" "$3" "${4:-}" "${5:-}" "${6:-}" "${7:-}" << 'PYEOF'
import sys
from PIL import Image, ImageChops

before = Image.open(sys.argv[1])
after  = Image.open(sys.argv[2])
output = sys.argv[3]
W, H   = after.size

# Parse optional search region
args = [a for a in sys.argv[4:8] if a]
if len(args) == 4:
    sx1, sy1, sx2, sy2 = int(args[0]), int(args[1]), int(args[2]), int(args[3])
    b_roi = before.crop((sx1, sy1, sx2, sy2))
    a_roi = after.crop((sx1, sy1, sx2, sy2))
    ox, oy = sx1, sy1   # offset to translate ROI coords back to full image
else:
    b_roi, a_roi = before, after
    ox, oy = 0, 0

diff = ImageChops.difference(b_roi, a_roi).convert("L")
mask = diff.point(lambda v: 255 if v > 20 else 0)
bbox = mask.getbbox()

if bbox:
    x1, y1, x2, y2 = bbox
    # Translate to full-image coordinates
    x1 += ox; y1 += oy; x2 += ox; y2 += oy
    pad = 6
    crop = after.crop((max(0, x1-pad), max(0, y1-pad),
                       min(W, x2+pad), min(H, y2+pad)))
    crop.save(output)
    print(f"    cropped to ({x1},{y1})→({x2},{y2}), size {crop.size}")
else:
    print("    WARNING: no change detected in search region — saving full region")
    after.crop((ox, oy, ox + (sx2-sx1 if len(args)==4 else W),
                         oy + (sy2-sy1 if len(args)==4 else H))).save(output)
PYEOF
}

# ── ensure SpaceInvader is running ───────────────────────────────────────────

if ! pgrep -xq SpaceInvader; then
    echo "Launching SpaceInvader …"
    open /Applications/SpaceInvader.app
    sleep 2.5
fi

# ── target selection ─────────────────────────────────────────────────────────
# Usage: bash take_screenshots.sh [menubar|menu|hud|mc]
# Omit argument to run all four in sequence.

TARGET="${1:-all}"

# ── 1. Menu bar badge ────────────────────────────────────────────────────────
shot_menubar() {
    echo "→ menubar.png"
    capture "$TMP/full.png"
    python3 - "$TMP/full.png" "$SW" "$SHOTS/menubar.png" << 'PYEOF'
import sys
from PIL import Image
img = Image.open(sys.argv[1])
sw  = int(sys.argv[2])
W, H = img.size
scale   = W / sw
bar_px  = int(28 * scale)
left_px = int(W * 0.72)
img.crop((left_px, 0, W, bar_px)).save(sys.argv[3])
PYEOF
}

# ── 2. Dropdown menu ─────────────────────────────────────────────────────────
shot_menu() {
    echo "→ menu.png"

    read -r BX BY BW BH < <(osascript << 'OSEOF'
tell application "System Events"
    tell process "SpaceInvader"
        set mb  to menu bar item 1 of menu bar 2
        set pos to position of mb
        set sz  to size of mb
        return ((item 1 of pos) as string) & " " & ((item 2 of pos) as string) & " " & ((item 1 of sz) as string) & " " & ((item 2 of sz) as string)
    end tell
end tell
OSEOF
)
    echo "  badge at (${BX},${BY}) ${BW}x${BH}"

    SR_X1=$(( BX - 350 ));  [[ $SR_X1 -lt 0 ]] && SR_X1=0
    SR_X2=$(( BX + BW + 35 ))
    SR_Y1=$BY
    SR_Y2=$SH

    sleep 0.3
    capture "$TMP/before.png"
    osascript << 'OSEOF'
tell application "System Events"
    tell process "SpaceInvader"
        click menu bar item 1 of menu bar 2
    end tell
end tell
OSEOF
    sleep 1.0
    capture "$TMP/after.png"
    diff_crop "$TMP/before.png" "$TMP/after.png" "$SHOTS/menu.png" \
        "$SR_X1" "$SR_Y1" "$SR_X2" "$SR_Y2"
    osa_escape
    sleep 0.4
}

# ── 3. HUD ───────────────────────────────────────────────────────────────────
shot_hud() {
    echo "→ hud.png"
    move_mouse "$MID_X" "$(( GY + SH * 6 / 10 ))"
    sleep 0.9
    capture "$TMP/before.png"

    for _ in 1 2 3 4 5 6 7 8; do
        move_mouse "$MID_X" "$(( GY + 12 ))"
        sleep 0.04
    done
    sleep 0.65

    capture "$TMP/after.png"

    # Start collapsing BEFORE the slow image-processing step so the HUD is fully
    # gone by the time MC opens (collapse needs ~580 ms; Python adds ~1-2 s more).
    move_mouse "$MID_X" "$(( GY + SH * 3 / 4 ))"

    python3 - "$TMP/before.png" "$TMP/after.png" "$SHOTS/hud.png" << 'PYEOF'
import sys
from PIL import Image, ImageChops, ImageFilter

before = Image.open(sys.argv[1])
after  = Image.open(sys.argv[2])
output = sys.argv[3]
W, H   = after.size

# Find HUD bounds: diff constrained to top 180 px.
diff = ImageChops.difference(before.crop((0, 0, W, 180)),
                             after.crop((0, 0, W, 180))).convert("L")
bbox = diff.point(lambda v: 255 if v > 20 else 0).getbbox()

if not bbox:
    print("    WARNING: HUD not found in diff — saving raw top strip")
    after.crop((0, 0, W, 180)).save(output)
else:
    x1, y1, x2, y2 = bbox
    print(f"    HUD bounds: ({x1},{y1})→({x2},{y2})")

    # Canvas: flush to screen top, asymmetric horizontal padding, ~55 px below.
    pad_left = 13
    pad_right = 4
    pad_bot  = 55
    cx1 = max(0, x1 - pad_left)
    cy1 = 0
    cx2 = min(W, x2 + pad_right)
    cy2 = min(H, y2 + pad_bot)

    wide   = after.crop((cx1, cy1, cx2, cy2))
    blurred = wide.filter(ImageFilter.GaussianBlur(radius=14))

    # Paste the sharp HUD back on top of the blurred background.
    sharp = after.crop((x1, y1, x2, y2))
    blurred.paste(sharp, (x1 - cx1, y1 - cy1))

    blurred.save(output)
    print(f"    output size: {blurred.size}")
PYEOF

    sleep 1.0
}

# ── 4. Mission Control ───────────────────────────────────────────────────────
#
# Neither F3 nor Control+Up produces full MC with space thumbnails on this
# system — both keyboard paths use a degraded render mode.  The hot corner
# (top-left = Mission Control) goes through the same animation path as the
# trackpad gesture and correctly pre-populates thumbnail content.
# Requires: Desktop & Dock → Hot Corners → top-left set to "Mission Control".
shot_mc() {
    echo "→ mc.png"

    # Park mouse away from the hot corner so we don't accidentally re-trigger.
    move_mouse "$MID_X" "$(( GY + SH * 3 / 4 ))"
    sleep 0.8

    capture "$TMP/before.png"

    # Move to the top-left hot corner to trigger Mission Control.
    # macOS fires the hot corner after the cursor dwells there ~100-500 ms;
    # then the MC animation runs (~500 ms) and thumbnails render (~1 s more).
    move_mouse "$(( GX + 2 ))" "$(( GY + 2 ))"
    sleep 3.5

    capture "$TMP/after.png"

    # Move cursor to centre before dismissing so the hot corner doesn't
    # re-trigger when we send Escape.
    move_mouse "$MID_X" "$(( GY + SH / 2 ))"
    sleep 0.2

    python3 - "$TMP/before.png" "$TMP/after.png" "$SHOTS/mc.png" << 'PYEOF'
import sys
from PIL import Image, ImageChops
before = Image.open(sys.argv[1])
after  = Image.open(sys.argv[2])
diff = ImageChops.difference(before, after).convert("L")
if diff.getbbox():
    print("    MC transition confirmed")
    W, H = after.size
    crop_h = int(H * 0.40)   # spaces strip + upper window thumbnails
    after.crop((0, 0, W, crop_h)).save(sys.argv[3])
    print(f"    cropped to {W}x{crop_h}")
else:
    print("    WARNING: no screen change detected — is top-left hot corner set to Mission Control?")
PYEOF

    osascript -e 'tell application "System Events" to key code 53'  # Escape
    sleep 0.6
}

# ── dispatch ──────────────────────────────────────────────────────────────────

case "$TARGET" in
    menubar) shot_menubar ;;
    menu)    shot_menu    ;;
    hud)     shot_hud     ;;
    mc)      shot_mc      ;;
    all)     shot_menubar; shot_menu; shot_hud; shot_mc ;;
    *)
        echo "Unknown target '$TARGET'. Valid: menubar  menu  hud  mc  (or omit for all)"
        exit 1
        ;;
esac

echo
echo "Done.  Files in $SHOTS/"
ls -lh "$SHOTS/"
