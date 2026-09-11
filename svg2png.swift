// Rasterize an SVG (or any image NSImage can load) to a square PNG with a
// transparent background — qlmanage renders SVG onto opaque white, which is
// useless for a menu-bar icon.
//
// Usage: svg2png <in.svg> <out.png> [size]
import AppKit

let args = CommandLine.arguments
let src = args.count > 1 ? args[1] : ""
let dst = args.count > 2 ? args[2] : "/tmp/out.png"
let S = args.count > 3 ? (Int(args[3]) ?? 1024) : 1024

guard !src.isEmpty, let img = NSImage(contentsOfFile: src) else {
    print("LOAD FAIL: \(src)"); exit(1)
}
print("  source native size: \(Int(img.size.width))x\(Int(img.size.height))")

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
img.draw(in: NSRect(x: 0, y: 0, width: S, height: S), from: .zero, operation: .sourceOver,
         fraction: 1.0, respectFlipped: false,
         hints: [.interpolation: NSImageInterpolation.high.rawValue])
NSGraphicsContext.restoreGraphicsState()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dst))
let corner = rep.colorAt(x: 1, y: 1)!
print("wrote \(dst) (\(S)x\(S)) corner alpha=\(String(format: "%.2f", corner.alphaComponent))")
