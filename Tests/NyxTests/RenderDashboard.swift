import AppKit
import SwiftUI
import Testing
@testable import Nyx

/// Writes the dashboard to PNG in both appearances so the layout can be looked
/// at. Off by default; set NYX_RENDER to a directory to produce them.
@Suite("Dashboard render", .enabled(if: ProcessInfo.processInfo.environment["NYX_RENDER"] != nil))
@MainActor
struct RenderDashboardTests {
    @Test(arguments: [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)])
    func renderDashboard(name: String, appearance: NSAppearance.Name) throws {
        let directory = try #require(ProcessInfo.processInfo.environment["NYX_RENDER"])
        Theme.registerBundledFonts()

        let list = ProtectionList()
        let model = AppModel()
        model.state = .active
        model.hasScreenPermission = true
        model.isDark = appearance == .darkAqua

        let view = DashboardView(list: list, model: model)
            .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light)

        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(420 * scale), pixelsHigh: Int(540 * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let context = try #require(NSGraphicsContext(bitmapImageRep: rep))

        try #require(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            renderer.render { _, draw in
                context.cgContext.scaleBy(x: scale, y: scale)
                draw(context.cgContext)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "\(directory)/dashboard-\(name).png"))

        try render(
            SettingsPopover(model: model)
                .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light),
            size: CGSize(width: 310, height: 170),
            appearance: appearance,
            to: "\(directory)/settings-\(name).png"
        )
    }

    private func render(
        _ view: some View, size: CGSize, appearance: NSAppearance.Name, to path: String
    ) throws {
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
        try #require(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            renderer.render { _, draw in
                context.cgContext.scaleBy(x: scale, y: scale)
                draw(context.cgContext)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        try #require(rep.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: path))
    }
}
