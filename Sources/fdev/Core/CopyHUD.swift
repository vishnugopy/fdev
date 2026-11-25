import SwiftUI
import AppKit

/// Shared clipboard helpers. Every copy flashes a centered Liquid Glass HUD.
@MainActor
enum Clipboard {
    /// changeCount right after fdev's own last copy — so the screenshot keeper can ignore it.
    nonisolated(unsafe) static var lastOwnChange = -1
    static func copy(_ s: String, swatch: Color? = nil, symbol: String = "checkmark") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        CopyHUD.shared.show(text: s, swatch: swatch, symbol: symbol)
    }

    static func copy(image: NSImage, png: Data?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        if let png { pb.setData(png, forType: .png) }
        lastOwnChange = pb.changeCount
        CopyHUD.shared.show(text: "Image copied", swatch: nil, symbol: "photo")
    }
}

/// A borderless, click-through panel centered on the active screen — like the
/// system volume HUD. Duration and position are configurable in Settings.
@MainActor
final class CopyHUD {
    static let shared = CopyHUD()

    private var panel: NSPanel?
    private var host: NSHostingView<HUDView>?
    private var hideWork: DispatchWorkItem?

    private let fadeIn: TimeInterval = 0.1
    private let fadeOut: TimeInterval = 0.2
    /// Total visible time comes from Settings (default 1s).
    private var hold: TimeInterval { max(0.1, AppSettings.shared.toastDuration - fadeIn - fadeOut) }

    func show(text: String, swatch: Color?, symbol: String = "checkmark") {
        guard AppSettings.shared.toastEnabled else { return }
        let view = HUDView(text: text, swatch: swatch, symbol: symbol)
        let panel = self.panel ?? makePanel()
        if let host { host.rootView = view } else {
            let h = NSHostingView(rootView: view)
            h.sizingOptions = [.intrinsicContentSize]
            panel.contentView = h
            host = h
        }
        host?.layoutSubtreeIfNeeded()
        let size = host?.fittingSize ?? CGSize(width: 220, height: 64)

        // Center on the screen the mouse is on.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let f = screen?.frame ?? .zero
        let y: CGFloat = switch AppSettings.shared.toastPosition {
        case .center: f.midY - size.height / 2
        case .top: f.maxY - 120 - size.height
        case .bottom: f.minY + 120
        }
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: y,
                              width: size.width, height: size.height), display: true)

        hideWork?.cancel()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = fadeIn; panel.animator().alphaValue = 1 }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = self.fadeOut; panel.animator().alphaValue = 0 },
                                                 completionHandler: { panel.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeIn + hold, execute: work)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel = p
        return p
    }
}

struct HUDView: View {
    let text: String
    let swatch: Color?
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            if let swatch {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(swatch)
                    .frame(width: 30, height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(.white.opacity(0.4), lineWidth: 1))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Copied").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Text(text)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: 320, alignment: .leading)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(20)   // room for the glass edge highlight
        .fixedSize()
    }
}
