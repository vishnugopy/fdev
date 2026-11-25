import SwiftUI
import AppKit

@main
struct FdevApp: App {
    init() {
        // `fdev --render-icon out.png` — used by build.sh so the icon and the in-app logo share one drawing.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
            do { try LogoArtwork.renderAppIcon(to: URL(fileURLWithPath: args[i + 1])); exit(0) }
            catch { print(error); exit(1) }
        }
        // `fdev --snapshot out.png [route]` — renders the panel to an image for design review.
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            _ = NSApplication.shared
            if i + 2 < args.count { UserDefaults.standard.set(args[i + 2], forKey: "route") }
            let view: AnyView
            if i + 2 < args.count, args[i + 2] == "wheel" {
                let m = ActionWheel.shared.model
                m.items = AppSettings.defaultWheel; m.highlighted = 1; m.appeared = true
                m.origin = CGPoint(x: 180, y: 180)
                view = AnyView(WheelView(model: m).frame(width: 360, height: 360).background(Color.gray))
            } else {
                view = AnyView(RootView(inWindow: false)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, .dark))
            }
            let r = ImageRenderer(content: view)
            r.scale = 2
            if let cg = r.cgImage,
               let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: args[i + 1]))
            }
            exit(0)
        }
        // `fdev --remove-bg in.png out.png [auto|subject|color]` — runs the background remover headless (testing).
        if let i = args.firstIndex(of: "--remove-bg"), i + 2 < args.count {
            let mode = i + 3 < args.count ? BGMode.allCases.first { $0.rawValue.lowercased().hasPrefix(args[i + 3]) } ?? .auto : .auto
            guard let img = NSImage(contentsOfFile: args[i + 1]),
                  let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("can't read"); exit(1) }
            do {
                let r = try BackgroundRemover.remove(cg, mode: mode, tolerance: 25, crop: false)
                if case .color(let c) = r.method { print("method: color", c.components ?? []) } else { print("method: subject") }
                try BackgroundRemoverModel.png(r.image)?.write(to: URL(fileURLWithPath: args[i + 2]))
                exit(0)
            } catch { print("error:", error.localizedDescription); exit(1) }
        }
        // Global shortcuts (action wheel, pick color, detect font, measure) — rebindable in Settings.
        AppSettings.shared.applyHotKeys()
        DispatchQueue.main.async {
            MenuPanel.shared.install()
            ScreenshotKeeper.shared.start()
        }
        SettingsSync.shared.start()
    }

    var body: some Scene {
        // The menu bar dropdown is MenuPanel (installed in init); this scene only supplies ⌘, .
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { SettingsWindow.shared.show() }.keyboardShortcut(",")
                }
            }
    }
}
