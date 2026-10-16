import SwiftUI

/// One theme as stored in themes.json: a name plus seven hex colors.
///
/// UI roles (what each color is used for in this app):
///   background  window and list background
///   text        titles and other primary text
///   sub         secondary text: artist, times, inactive icons
///   main        the accent: playing song, buttons, sliders
///   caption     small headings and status text ("Queue · 3", "120 songs")
///   subAlt      raised surfaces: the controls bar, the search box
///   error       destructive actions (Clear)
struct Theme: Identifiable, Codable, Hashable {
    let name: String          // e.g. "serika_dark"
    let background: String
    let main: String
    let caption: String
    let text: String
    let sub: String
    let subAlt: String
    let error: String

    var id: String { name }
    var displayName: String { name.replacingOccurrences(of: "_", with: " ") }

    /// Monkeytype's default theme. Built in, so the app looks right even before
    /// you have generated themes.json.
    static let serikaDark = Theme(name: "serika_dark",
                                  background: "#323437", main: "#e2b714", caption: "#e2b714",
                                  text: "#d1d0c5", sub: "#646669", subAlt: "#2c2e31",
                                  error: "#ca4754")
}

/// The same colors, converted to SwiftUI `Color` once when a theme is chosen.
/// (Views read this; parsing hex strings on every redraw would be wasteful.)
struct Palette {
    let background: Color
    let main: Color
    let caption: Color
    let text: Color
    let sub: Color
    let subAlt: Color
    let error: Color
    let isDark: Bool       // lets us switch macOS controls to their dark/light look

    /// `accent` replaces the theme's main color (used by "match album artwork").
    init(_ theme: Theme, accent: Color? = nil) {
        background = Color(hex: theme.background)
        main = accent ?? Color(hex: theme.main)
        caption = Color(hex: theme.caption)
        text = Color(hex: theme.text)
        sub = Color(hex: theme.sub)
        subAlt = Color(hex: theme.subAlt)
        error = Color(hex: theme.error)
        // Rough brightness of the background (0 = black, 1 = white).
        let c = hexComponents(theme.background)
        isDark = (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5
    }
}

// MARK: - Passing the palette down to every view

// Swift concept: the "environment" is a bag of values that SwiftUI hands to every
// child view automatically, like a context object you don't have to pass by hand.
// A view asks for it with `@Environment(\.palette) private var palette`.
private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(.serikaDark)
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - The full list (loaded only when the picker opens)

enum ThemeCatalog {
    private struct File: Decodable {
        let source: String?
        let themes: [Theme]
    }

    /// Reads themes.json from the app's resources. Returns [] if it is missing or broken.
    static func load() -> [Theme] {
        // Inside QuickFLAC.app the file sits in Contents/Resources (Bundle.main finds it).
        // Under `swift run` it lives in SwiftPM's resource bundle (Bundle.module).
        // `??` only evaluates Bundle.module if the first lookup fails.
        let url = Bundle.main.url(forResource: "themes", withExtension: "json")
            ?? Bundle.module.url(forResource: "themes", withExtension: "json")
        guard let url,
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.themes
    }
}
