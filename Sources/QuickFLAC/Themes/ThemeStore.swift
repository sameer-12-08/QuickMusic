import SwiftUI
import AppKit
import Observation

/// Holds the theme in use and remembers it between launches.
///
/// We save the chosen theme's colors themselves (a few hundred bytes), not just its
/// name. That way launching never has to read the big themes.json; only the picker does.
///
/// "Match album artwork": while a song with a colorful cover is playing, the theme's
/// accent color (the playing song, buttons, sliders) is swapped for the cover's main color.
/// Everything else (background, text) stays the theme's, so the app never turns unreadable.
@MainActor
@Observable
final class ThemeStore {
    private(set) var current: Theme
    private(set) var palette: Palette
    private(set) var matchArtwork: Bool

    @ObservationIgnored private var artworkColor: ArtworkColor.RGB?    // from the playing song's cover

    private static let defaultsKey = "theme.selected"   // UserDefaults = a tiny built-in settings file
    private static let matchKey = "theme.matchArtwork"

    init() {
        let saved = UserDefaults.standard.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(Theme.self, from: $0) }
        let theme = saved ?? .serikaDark
        current = theme
        palette = Palette(theme)
        // On unless you turned it off. (`as? Bool` is nil if nothing was ever saved.)
        matchArtwork = UserDefaults.standard.object(forKey: Self.matchKey) as? Bool ?? true
    }

    /// Applies a theme immediately (every view re-colors) and saves it.
    func select(_ theme: Theme) {
        guard theme != current else { return }
        current = theme
        rebuildPalette(animated: false)
        if let data = try? JSONEncoder().encode(theme) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    func setMatchArtwork(_ on: Bool) {
        guard on != matchArtwork else { return }
        matchArtwork = on
        UserDefaults.standard.set(on, forKey: Self.matchKey)
        rebuildPalette(animated: true)
    }

    /// Called whenever the playing song's cover changes (nil = this song has no cover).
    func artworkChanged(_ image: NSImage?) {
        artworkColor = image.flatMap { ArtworkColor.dominant(from: $0) }
        rebuildPalette(animated: true)
    }

    private func rebuildPalette(animated: Bool) {
        var accent: Color?
        if matchArtwork, let color = artworkColor {
            let bg = hexComponents(current.background)
            let readable = ArtworkColor.ensureContrast(color, against: (bg.r, bg.g, bg.b))
            accent = Color(.sRGB, red: readable.r, green: readable.g, blue: readable.b, opacity: 1)
        }
        let new = Palette(current, accent: accent)
        if animated {
            withAnimation(.easeInOut(duration: 0.4)) { palette = new }    // colors fade between songs
        } else {
            palette = new
        }
    }
}
