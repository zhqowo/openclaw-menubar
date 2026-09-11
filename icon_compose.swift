// Compose the OpenClaw.app icon: a near-white gradient card with the lobster on top.
//
// Mirrors the shape of OpenClaw's own apple-touch-icon (light background, red
// mascot) while staying full-bleed — macOS applies the squircle mask itself, the
// same way 大肥鱼.app's full-square gradient icon is handled.
//
// Usage: icon_compose <lobster.png> <out.png> [size] [scale]
import AppKit

let args = CommandLine.arguments
let charPath = args.count > 1 ? args[1] : "lobster1024.png"
let outPath = args.count > 2 ? args[2] : "/tmp/openclaw-icon.png"
let S = args.count > 3 ? (Int(args[3]) ?? 1024) : 1024
let scale = args.count > 4 ? (Double(args[4]) ?? 0.84) : 0.84
let px = CGFloat(S)

guard let char = NSImage(contentsOfFile: charPath) else {
    print("cannot load character: \(charPath)"); exit(1)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// 1. background: white fading to a faintly cool grey, so the card has depth
//    without competing with the mascot.
let top = NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1.0)   // #FFFFFF
let bottom = NSColor(srgbRed: 0.93, green: 0.92, blue: 0.94, alpha: 1.0) // #EDEBF0
NSGradient(starting: top, ending: bottom)!
    .draw(in: NSRect(x: 0, y: 0, width: px, height: px), angle: -90)

// 2. the lobster, centred. The source is square and full-bleed (claws reach the
//    edges), so the inset is what keeps it off the icon's rounded border.
let side = px * CGFloat(scale)
let inset = (px - side) / 2
let box = NSRect(x: inset, y: inset, width: side, height: side)
char.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1.0,
          respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high.rawValue])
print("  lobster box: x=\(Int(inset)) y=\(Int(inset)) w=\(Int(side)) h=\(Int(side)) (canvas \(S))")

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    print("encode failed"); exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(S)x\(S), \(png.count) bytes)")

// Sample a few pixels so we can verify the background really is ours.
func sample(_ x: Int, _ y: Int) -> String {
    guard let c = rep.colorAt(x: x, y: y) else { return "?" }
    return String(format: "#%02X%02X%02X a=%.0f",
                  Int(c.redComponent * 255), Int(c.greenComponent * 255),
                  Int(c.blueComponent * 255), c.alphaComponent * 255)
}
print("  corner(4,4)  :", sample(4, 4))
print("  corner(S-5,4):", sample(S - 5, 4))
print("  top-centre   :", sample(S / 2, 6))
print("  centre       :", sample(S / 2, S / 2))
