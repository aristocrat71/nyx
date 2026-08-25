import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "owl-1024.png"

func hex(_ v: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
        green: CGFloat((v >> 8) & 0xFF) / 255,
        blue: CGFloat(v & 0xFF) / 255,
        alpha: 1
    )
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

hex(0x0E0F12).setFill()
NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 200, yRadius: 200).fill()

hex(0xE8E8E8).setFill()
NSBezierPath(ovalIn: NSRect(x: 292, y: 190, width: 440, height: 520)).fill()
let ears = NSBezierPath()
ears.move(to: NSPoint(x: 330, y: 620)); ears.line(to: NSPoint(x: 352, y: 800)); ears.line(to: NSPoint(x: 490, y: 685)); ears.close()
let rightEar = NSBezierPath()
rightEar.move(to: NSPoint(x: 694, y: 620)); rightEar.line(to: NSPoint(x: 672, y: 800)); rightEar.line(to: NSPoint(x: 534, y: 685)); rightEar.close()
ears.fill()
rightEar.fill()

hex(0xF5A623).setFill()
NSBezierPath(ovalIn: NSRect(x: 362, y: 460, width: 130, height: 130)).fill()
NSBezierPath(ovalIn: NSRect(x: 532, y: 460, width: 130, height: 130)).fill()

hex(0x0E0F12).setFill()
NSBezierPath(ovalIn: NSRect(x: 402, y: 500, width: 50, height: 50)).fill()
NSBezierPath(ovalIn: NSRect(x: 572, y: 500, width: 50, height: 50)).fill()

let beak = NSBezierPath()
beak.move(to: NSPoint(x: 482, y: 440)); beak.line(to: NSPoint(x: 542, y: 440)); beak.line(to: NSPoint(x: 512, y: 380)); beak.close()
hex(0xF5A623).setFill()
beak.fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
