import SwiftUI

// Native macOS menu styling (like the Wi‑Fi / Control Center menus):
// section headers, full-width rows with a hover highlight, round icon badges, hairline dividers.
// The panel's own background provides the material — content stays flat.

enum Metrics {
    static let edge: CGFloat = 6          // panel edge → row highlight
    static let inset: CGFloat = 8         // row highlight → row content
    static let section: CGFloat = 12      // between blocks inside a tool
    static let panelWidth: CGFloat = 360
    static let rowHeight: CGFloat = 32
}

/// Inside a tool page, content is inset to line up with text; rows "outset" back so their
/// highlight still reaches the same edges as on the home list.
private struct RowOutsetKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues {
    var rowOutset: CGFloat {
        get { self[RowOutsetKey.self] }
        set { self[RowOutsetKey.self] = newValue }
    }
}

/// "Réseaux connus"-style header.
struct MenuHeader: View {
    let title: String
    @Environment(\.rowOutset) private var outset
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Metrics.inset)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, -outset)
            .accessibilityAddTraits(.isHeader)
    }
}

struct MenuDivider: View {
    @Environment(\.rowOutset) private var outset
    var body: some View {
        Divider().padding(.horizontal, Metrics.inset - outset).padding(.vertical, 4)
    }
}

/// Round icon badge — filled accent when active, neutral otherwise.
struct IconCircle: View {
    let symbol: String
    var active = false
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(active ? Color.white : Color.primary)
            .frame(width: size, height: size)
            .background(Circle().fill(active ? Color.accentColor : Color.primary.opacity(0.1)))
            .accessibilityHidden(true)
    }
}

/// A full-width menu row with the system-style hover highlight.
struct MenuRow<Content: View>: View {
    var selected = false
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hover = false
    @Environment(\.rowOutset) private var outset

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { content() }
                .padding(.horizontal, Metrics.inset)
                .frame(maxWidth: .infinity, minHeight: Metrics.rowHeight, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(hover ? 0.1 : selected ? 0.06 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .padding(.horizontal, -outset)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Plain text row like "Réglages Wi‑Fi…", with an optional trailing hint.
struct MenuActionRow: View {
    let title: String
    var hint: String? = nil
    let action: () -> Void
    var body: some View {
        MenuRow(action: action) {
            Text(title).font(.system(size: 13))
            Spacer(minLength: 8)
            if let hint { Text(hint).font(.system(size: 12)).foregroundStyle(.secondary) }
        }
    }
}

/// Label + trailing control row (switches, pickers) — no hover, since it isn't a button.
struct MenuControlRow<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing
    @Environment(\.rowOutset) private var outset
    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 13))
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, Metrics.inset)
        .frame(minHeight: Metrics.rowHeight)
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.horizontal, -outset)
    }
}

extension View {
    /// Subtle inset surface for previews, fields and code — used sparingly.
    func well(_ radius: CGFloat = 8) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    /// Small selectable chip (presets, layer numbers, quick values).
    /// Selected = accent tint + outline, so it isn't color-only.
    func chip(_ selected: Bool) -> some View {
        background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1)
        )
    }

    /// Content blocks inside a tool line up with row text.
    func blockInset() -> some View { padding(.horizontal, Metrics.inset) }
}

/// Small keycap, shared by Settings and the Font tool.
struct Keycap: View {
    let key: String
    init(_ key: String) { self.key = key }
    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(minWidth: 20, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12)))
    }
}

/// The app mark — same drawing as the app icon.
struct LogoMark: View {
    var size: CGFloat
    var body: some View {
        Image(nsImage: LogoArtwork.tileImage(size: size))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
