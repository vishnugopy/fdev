import SwiftUI

/// The Settings window (⌘,) — native tabs + grouped forms, like System Settings.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Copy Pop‑up", systemImage: "checkmark.bubble") { PopupSettings() }
            Tab("Shortcuts", systemImage: "command") { ShortcutSettings() }
            Tab("Wheel", systemImage: "circle.circle") { WheelSettings() }
            Tab("Tools", systemImage: "square.grid.2x2") { ToolSettings() }
            Tab("Color", systemImage: "eyedropper.halffull") { ColorSettings() }
        }
        .frame(width: 520, height: 560)
    }
}

private struct GeneralSettings: View {
    @ObservedObject private var s = AppSettings.shared
    @ObservedObject private var fonts = FontStore.shared
    @ObservedObject private var colors = ColorStore.shared
    @State private var confirmReset = false
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    LogoMark(size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("fdev").font(.headline)
                        Text("Frontend toolkit for macOS · \(AppSettings.version)")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { s.launchAtLogin }, set: { s.setLaunchAtLogin($0) }))
                if let e = s.loginError {
                    Text(e).font(.caption).foregroundStyle(.orange)
                }
            }

            Section {
                LabeledContent("Accessibility") {
                    if fonts.trusted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant Access…") { fonts.requestAccess() }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Needed by Detect Font to read the font of text in other apps.")
            }

            SyncSection()

            Section("Data") {
                LabeledContent("Color history") {
                    HStack {
                        Text("\(colors.history.count) colors").foregroundStyle(.secondary)
                        confirmButton("Clear", confirming: $confirmClear) { colors.clear() }
                            .disabled(colors.history.isEmpty)
                    }
                }
                LabeledContent("All settings") {
                    confirmButton("Reset", confirming: $confirmReset) { s.resetAll() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { fonts.refreshTrust() }
    }
}

private struct PopupSettings: View {
    @ObservedObject private var s = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show a pop‑up when something is copied", isOn: $s.toastEnabled)
            }
            Section {
                LabeledContent("Duration") {
                    HStack {
                        Slider(value: $s.toastDuration, in: 0.4...3, step: 0.1)
                            .frame(width: 200)
                            .accessibilityLabel("Duration")
                        Text("\(Num.fmt(s.toastDuration, decimals: 1)) s")
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Picker("Position on screen", selection: $s.toastPosition) {
                    ForEach(ToastPosition.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("") {
                    Button("Preview") {
                        CopyHUD.shared.show(text: "#4F8CFF", swatch: Color(red: 0.31, green: 0.55, blue: 1))
                    }
                }
            }
            .disabled(!s.toastEnabled)
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutSettings: View {
    @ObservedObject private var s = AppSettings.shared

    var body: some View {
        Form {
            Section {
                ForEach(Shortcut.all) { sc in
                    let on = Binding(
                        get: { !s.disabledShortcuts.contains(sc.id) },
                        set: { v in if v { s.disabledShortcuts.remove(sc.id) } else { s.disabledShortcuts.insert(sc.id) } }
                    )
                    LabeledContent {
                        HStack(spacing: 12) {
                            ShortcutRecorder(shortcut: sc)
                                .disabled(!on.wrappedValue)
                            Toggle("", isOn: on).labelsHidden().toggleStyle(.switch).controlSize(.small)
                                .accessibilityLabel("Enable \(sc.title)")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(sc.title)
                            if s.failedShortcuts.contains(sc.id) && on.wrappedValue {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                    .help("macOS refused this combination — choose another.")
                                    .accessibilityLabel("Unavailable")
                            }
                        }
                    }
                }
            } footer: {
                Text("Click Change, then press the new combination — it must include ⌘, ⌥ or ⌃, or be an F‑key on its own. Esc cancels. Shortcuts work from any app.")
            }

            Section {
                LiveShortcutIndicator()
            } header: {
                Text("Test")
            } footer: {
                Text("Press any fdev shortcut — this lights up the moment fdev receives it.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct WheelSettings: View {
    @ObservedObject private var s = AppSettings.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Open the wheel") {
                    if let sc = Shortcut.all.first(where: { $0.id == Shortcut.wheelID }) {
                        HStack(spacing: 8) {
                            ShortcutRecorder(shortcut: sc)
                            Menu("Presets") {
                                ForEach(KeyBinding.wheelPresets, id: \.display) { b in
                                    Button {
                                        if s.conflict(b, excluding: sc) == nil {
                                            s.setBinding(b == sc.defaultBinding ? nil : b, for: sc)
                                        } else { NSSound.beep() }
                                    } label: {
                                        Text(b.display + (b == s.binding(for: sc) ? "  ✓" : ""))
                                    }
                                }
                            }
                            .fixedSize()
                        }
                    }
                }
                Toggle(isOn: $s.wheelHold) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hold to aim, release to select")
                        Text(s.wheelHold
                             ? "Like a game weapon wheel. A quick tap keeps it open so you can click instead."
                             : "Press once to open, then click a slice or press its number.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Behavior")
            } footer: {
                Text("Number keys 1–9 pick a slice, Return runs the highlighted one, Esc or right‑click closes.")
            }

            Section {
                ForEach(Tool.allCases) { t in
                    let included = s.wheelTools.contains(t)
                    Toggle(isOn: Binding(get: { included }, set: { s.setWheel(t, included: $0) })) {
                        Label {
                            HStack {
                                Text(t.title)
                                Spacer()
                                if let i = s.wheelTools.firstIndex(of: t) {
                                    Text("\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        } icon: { IconCircle(symbol: t.icon, active: included, size: 24) }
                    }
                    .disabled(included && s.wheelTools.count <= 2)
                }
            } header: {
                Text("On the wheel (\(s.wheelTools.count))")
            } footer: {
                Text("Slices go clockwise from the top. Pick Color, Detect Font and Measure Screen run right away; other tools open in the fdev window.")
            }

            Section {
                Button("Try the wheel") { ActionWheel.shared.open() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ToolSettings: View {
    @ObservedObject private var s = AppSettings.shared

    var body: some View {
        Form {
            ForEach(ToolGroup.allCases, id: \.self) { g in
                Section(g.title) {
                    ForEach(Tool.allCases.filter { $0.group == g }) { t in
                        let visible = !s.hiddenTools.contains(t.rawValue)
                        Toggle(isOn: Binding(get: { visible }, set: { s.setTool(t, visible: $0) })) {
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.title)
                                    Text(t.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                IconCircle(symbol: t.icon, size: 24)
                            }
                        }
                        .disabled(visible && s.visibleTools.count == 1)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ColorSettings: View {
    @ObservedObject private var s = AppSettings.shared
    @ObservedObject private var colors = ColorStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("Copy automatically after picking", isOn: $colors.autoCopy)
                Picker("Copy format", selection: $colors.autoCopyFormat) {
                    ForEach(ColorFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .disabled(!colors.autoCopy)
                Toggle("Lowercase HEX (#4f8cff)", isOn: $s.hexLowercase)
            }
        }
        .formStyle(.grouped)
    }
}

/// Two-step destructive action.
private func confirmButton(_ title: String, confirming: Binding<Bool>, action: @escaping () -> Void) -> some View {
    HStack(spacing: 6) {
        if confirming.wrappedValue {
            Button("Cancel") { confirming.wrappedValue = false }
            Button("Confirm \(title)", role: .destructive) {
                action(); confirming.wrappedValue = false
            }
            .buttonStyle(.borderedProminent).tint(.red)
        } else {
            Button("\(title)…") { confirming.wrappedValue = true }
        }
    }
}

private struct SyncSection: View {
    @ObservedObject private var sync = SettingsSync.shared

    var body: some View {
        Section {
            Toggle("Sync settings with iCloud Drive", isOn: $sync.enabled)
                .disabled(!SettingsSync.iCloudDriveAvailable)
            if sync.enabled {
                LabeledContent("Status") {
                    HStack(spacing: 8) {
                        if let e = sync.error {
                            Text(e).foregroundStyle(.orange)
                        } else if let d = sync.lastSync {
                            Text("Synced \(d.formatted(date: .omitted, time: .shortened))\(sync.lastSource.map { " · \($0)" } ?? "")")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Waiting…").foregroundStyle(.secondary)
                        }
                        Button("Sync Now") { sync.syncNow() }
                    }
                }
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text(SettingsSync.iCloudDriveAvailable
                 ? "Shortcuts, the wheel, pop‑up, tool settings and color history are saved to iCloud Drive › fdev and applied on every Mac where fdev is installed."
                 : "Turn on iCloud Drive in System Settings › Apple Account › iCloud to sync.")
        }
    }
}

/// Shows the last shortcut fdev received, so you can see a key combo is working.
private struct LiveShortcutIndicator: View {
    @ObservedObject private var s = AppSettings.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let recent = s.lastHotKey.map { ctx.date.timeIntervalSince($0.at) < 1.2 } ?? false
            HStack(spacing: 10) {
                Circle()
                    .fill(recent ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                if let e = s.lastHotKey, let sc = Shortcut.all.first(where: { $0.id == e.id }) {
                    Text(sc.title).fontWeight(.medium)
                    HStack(spacing: 3) { ForEach(s.binding(for: sc).keys, id: \.self) { Keycap($0) } }
                    Text(e.pressed ? "pressed" : "released").foregroundStyle(.secondary)
                    Spacer()
                    Text(e.at.formatted(date: .omitted, time: .standard))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                } else {
                    Text("Waiting for a shortcut…").foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
