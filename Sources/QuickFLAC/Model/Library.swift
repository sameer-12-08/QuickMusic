import Foundation
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

    @ObservationIgnored private var metadataTask: Task<Void, Never>?
    @ObservationIgnored private let saveURL: URL

    init() {
        // ~/Library/Application Support/QuickFLAC/library.json
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent("QuickFLAC", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        saveURL = folder.appendingPathComponent("library.json")
        load()
    }

    // MARK: - Search

    /// Tracks matching the search box. Every typed word must appear somewhere in the
    /// title, artist or file name, so "dark side pink" finds "Pink Floyd - Dark Side...".
    var visibleTracks: [Track] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return tracks }
        return tracks.filter { track in
            words.allSatisfy { track.searchKey.contains($0) }
        }
    }

    // MARK: - Adding and removing

    /// Adds files and/or folders (folders are scanned recursively for .flac and .wav).
    func add(_ urls: [URL]) {
        Task { await addAndWait(urls) }
    }

    /// Same as add(), but you can `await` it, and it returns the library entries for
    /// everything that was requested (including songs that were already in the library),
    /// in order. Used when you open files from Finder, so we can start playing them.
    @discardableResult
    func addAndWait(_ urls: [URL]) async -> [Track] {
        // Scan on a background thread so a big folder never freezes the window.
        let found = await Task.detached(priority: .userInitiated) {
            Library.scan(urls)
        }.value

        // Back on the main thread: skip files we already have.
        var known = Set(tracks.map { $0.url.path })
        var newTracks: [Track] = []
        for url in found where known.insert(url.path).inserted {
            newTracks.append(Track(url: url))
        }
        if !newTracks.isEmpty {
            tracks.append(contentsOf: newTracks)
            save()
            loadMissingMetadata()
        }

        // Look up the entries for what was asked for, keeping the order.
        var byPath: [String: Track] = [:]
        for track in tracks { byPath[track.url.path] = track }
        return found.compactMap { byPath[$0.path] }
    }

    func remove(_ ids: Set<Track.ID>) {
        tracks.removeAll { ids.contains($0.id) }
        save()
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
        let pending = tracks.filter { !$0.metadataLoaded }.map { ($0.id, $0.url) }
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
