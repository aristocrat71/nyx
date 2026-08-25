import AppKit
import SwiftUI

struct ToastView: View {
    let message: String
    let accent: Bool

    var body: some View {
        HStack(spacing: 0) {
            (accent ? Theme.amber : Theme.muted).frame(width: 3)
            HStack(spacing: 8) {
                Text("🦉").font(.system(size: 14))
                Text(message)
                    .font(Theme.font(12))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
        }
        .frame(width: 300, height: 56)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

final class ToastCenter {
    private var windows: [NSWindow] = []

    func show(_ message: String, accent: Bool) {
        NSLog("nyx: toast — \(message)")
        if windows.count >= 2, let oldest = windows.first {
            dismiss(oldest)
        }
        let window = OverlayWindow(frame: .zero)
        window.sharingType = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = NSHostingView(rootView: ToastView(message: message, accent: accent))
        window.setFrame(frame(forSlot: windows.count), display: true)
        window.orderFront(nil)
        windows.append(window)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak window] in
            guard let self, let window else { return }
            self.dismiss(window)
        }
    }

    private func frame(forSlot slot: Int) -> CGRect {
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        return CGRect(
            x: screen.maxX - 300 - 16,
            y: screen.maxY - 56 - 16 - CGFloat(slot) * (56 + 8),
            width: 300,
            height: 56
        )
    }

    private func dismiss(_ window: NSWindow) {
        guard let index = windows.firstIndex(of: window) else { return }
        windows.remove(at: index)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
        for (slot, remaining) in windows.enumerated() {
            remaining.setFrame(frame(forSlot: slot), display: true)
        }
    }
}
