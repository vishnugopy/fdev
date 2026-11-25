import SwiftUI
import AppKit

/// Where the panel is. Persisted so reopening the menu returns to the same page.
enum Route: Equatable {
    case home, tool(Tool)

    init(raw: String) {
        switch raw {
        case "home": self = .home
        default: self = Tool(rawValue: raw).map(Route.tool) ?? .home
        }
    }

    var raw: String {
        switch self {
        case .home: "home"
        case .tool(let t): t.rawValue
        }
    }
}

struct RootView: View {
    let inWindow: Bool
    @AppStorage("route") private var routeRaw = "home"
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var route: Route {
        let r = Route(raw: routeRaw)
        if case .tool(let t) = r, !settings.visibleTools.contains(t) { return .home }
        return r
    }

    private func go(_ r: Route) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { routeRaw = r.raw }
        if case .tool(let t) = r { UserDefaults.standard.set(t.rawValue, forKey: "lastTool") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch route {
            case .home:
                HomeView(inWindow: inWindow, go: go)
                    .transition(.opacity)
            case .tool(let t):
                Page(title: t.title, subtitle: t.subtitle, showPin: !inWindow, back: { go(.home) }) {
                    t.view
                }
                .id(t)
                .transition(.opacity)
            }
        }
        .padding(Metrics.edge)
        .environment(\.headerLead, inWindow ? 64 : 0)   // window: header shares the row with the traffic lights
        .frame(width: Metrics.panelWidth)
        .ignoresSafeArea(.container, edges: inWindow ? .top : [])
    }
}

// MARK: - Home (Wi‑Fi menu style list)

private struct HomeView: View {
    let inWindow: Bool
    let go: (Route) -> Void
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var menu = MenuPanel.shared
    @ObservedObject private var shots = ScreenshotKeeper.shared
    @Environment(\.headerLead) private var headerLead
    @AppStorage("lastTool") private var lastTool = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                LogoMark(size: 22)
                Text("fdev").font(.system(size: 13, weight: .bold))
                Spacer()
                if !inWindow { PinButton() }
            }
            .padding(.horizontal, Metrics.inset)
            .padding(.leading, headerLead)
            .frame(minHeight: 34)

            if !inWindow && menu.dragActive {
                MenuHeader("Drop image to")
                DropTargetsView()
                    .transition(.opacity)
            } else if shots.last != nil {
                LastScreenshotRow()
            }

            ForEach(ToolGroup.allCases, id: \.self) { g in
                let tools = settings.visibleTools.filter { $0.group == g }
                if !tools.isEmpty {
                    MenuDivider()
                    MenuHeader(g.title)
                    ForEach(tools) { t in toolRow(t) }
                }
            }

            MenuDivider()
            MenuActionRow(title: "Clean Keyboard…") { KeyboardCleaner.shared.start() }
                .help("Ignore all key presses for 60 s so you can wipe the keyboard")
            if !inWindow {
                MenuActionRow(title: "Open in Window") { MenuPanel.shared.close(); MainWindow.shared.show() }
            }
            MenuActionRow(title: "Settings…", hint: "⌘,") {
                SettingsWindow.shared.show()
            }
                .keyboardShortcut(",")
            MenuActionRow(title: "Quit fdev", hint: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private func toolRow(_ t: Tool) -> some View {
        let current = t.rawValue == lastTool
        let toWindow = t.opensInWindow && !inWindow && !menu.pinned
        return MenuRow(action: {
            if toWindow {
                MenuPanel.shared.close()
                MainWindow.shared.show(tool: t)
            } else { go(.tool(t)) }
        }) {
            IconCircle(symbol: t.icon, active: current)
            Text(t.title).font(.system(size: 13))
            Spacer(minLength: 8)
            if let id = t.shortcutID, !settings.disabledShortcuts.contains(id),
               let sc = Shortcut.all.first(where: { $0.id == id }) {
                Text(settings.binding(for: sc).display).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Image(systemName: toWindow ? "macwindow" : "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .help(toWindow ? "\(t.subtitle) — opens in a window so you can drop files (or pin this menu)" : t.subtitle)
        .accessibilityLabel(current ? "\(t.title), last used" : t.title)
    }
}

// MARK: - Drill-down page (like a Control Center module)

private struct Page<Content: View>: View {
    let title: String
    let subtitle: String
    let showPin: Bool
    let back: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.headerLead) private var headerLead

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.primary.opacity(0.1)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("[", modifiers: .command)
                .help("Back (⌘[)")
                .accessibilityLabel("Back")

                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .bold))
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if showPin { PinButton() }
            }
            .padding(.horizontal, Metrics.inset)
            .padding(.leading, headerLead)
            .frame(minHeight: 40)

            MenuDivider()

            content()
                .padding(.horizontal, Metrics.inset)
                .padding(.top, 4).padding(.bottom, 6)
                .environment(\.rowOutset, Metrics.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HeaderLeadKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues {
    /// Extra leading space for headers — in the window they share the title bar row with the traffic lights.
    var headerLead: CGFloat {
        get { self[HeaderLeadKey.self] }
        set { self[HeaderLeadKey.self] = newValue }
    }
}
