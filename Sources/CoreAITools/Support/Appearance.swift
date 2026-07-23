import SwiftUI

// MARK: - Appearance Options

enum AccentColorOption: String, CaseIterable, Identifiable {
    case indigo, blue, purple, pink, red, orange, green, teal, yellow
    var id: String { rawValue }

    var label: String {
        switch self {
        case .indigo: return "Indigo"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .red: return "Red"
        case .orange: return "Orange"
        case .green: return "Green"
        case .teal: return "Teal"
        case .yellow: return "Yellow"
        }
    }

    var color: Color {
        switch self {
        case .indigo: return .indigo
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .green: return .green
        case .teal: return .teal
        case .yellow: return .yellow
        }
    }
}

enum GlassMaterialOption: String, CaseIterable, Identifiable {
    case ultraThin, thin, regular, thick, ultraThick
    var id: String { rawValue }

    var label: String {
        switch self {
        case .ultraThin: return "Ultra Thin"
        case .thin: return "Thin"
        case .regular: return "Regular"
        case .thick: return "Thick"
        case .ultraThick: return "Ultra Thick"
        }
    }

    var material: Material {
        switch self {
        case .ultraThin: return .ultraThinMaterial
        case .thin: return .thinMaterial
        case .regular: return .regularMaterial
        case .thick: return .thickMaterial
        case .ultraThick: return .ultraThickMaterial
        }
    }
}

enum SidebarStyleOption: String, CaseIterable, Identifiable {
    case glass, solid
    var id: String { rawValue }
    var label: String { self == .glass ? "Glass" : "Solid" }
}

// MARK: - Theme Presets

/// Curated combinations of accent + glass material for one-tap customization.
struct ThemePreset: Identifiable, CaseIterable {
    let id: String
    let name: String
    let accent: AccentColorOption
    let glassMaterial: GlassMaterialOption
    let vividGlass: Bool

    @MainActor
    func apply(to settings: AppearanceSettings) {
        settings.accent = accent
        settings.glassMaterial = glassMaterial
        settings.vividGlass = vividGlass
    }

    static let allCases: [ThemePreset] = [
        ThemePreset(id: "indigo-glass", name: "Indigo Glass", accent: .indigo, glassMaterial: .thin, vividGlass: true),
        ThemePreset(id: "graphite", name: "Graphite", accent: .blue, glassMaterial: .regular, vividGlass: false),
        ThemePreset(id: "sunset", name: "Sunset", accent: .orange, glassMaterial: .ultraThin, vividGlass: true),
        ThemePreset(id: "forest", name: "Forest", accent: .green, glassMaterial: .thick, vividGlass: false),
        ThemePreset(id: "mono", name: "Mono", accent: .teal, glassMaterial: .ultraThick, vividGlass: true)
    ]
}

// MARK: - Appearance Settings (app-wide, UserDefaults-backed, observable)

@MainActor
@Observable
final class AppearanceSettings {
    static let shared = AppearanceSettings()

    private func get<T>(_ key: String, _ fallback: T) -> T {
        (UserDefaults.standard.object(forKey: key) as? T) ?? fallback
    }
    private func set(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }

    var accent: AccentColorOption {
        get { AccentColorOption(rawValue: get("appearance.accent", "")) ?? .indigo }
        set { set("appearance.accent", newValue.rawValue) }
    }

    var glassMaterial: GlassMaterialOption {
        get { GlassMaterialOption(rawValue: get("appearance.glassMaterial", "")) ?? .thin }
        set { set("appearance.glassMaterial", newValue.rawValue) }
    }

    var sidebarStyle: SidebarStyleOption {
        get { SidebarStyleOption(rawValue: get("appearance.sidebarStyle", "")) ?? .glass }
        set { set("appearance.sidebarStyle", newValue.rawValue) }
    }

    /// Base font size for chat content (points). 13–18.
    var fontSize: Double {
        get { get("appearance.fontSize", 14.0) }
        set { set("appearance.fontSize", newValue) }
    }

    /// Reduce transparency: replace glass with a solid material (accessibility / legibility).
    var reduceTransparency: Bool {
        get { get("appearance.reduceTransparency", false) }
        set { set("appearance.reduceTransparency", newValue) }
    }

    /// Glass prominence: when false, glass effects are subtle; when true, more pronounced.
    var vividGlass: Bool {
        get { get("appearance.vividGlass", true) }
        set { set("appearance.vividGlass", newValue) }
    }

    /// Non-isolated accessor for use from `App`/`Scene` bodies that are not
    /// guaranteed to be on the main actor.
    static var currentAccentColor: Color {
        AccentColorOption(rawValue: UserDefaults.standard.string(forKey: "appearance.accent") ?? "")?.color ?? .indigo
    }

    /// Unified surface style (glass material or solid, when "Reduce Transparency"
    /// is on) as `AnyShapeStyle` so it can be used in `background`/`fill`/`containerBackground`.
    var surfaceStyle: AnyShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
            : AnyShapeStyle(glassMaterial.material)
    }

    /// Restores all appearance settings to their factory defaults.
    func resetToDefaults() {
        accent = .indigo
        glassMaterial = .thin
        sidebarStyle = .glass
        fontSize = 14.0
        reduceTransparency = false
        vividGlass = true
    }
}

// MARK: - Glass Modifiers

extension View {
    /// Applies the user's chosen glass material as a background. Falls back to a
    /// solid material when "Reduce Transparency" is enabled.
    @MainActor
    func coreAIGlass() -> some View {
        let settings = AppearanceSettings.shared
        let material = settings.reduceTransparency ? Material.regularMaterial : settings.glassMaterial.material
        return self.background(material)
    }

    /// A glass panel with optional interactive glass effect and corner radius.
    @MainActor
    func coreAIPanel(cornerRadius: CGFloat = 12) -> some View {
        let settings = AppearanceSettings.shared
        let material = settings.reduceTransparency ? Material.regularMaterial : settings.glassMaterial.material
        return self
            .padding(10)
            .background(material)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(settings.vividGlass ? 0.18 : 0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(settings.vividGlass ? 0.18 : 0.08), radius: settings.vividGlass ? 10 : 4, y: 2)
    }

    /// Accent color derived from the user's appearance setting.
    @MainActor
    func coreAIAccent() -> some View {
        self.tint(AppearanceSettings.shared.accent.color)
    }
}
