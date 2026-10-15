import Foundation
import Observation

/// Holds the theme in use and remembers it between launches.
///
/// We save the chosen theme's colors themselves (a few hundred bytes), not just its
/// name. That way launching never has to read the big themes.json; only the picker does.
@MainActor
@Observable
final class ThemeStore {
    private(set) var current: Theme
    private(set) var palette: Palette

    private static let defaultsKey = "theme.selected"   // UserDefaults = a tiny built-in settings file

    init() {
        let saved = UserDefaults.standard.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(Theme.self, from: $0) }
        let theme = saved ?? .serikaDark
        current = theme
        palette = Palette(theme)
    }

    /// Applies a theme immediately (every view re-colors) and saves it.
    func select(_ theme: Theme) {
        guard theme != current else { return }
        current = theme
        palette = Palette(theme)
        if let data = try? JSONEncoder().encode(theme) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
