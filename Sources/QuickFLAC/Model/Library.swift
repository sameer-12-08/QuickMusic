import Foundation
import AppKit
import Observation

/// The list of all songs the user has added, plus the current search text.
///
/// Swift concept: `@MainActor` means "only touch this from the main (UI) thread".
/// The compiler enforces it, which prevents the thread bugs you'd otherwise get when
/// background work (folder scanning, tag reading) updates data the UI is showing.
@MainActor
@Observable
final class Library {

    private(set) var tracks: [Track] = []
    var query = ""   // bound to the search box
    /// Goes up by one every time something (the "/" key, Cmd+F) asks for the search box to
    /// be focused. The search field watches this number and grabs focus when it changes.
    private(set) var searchFocusToken = 0

    func focusSearch() { searchFocusToken += 1 }

    /// The folder that holds your music. Everything inside it is added at launch and on "Rescan".
    private(set) var musicFolder: URL?
    private(set) var isScanning = false
    private static let folderKey = "library.musicFolder"

    @ObservationIgnored private var metadataTask: Task<Void, Never>?
    @ObservationIgnored private let saveURL: URL

    init() {
        // ~/Library/Application Support/QuickFLAC/library.json
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent("QuickFLAC", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        saveURL = folder.appendingPathComponent("library.json")
        if let path = UserDefaults.standard.string(forKey: Self.folderKey) {
            musicFolder = URL(fileURLWithPath: path, isDirectory: true)
        }
        load()
        // Pick up songs that were added to (or deleted from) the folder since last time.
        if musicFolder != nil { Task { await rescanMusicFolder() } }
    }

    // MARK: - Search

    /// Tracks matching the search box. Every typed word must appear somewhere in the
    /// title, artist, album or file name, so "dark side pink" finds "Pink Floyd - Dark Side...".
    var visibleTracks: [Track] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return tracks }
        return tracks.filter { track in
            words.allSatisfy { track.searchKey.contains($0) }
        }
    }

    // MARK: - Adding and removing

    /// Adds files and/or folders (folders are scanned recursively for .flac and .wav).
    /// With `asAlbum`, every song found is put into one album with that name, whatever its tags say.
    func add(_ urls: [URL], asAlbum albumName: String? = nil) {
        Task { await addAndWait(urls, asAlbum: albumName) }
    }

    /// Same as add(), but you can `await` it, and it returns the library entries for
    /// everything that was requested (including songs that were already in the library),
    /// in order. Used when you open files from Finder, so we can start playing them.
    @discardableResult
    func addAndWait(_ urls: [URL], asAlbum albumName: String? = nil) async -> [Track] {
        // Scan on a background thread so a big folder never freezes the window.
        let found = await Task.detached(priority: .userInitiated) {
            Library.scan(urls)
        }.value

        // Back on the main thread. Map path -> position once, instead of searching per song.
        var position: [String: Int] = [:]
        for (i, track) in tracks.enumerated() { position[track.url.path] = i }

        var changed = false
        var addedNew = false
        for url in found {
            if let i = position[url.path] {
                // Already in the library: only re-label it if "Folder as Album" was used.
                if let albumName, tracks[i].albumOverride != albumName {
                    tracks[i].setAlbumOverride(albumName)
                    changed = true
                }
            } else {
                var track = Track(url: url)
                if let albumName { track.setAlbumOverride(albumName) }
                tracks.append(track)
                position[url.path] = tracks.count - 1
                changed = true
                addedNew = true
            }
        }
        if changed { save() }
        if addedNew { loadMissingMetadata() }

        // Look up the entries for what was asked for, keeping the order.
        var byPath: [String: Track] = [:]
        for track in tracks { byPath[track.url.path] = track }
        return found.compactMap { byPath[$0.path] }
    }

    /// Called by PlaybackController when a song has been played long enough to count.
    func incrementPlayCount(_ id: Track.ID) {
        guard let i = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[i].playCount += 1
        save()
    }

    func remove(_ ids: Set<Track.ID>) {
        tracks.removeAll { ids.contains($0.id) }
        save()
    }

    // MARK: - Music folder

    /// Asks you for the folder, remembers it, and scans it.
    func chooseMusicFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder that holds your music. QuickFLAC adds everything inside it, now and each time it opens."
        panel.directoryURL = musicFolder ?? FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setMusicFolder(url)
    }

    func setMusicFolder(_ url: URL) {
        musicFolder = url
        UserDefaults.standard.set(url.path, forKey: Self.folderKey)
        Task { await rescanMusicFolder() }
    }

    /// Adds new songs found in the music folder, and drops songs whose files were deleted.
    func rescanMusicFolder() async {
        guard let folder = musicFolder, !isScanning else { return }
        // If the folder is not there (an external drive that is unplugged), do nothing.
        // Otherwise every song on it would look "deleted" and be removed from the library.
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        isScanning = true
        defer { isScanning = false }

        await addAndWait([folder])

        let prefix = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
        let candidates = tracks.filter { $0.url.path.hasPrefix(prefix) }.map { ($0.id, $0.url.path) }
        let gone = await Task.detached(priority: .utility) {
            candidates.filter { !FileManager.default.fileExists(atPath: $0.1) }.map { $0.0 }
        }.value
        if !gone.isEmpty { remove(Set(gone)) }
    }

    /// Finds all .flac/.wav files in the given files and folders.
    /// `nonisolated` = allowed to run off the main thread (it touches no library state).
    nonisolated static func scan(_ urls: [URL]) -> [URL] {
        let allowed: Set<String> = ["flac", "wav"]
        var result: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                var inFolder: [URL] = []
                if let walker = FileManager.default.enumerator(at: url,
                                                               includingPropertiesForKeys: nil,
                                                               options: [.skipsHiddenFiles]) {
                    for case let fileURL as URL in walker
                    where allowed.contains(fileURL.pathExtension.lowercased()) {
                        inFolder.append(fileURL)
                    }
                }
                // "Track 2" before "Track 10", like Finder does.
                inFolder.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                result += inFolder
            } else if allowed.contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }
        return result
    }

    // MARK: - Lazy metadata

    /// Reads tags for tracks that don't have them yet, in the background, a few
    /// files at a time. We keep only two short strings per song (never artwork),
    /// and the results are saved, so the next launch doesn't re-read anything.
    private func loadMissingMetadata() {
        let pending = tracks.filter { $0.needsMetadata }.map { ($0.id, $0.url) }
        guard !pending.isEmpty else { return }

        metadataTask?.cancel()
        metadataTask = Task.detached(priority: .utility) { [weak self] in
            var batch: [(UUID, TrackMetadata)] = []
            for (id, url) in pending {
                if Task.isCancelled { return }
                batch.append((id, await MetadataReader.read(url)))
                if batch.count >= 50 {              // update the UI in chunks, not per song
                    await self?.applyMetadata(batch)
                    batch.removeAll()
                }
            }
            await self?.applyMetadata(batch)
            await self?.save()
        }
    }

    private func applyMetadata(_ batch: [(UUID, TrackMetadata)]) {
        guard !batch.isEmpty else { return }
        // Map id -> position once, instead of searching the array for every song.
        var index: [UUID: Int] = [:]
        for (position, track) in tracks.enumerated() { index[track.id] = position }
        for (id, meta) in batch {
            if let position = index[id] { tracks[position].apply(meta) }
        }
    }

    // MARK: - Saving and loading

    private func save() {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let saved = try? JSONDecoder().decode([Track].self, from: data) else { return }
        tracks = saved
        loadMissingMetadata()   // finishes any tag reading that was interrupted last time
    }
}
