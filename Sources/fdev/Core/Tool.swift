import SwiftUI

/// The tool registry. To add a tool: add a case, give it a title/icon/subtitle,
/// and return its view below. Everything else (tab bar, window, menu) picks it up.
enum Tool: String, CaseIterable, Identifiable {
    case color
    case contrast
    case font
    case measure
    case units
    case fluid
    case shadow
    case text
    case image
    case background

    var id: String { rawValue }

    var group: ToolGroup {
        switch self {
        case .color, .contrast, .font, .measure: .inspect
        case .units, .fluid, .shadow: .css
        case .image, .background: .images
        case .text: .code
        }
    }

    /// Global shortcut id in `Shortcut.all`, if this tool has one.
    /// Tools you drop files onto. The menu panel closes as soon as you click Finder to start a drag,
    /// so these open in the fdev window instead.
    var opensInWindow: Bool { self == .background || self == .image }

    var shortcutID: UInt32? {
        switch self {
        case .color: 1
        case .font: 2
        case .measure: 3
        default: nil
        }
    }

    var title: String {
        switch self {
        case .color: "Pick Color"
        case .contrast: "Check Contrast"
        case .font: "Detect Font"
        case .measure: "Measure Screen"
        case .units: "Convert px ↔ rem"
        case .fluid: "Generate Fluid Type"
        case .shadow: "Build Box Shadow"
        case .text: "Transform Text & JSON"
        case .image: "Convert Image"
        case .background: "Remove Background"
        }
    }

    var icon: String {
        switch self {
        case .color: "eyedropper.halffull"
        case .contrast: "circle.lefthalf.filled"
        case .font: "textformat"
        case .measure: "ruler"
        case .units: "arrow.left.arrow.right"
        case .fluid: "textformat.size"
        case .shadow: "shadow"
        case .text: "curlybraces"
        case .image: "photo.on.rectangle.angled"
        case .background: "person.crop.rectangle.badge.plus"
        }
    }

    var subtitle: String {
        switch self {
        case .color: "Pick from any window · ⌥⌘C"
        case .contrast: "WCAG 2.2 contrast checker"
        case .font: "Identify fonts under the cursor · ⌥⌘F"
        case .measure: "Measure anything on screen · ⌥⌘M"
        case .units: "Convert sizes for CSS"
        case .fluid: "Responsive clamp() generator"
        case .shadow: "box-shadow builder · CSS, Tailwind, SwiftUI"
        case .text: "JSON, Base64, URL, naming cases"
        case .image: "AVIF, JPEG, PNG, HEIC · resize & compress"
        case .background: "Photos, logos & graphics · on‑device"
        }
    }

    @MainActor @ViewBuilder
    var view: some View {
        switch self {
        case .color: ColorPickerTool()
        case .contrast: ContrastTool()
        case .font: FontTool()
        case .measure: MeasureTool()
        case .units: UnitsTool()
        case .fluid: FluidTypeTool()
        case .shadow: ShadowTool()
        case .text: TextTool()
        case .image: ImageConvertTool()
        case .background: BackgroundRemoverTool()
        }
    }
}

enum ToolGroup: CaseIterable {
    case inspect, css, images, code
    var title: String {
        switch self {
        case .inspect: "Pick & inspect"
        case .css: "CSS"
        case .images: "Images"
        case .code: "Code"
        }
    }
}
