import AppKit

// Turns assets/nyx-logo.png into the glyph the dashboard tints and two icon
// canvases: at 16pt the padding that frames the owl at 512 starves its strokes.

let args = CommandLine.arguments
guard args.count > 4 else {
    FileHandle.standardError.write(Data("usage: render-icon.swift <source> <glyph> <icon> <small>\n".utf8))
    exit(2)
}
let (sourcePath, glyphPath, iconPath, smallPath) = (args[1], args[2], args[3], args[4])

let paper = NSColor(srgbRed: 0.98, green: 0.98, blue: 0.96, alpha: 1)

func hex(_ v: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
        green: CGFloat((v >> 8) & 0xFF) / 255,
        blue: CGFloat(v & 0xFF) / 255,
        alpha: 1
    )
}

func makeRep(_ width: Int, _ height: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32
    )!
}

func draw(into rep: NSBitmapImageRep, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func write(_ rep: NSBitmapImageRep, to path: String) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "render-icon", code: 1)
    }
    try data.write(to: URL(fileURLWithPath: path))
}

guard let source = NSImage(contentsOfFile: sourcePath) else {
    FileHandle.standardError.write(Data("cannot read \(sourcePath)\n".utf8))
    exit(1)
}

// Black line work on paper, with no alpha of its own: alpha comes from how far
// each pixel falls below the paper's luminance, and the colour is discarded.
let size = source.size
let (width, height) = (Int(size.width.rounded()), Int(size.height.rounded()))
let flat = makeRep(width, height)
draw(into: flat) {
    source.draw(in: NSRect(x: 0, y: 0, width: size.width, height: size.height))
}

let glyph = makeRep(width, height)
guard let input = flat.bitmapData, let output = glyph.bitmapData else { exit(1) }
let paperLuminance = 0.2126 * 0.98 + 0.7152 * 0.98 + 0.0722 * 0.96
// The paper measures up to 0.023 of ink, a faint rectangle the toe drops. The
// artwork is bimodal — paper under 0.05, strokes over 0.85 — so edges survive.
let toe = 0.06

for pixel in 0 ..< (width * height) {
    let offset = pixel * 4
    let r = Double(input[offset]) / 255
    let g = Double(input[offset + 1]) / 255
    let b = Double(input[offset + 2]) / 255
    let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
    let measured = (paperLuminance - luminance) / paperLuminance
    let ink = max(0, min(1, (measured - toe) / (1 - toe)))
    // Premultiplied, which is what NSBitmapImageRep expects by default.
    let value = UInt8((ink * 255).rounded())
    output[offset] = 0
    output[offset + 1] = 0
    output[offset + 2] = 0
    output[offset + 3] = value
}
try write(glyph, to: glyphPath)

// The icon keeps the logo's own paper rather than the dashboard's dark, so it
// reads the same on the Dock as it does on the page it arrived on.
let side = 1024
let tintedGlyph = NSImage(size: glyph.size, flipped: false) { rect in
    glyph.draw(in: rect)
    return true
}

func renderIcon(inset: CGFloat, owlHeight: CGFloat, to path: String) throws {
    let icon = makeRep(side, side)
    let owlWidth = owlHeight * size.width / size.height
    draw(into: icon) {
        paper.setFill()
        let plate = NSRect(
            x: inset, y: inset,
            width: CGFloat(side) - inset * 2, height: CGFloat(side) - inset * 2
        )
        let radius = plate.width * 0.22
        NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius).fill()

        hex(0x101114).set()
        tintedGlyph.draw(in: NSRect(
            x: (CGFloat(side) - owlWidth) / 2,
            y: (CGFloat(side) - owlHeight) / 2,
            width: owlWidth,
            height: owlHeight
        ))
    }
    try write(icon, to: path)
}

try renderIcon(inset: 60, owlHeight: 620, to: iconPath)
try renderIcon(inset: 16, owlHeight: 880, to: smallPath)

print("wrote \(glyphPath), \(iconPath) and \(smallPath)")
