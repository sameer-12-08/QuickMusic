import SwiftUI

/// Popover with every theme. Click one (or move with the arrow keys) and the whole
/// app re-colors immediately, so browsing IS the live preview. The choice is saved
/// as you go; to go back, just click your old theme again.
struct ThemePicker: View {
    let store: ThemeStore

    // The full list lives only in this view's state, so it is loaded when the
    // popover opens and freed when it closes.
    @LocalState private var all: [Theme] = []
    @LocalState private var query = ""
    @LocalState private var selection: String?     // theme name

    private var filtered: [Theme] {
        let q = query.lowercased()
        return q.isEmpty ? all : all.filter { $0.name.contains(q.replacingOccurrences(of: " ", with: "_")) }
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search themes", text: $query)
                .textFieldStyle(.roundedBorder)

            if all.isEmpty {
                Text("No themes found.\nRun Tools/convert_themes.py to generate themes.json, then rebuild.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            } else {
                List(filtered, selection: $selection) { theme in
                    ThemeRow(theme: theme)
                }
            }
        }
        .padding(10)
        .frame(width: 280, height: 380)
        .onAppear {
            all = ThemeCatalog.load()
            selection = store.current.name
        }
        .onChange(of: selection) { _, name in
            if let theme = all.first(where: { $0.name == name }) {
                store.select(theme)
            }
        }
    }
}

/// Theme name plus four little color dots (background, main, text, sub).
struct ThemeRow: View {
    let theme: Theme

    var body: some View {
        HStack {
            Text(theme.displayName).lineLimit(1)
            Spacer()
            HStack(spacing: 3) {
                dot(theme.background)
                dot(theme.main)
                dot(theme.text)
                dot(theme.sub)
            }
        }
    }

    private func dot(_ hex: String) -> some View {
        Circle()
            .fill(Color(hex: hex))
            .overlay(Circle().stroke(.secondary.opacity(0.5), lineWidth: 0.5))
            .frame(width: 12, height: 12)
    }
}
