#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Generate a DMG background image using sips + Core Graphics
#
# Creates a 560x320 dark background with a subtle arrow
# indicating "drag Anna to Applications"
#
# Output: Resources/dmg_background.png (or @2x variant)
# ─────────────────────────────────────────────────────────────

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT_DIR/Resources/dmg_background.png"
OUTPUT_2X="$ROOT_DIR/Resources/dmg_background@2x.png"

mkdir -p "$ROOT_DIR/Resources"

# Generate using Python + Quartz (available on all Macs)
python3 - "$OUTPUT" "$OUTPUT_2X" <<'PYEOF'
import sys
import os

try:
    import Quartz
    from CoreGraphics import *
    from CoreText import *

    def create_background(path, width, height, scale=1):
        w = int(width * scale)
        h = int(height * scale)

        cs = CGColorSpaceCreateWithName(Quartz.kCGColorSpaceSRGB)
        ctx = CGBitmapContextCreate(None, w, h, 8, w * 4, cs,
                                     Quartz.kCGImageAlphaPremultipliedLast)

        # Dark background matching Anna's theme
        CGContextSetRGBFillColor(ctx, 0.06, 0.06, 0.08, 1.0)
        CGContextFillRect(ctx, CGRectMake(0, 0, w, h))

        # Subtle gradient overlay
        CGContextSaveGState(ctx)
        gradient_cs = CGColorSpaceCreateWithName(Quartz.kCGColorSpaceSRGB)
        gradient = CGGradientCreateWithColorComponents(
            gradient_cs,
            [0.08, 0.08, 0.12, 0.3,  0.06, 0.06, 0.08, 0.0],
            [0.0, 1.0], 2
        )
        CGContextDrawRadialGradient(
            ctx, gradient,
            CGPointMake(w * 0.5, h * 0.5), 0,
            CGPointMake(w * 0.5, h * 0.5), w * 0.6,
            Quartz.kCGGradientDrawsAfterEndLocation
        )
        CGContextRestoreGState(ctx)

        # Draw arrow between icon positions (pointing right)
        arrow_y = h * 0.5
        arrow_x_start = w * 0.38
        arrow_x_end = w * 0.62
        arrow_size = 8 * scale

        CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 0.12)
        CGContextSetLineWidth(ctx, 1.5 * scale)
        CGContextSetLineCap(ctx, Quartz.kCGLineCapRound)

        # Arrow shaft
        CGContextMoveToPoint(ctx, arrow_x_start, arrow_y)
        CGContextAddLineToPoint(ctx, arrow_x_end, arrow_y)
        CGContextStrokePath(ctx)

        # Arrow head
        CGContextMoveToPoint(ctx, arrow_x_end - arrow_size, arrow_y + arrow_size)
        CGContextAddLineToPoint(ctx, arrow_x_end, arrow_y)
        CGContextAddLineToPoint(ctx, arrow_x_end - arrow_size, arrow_y - arrow_size)
        CGContextStrokePath(ctx)

        # Save
        image = CGBitmapContextCreateImage(ctx)
        url = Quartz.CFURLCreateFromFileSystemRepresentation(None, path.encode(), len(path.encode()), False)
        dest = Quartz.CGImageDestinationCreateWithURL(url, "public.png", 1, None)
        Quartz.CGImageDestinationAddImage(dest, image, None)
        Quartz.CGImageDestinationFinalize(dest)

    output_1x = sys.argv[1]
    output_2x = sys.argv[2]
    create_background(output_1x, 560, 320, scale=1)
    create_background(output_2x, 560, 320, scale=2)
    print(f"Created: {output_1x}")
    print(f"Created: {output_2x}")

except ImportError:
    # Fallback: create a simple solid-color PNG using sips
    import subprocess
    output_1x = sys.argv[1]

    # Create a tiny TIFF, then resize
    subprocess.run([
        "python3", "-c",
        f"""
import struct, zlib
def create_png(path, w, h, r, g, b):
    raw = b''
    for y in range(h):
        raw += b'\\x00' + bytes([r, g, b]) * w
    compressed = zlib.compress(raw)
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    with open(path, 'wb') as f:
        f.write(b'\\x89PNG\\r\\n\\x1a\\n')
        f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b'IDAT', compressed))
        f.write(chunk(b'IEND', b''))
create_png('{output_1x}', 560, 320, 15, 15, 20)
"""
    ], check=True)
    print(f"Created (fallback): {output_1x}")
PYEOF

echo "DMG background generated."
