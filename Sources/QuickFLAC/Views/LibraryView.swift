import SwiftUI
import AppKit

/// Search box + song list. It knows nothing about audio: when the user wants to
/// play a song it just calls `onPlay`.
struct LibraryView: View {
    let library: Library
    let nowPlaying: URL?
    let onPlay: (Track) -> Void           // double-click / Return
    let onPlayNext: ([Track]) -> Void     // context menu
    let onEnqueue: ([Track]) -> Void      // context menu and "Add all" button

    @Environment(\.palette) private var palette     // current theme colors
    @LocalState private var selection = Set<Track.ID>()

    var body: some View {
        // Lets us write `$library.query` to bind the text field to the library's search text.
        @Bindable var library = library
        let tracks = library.visibleTracks

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Search title, artist or file name", text: $library.query)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(palette.subAlt, in: RoundedRectangle(cornerRadius: 6))
                Button("Add…") { pickFilesOrFolders() }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.main)
            }
            .padding(10)

            // List only creates rows for what is on screen, so 10,000 songs stay cheap.
            List(tracks, selection: $selection) { track in
                TrackRow(track: track, isPlaying: track.url == nowPlaying)
            }
            .scrollContentBackground(.hidden)      // lets our background color show through
            // Double-click or Return on a row = play. Right-click = menu.
            .contextMenu(forSelectionType: Track.ID.self) { ids in
                if !ids.isEmpty {
                    Button("Play Next") { onPlayNext(selectedTracks(for: ids)) }
                    Button("Add to Queue") { onEnqueue(selectedTracks(for: ids)) }
                    Divider()
                    Button("Remove from Library") { library.remove(ids) }
                }
            } primaryAction: { ids in
                if let id = ids.first, let track = library.tracks.first(where: { $0.id == id }) {
                    onPlay(track)
                }
            }
            .onDeleteCommand {          // Delete key
                library.remove(selection)
                selection.removeAll()
            }
            .overlay {
                if library.tracks.isEmpty {
                    Text("Drop FLAC / WAV files or folders here,\nor click Add…")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(palette.sub)
                }
            }

            HStack {
                Text("\(tracks.count) of \(library.tracks.count) songs")
                    .font(.caption)
                    .foregroundStyle(palette.caption)
                Spacer()
                // Handy for albums: search for the album name, then queue everything shown.
                Button("Add all to Queue") { onEnqueue(tracks) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(palette.main)
                    .disabled(tracks.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    /// Looks up the selected songs, keeping library order.
    private func selectedTracks(for ids: Set<Track.ID>) -> [Track] {
        library.tracks.filter { ids.contains($0.id) }
    }

    /// One standard macOS panel that accepts several files and folders at once.
    private func pickFilesOrFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        library.add(panel.urls)
    }
}

/// One row: title on top, artist below. The playing song gets an accent color and a speaker icon.
/// (Also used by the queue.)
struct TrackRow: View {
    let track: Track
    let isPlaying: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isPlaying ? "speaker.wave.2.fill" : "music.note")
                .foregroundStyle(isPlaying ? palette.main : palette.sub)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .foregroundStyle(isPlaying ? palette.main : palette.text)
                    .lineLimit(1)
                if let artist = track.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(palette.sub)
                        .lineLimit(1)
                }
            }
        }
    }
}
