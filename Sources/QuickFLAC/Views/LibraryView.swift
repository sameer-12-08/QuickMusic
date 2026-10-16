import SwiftUI
import AppKit

/// Search box + the current page of the library (songs, albums, artists, folders or
/// most played). Playing things goes through `playback`; this view knows nothing about audio.
struct LibraryView: View {
    let library: Library
    let playback: PlaybackController
    let section: LibrarySection

    @Environment(\.palette) private var palette     // current theme colors
    @FocusState private var searchFocused: Bool     // is the cursor in the search box?

    var body: some View {
        // Lets us write `$library.query` to bind the text field to the library's search text.
        @Bindable var library = library
        // The search box filters every page, so work out the matching songs once.
        let visible = library.visibleTracks

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Search title, artist, album or file name", text: $library.query)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(palette.subAlt, in: RoundedRectangle(cornerRadius: 6))
                    .focused($searchFocused)
                    // Esc: clear the search and give the keyboard back to the window.
                    .onExitCommand {
                        library.query = ""
                        searchFocused = false
                    }
                Menu {
                    Button("Files or Folders…") { pickFilesOrFolders() }
                    Button("Folder as Album…") { pickAlbumFolders() }
                    Divider()
                    Button("Set Music Folder…") { library.chooseMusicFolder() }
                    Button("Rescan Music Folder") { Task { await library.rescanMusicFolder() } }
                        .disabled(library.musicFolder == nil)
                } label: {
                    Text("Add…").foregroundStyle(palette.main)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(10)

            if library.tracks.isEmpty && library.musicFolder == nil {
                welcome
            } else {
                content(visible)
            }

            HStack {
                Text(library.isScanning ? "Scanning music folder…"
                                        : "\(visible.count) of \(library.tracks.count) songs")
                    .font(.caption)
                    .foregroundStyle(palette.caption)
                Spacer()
                if section == .songs {
                    // Handy for albums: search for the album name, then queue everything shown.
                    Button("Add all to Queue") { playback.enqueue(visible) }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(palette.main)
                        .disabled(visible.isEmpty)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        // "/" and Cmd+F bump this number; we answer by moving the cursor into the search box.
        .onChange(of: library.searchFocusToken) { _, _ in
            searchFocused = true
        }
    }

    /// Shown on first launch, before there is any music.
    private var welcome: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(palette.sub)
            Text("Choose your music folder")
                .font(.headline)
            Text("QuickFLAC adds every FLAC and WAV inside it, and picks up new files each time it opens.")
                .font(.callout)
                .foregroundStyle(palette.sub)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("Choose Music Folder…") { library.chooseMusicFolder() }
            Text("or drop files and folders here")
                .font(.caption)
                .foregroundStyle(palette.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The page for the selected sidebar item.
    @ViewBuilder
    private func content(_ visible: [Track]) -> some View {
        let nowPlaying = playback.player.currentURL
        let noMatches = library.tracks.isEmpty
            ? "Drop FLAC / WAV files or folders here,\nor click Add…"
            : "Nothing matches your search."

        switch section {
        case .songs:
            TrackListView(library: library, tracks: visible, nowPlaying: nowPlaying,
                          emptyText: noMatches,
                          onPlay: playback.playNow,
                          onPlayNext: playback.playNext,
                          onEnqueue: playback.enqueue)

        case .mostPlayed:
            let top = visible.filter { $0.playCount > 0 }
                             .sorted { $0.playCount > $1.playCount }
            TrackListView(library: library, tracks: Array(top.prefix(100)), nowPlaying: nowPlaying,
                          showPlayCount: true,
                          emptyText: "Songs you listen to will show up here.",
                          onPlay: playback.playNow,
                          onPlayNext: playback.playNext,
                          onEnqueue: playback.enqueue)

        case .albums:
            GroupBrowser(library: library, playback: playback, nowPlaying: nowPlaying,
                         groups: TrackGroup.albums(from: visible), emptyText: noMatches,
                         placeholderIcon: "square.stack")

        case .artists:
            GroupBrowser(library: library, playback: playback, nowPlaying: nowPlaying,
                         groups: TrackGroup.artists(from: visible), emptyText: noMatches,
                         placeholderIcon: "music.mic")

        case .folders:
            GroupBrowser(library: library, playback: playback, nowPlaying: nowPlaying,
                         groups: TrackGroup.folders(from: visible), emptyText: noMatches,
                         placeholderIcon: "folder")
        }
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

    /// Each folder you choose becomes one album (named after the folder), whatever its tags say.
    private func pickAlbumFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose one or more folders. Each folder becomes one album."
        guard panel.runModal() == .OK else { return }
        for folder in panel.urls {
            library.add([folder], asAlbum: folder.lastPathComponent)
        }
    }
}

/// A plain list of songs: double-click or Return plays, right-click opens the menu.
struct TrackListView: View {
    let library: Library
    let tracks: [Track]
    let nowPlaying: URL?
    var showPlayCount = false
    let emptyText: String
    let onPlay: (Track) -> Void           // double-click / Return
    let onPlayNext: ([Track]) -> Void     // context menu
    let onEnqueue: ([Track]) -> Void      // context menu

    @Environment(\.palette) private var palette
    @LocalState private var selection = Set<Track.ID>()

    var body: some View {
        // List only creates rows for what is on screen, so 10,000 songs stay cheap.
        List(tracks, selection: $selection) { track in
            TrackRow(track: track, isPlaying: track.url == nowPlaying, showPlayCount: showPlayCount)
        }
        .scrollContentBackground(.hidden)      // lets our background color show through
        .contextMenu(forSelectionType: Track.ID.self) { ids in
            if !ids.isEmpty {
                Button("Play Next") { onPlayNext(selectedTracks(for: ids)) }
                Button("Add to Queue") { onEnqueue(selectedTracks(for: ids)) }
                Divider()
                Button("Remove from Library") { library.remove(ids) }
            }
        } primaryAction: { ids in
            if let id = ids.first, let track = tracks.first(where: { $0.id == id }) {
                onPlay(track)
            }
        }
        .onDeleteCommand {          // Delete key
            library.remove(selection)
            selection.removeAll()
        }
        .overlay {
            if tracks.isEmpty {
                Text(emptyText)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.sub)
            }
        }
    }

    /// Looks up the selected songs, keeping the order they are shown in.
    private func selectedTracks(for ids: Set<Track.ID>) -> [Track] {
        tracks.filter { ids.contains($0.id) }
    }
}

/// Albums, Artists and Folders pages: first the groups, shown as an icon grid (like Finder's
/// icon view) or as a list; click one to open it and see its songs. Playing a song from an
/// open group queues the WHOLE group as one block, starting at that song, so next/previous
/// stay inside the album.
struct GroupBrowser: View {
    let library: Library
    let playback: PlaybackController
    let nowPlaying: URL?
    let groups: [TrackGroup]
    let emptyText: String
    let placeholderIcon: String        // shown in the grid when a group has no cover

    @Environment(\.palette) private var palette
    @LocalState private var openID: String?      // id of the group being viewed, if any
    // @AppStorage = a variable that is saved in UserDefaults, so the choice survives restarts.
    @AppStorage("library.iconView") private var iconView = true

    var body: some View {
        if let openID, let group = groups.first(where: { $0.id == openID }) {
            detail(group)
        } else {
            groupPage
        }
    }

    private var groupPage: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Picker("View", selection: $iconView) {
                    Image(systemName: "square.grid.2x2").tag(true)
                    Image(systemName: "list.bullet").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 84)
                .help("Show items as icons or as a list")
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)

            if iconView { groupGrid } else { groupRows }
        }
        .overlay {
            if groups.isEmpty {
                Text(emptyText)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.sub)
            }
        }
    }

    private func groupMenu(_ group: TrackGroup) -> some View {
        Group {
            Button("Play") { playback.playGroup(group.tracks) }
            Button("Play Next") { playback.playNextGroup(group.tracks) }
            Button("Add to Queue") { playback.enqueueGroup(group.tracks) }
        }
    }

    /// Icon view: a grid of covers. LazyVGrid only builds the tiles that are on screen,
    /// and each tile loads its cover only when it appears.
    private var groupGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 180), spacing: 18)],
                      spacing: 18) {
                ForEach(groups) { group in
                    GroupTile(group: group, placeholderIcon: placeholderIcon) { openID = group.id }
                        .contextMenu { groupMenu(group) }
                }
            }
            .padding(14)
        }
    }

    private var groupRows: some View {
        List(groups) { group in
            Button {
                openID = group.id
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title).lineLimit(1)
                    Text(group.subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.sub)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())      // makes the empty part of the row clickable too
            }
            .buttonStyle(.plain)
            .contextMenu { groupMenu(group) }
        }
        .scrollContentBackground(.hidden)
    }

    private func detail(_ group: TrackGroup) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { openID = nil } label: { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.main)
                Spacer()
                Text(group.title)
                    .font(.headline)
                    .foregroundStyle(palette.caption)
                    .lineLimit(1)
                Spacer()
                Button("Play") { playback.playGroup(group.tracks) }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.main)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            TrackListView(library: library, tracks: group.tracks, nowPlaying: nowPlaying,
                          emptyText: "",
                          onPlay: { playback.playGroup(group.tracks, startAt: $0) },
                          onPlayNext: playback.playNext,
                          onEnqueue: playback.enqueue)
        }
    }
}

/// One tile of the icon grid: cover on top, name and details below.
struct GroupTile: View {
    let group: TrackGroup
    let placeholderIcon: String
    let onOpen: () -> Void

    @Environment(\.palette) private var palette
    @LocalState private var cover: NSImage?

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                // Color.clear + aspectRatio gives an exact square; the cover is drawn on top and clipped.
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .background(palette.subAlt)
                    .overlay {
                        if let cover {
                            Image(nsImage: cover).resizable().scaledToFill()
                        } else {
                            Image(systemName: placeholderIcon)
                                .font(.system(size: 36))
                                .foregroundStyle(palette.sub)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(group.title)
                    .font(.callout)
                    .lineLimit(1)
                Text(group.subtitle)
                    .font(.caption)
                    .foregroundStyle(palette.sub)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Runs when the tile appears (scrolled into view), not for the whole library at once.
        .task(id: group.id) {
            guard let url = group.tracks.first?.url else { return }
            cover = await ArtworkCache.shared.image(for: url)
        }
    }
}

/// One row: title on top, artist below. The playing song gets an accent color and a speaker icon.
/// (Also used by the queue.)
struct TrackRow: View {
    let track: Track
    let isPlaying: Bool
    var showPlayCount = false
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
            if showPlayCount {
                Spacer()
                Text("\(track.playCount)×")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(palette.caption)
            }
        }
    }
}
