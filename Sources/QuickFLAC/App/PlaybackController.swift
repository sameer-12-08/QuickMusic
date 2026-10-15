import AppKit
import Observation

/// The glue between the audio `Player` and the `PlayQueue`.
/// Player only knows how to play ONE file; the queue only knows ORDER.
/// This class decides what "next" and "previous" mean.
@MainActor
@Observable
final class PlaybackController {
    let player = Player()
    let queue = PlayQueue()
    var errorMessage: String?      // shown in an alert by ContentView
    private(set) var artwork: NSImage?   // small thumbnail of the playing song's cover, if any

    @ObservationIgnored private var artworkTask: Task<Void, Never>?

    init() {
        // When a song ends, the player calls this closure (a closure is like a Python lambda).
        player.onFinished = { [weak self] in self?.next() }
    }

    // MARK: - Actions the UI can trigger

    /// "Play this now": slot it in right after the current song and start it,
    /// so the rest of the queue is kept.
    func playNow(_ track: Track) {
        guard let item = queue.insertNext([track]).first else { return }
        start(item)
    }

    /// Play a specific queue entry (double-click in the queue).
    func play(_ item: QueueItem) {
        start(item)
    }

    func playNext(_ tracks: [Track]) { queue.insertNext(tracks) }
    func enqueue(_ tracks: [Track]) { queue.append(tracks) }

    /// Next entry. Unplayable files (moved/deleted) are skipped. At the end of the queue, nothing happens.
    func next() {
        var candidate = queue.itemAfterCurrent()
        while let item = candidate {
            if start(item) { return }
            candidate = queue.item(after: item.id)
        }
    }

    /// Like most players: if you're more than 3 seconds in, restart the song;
    /// otherwise go to the entry above.
    func previous() {
        if player.currentTime() > 3 {
            player.seek(to: 0)
        } else if let item = queue.itemBeforeCurrent() {
            start(item)
        } else {
            player.seek(to: 0)
        }
    }

    // MARK: - Internals

    /// Fetches the cover in the background. If you skip to another song before it
    /// arrives, the old result is dropped instead of showing the wrong cover.
    private func loadArtwork(for url: URL) {
        artworkTask?.cancel()
        artwork = nil
        artworkTask = Task {
            let image = await ArtworkCache.shared.image(for: url)
            guard !Task.isCancelled, player.currentURL == url else { return }
            artwork = image
        }
    }

    /// Loads and plays one entry. Returns false (and sets an error) if the file can't be played.
    @discardableResult
    private func start(_ item: QueueItem) -> Bool {
        let track = item.track
        let label = track.artist.map { "\($0) – \(track.displayTitle)" } ?? track.displayTitle
        do {
            try player.load(track.url, title: label)
            queue.setCurrent(item.id)     // only move the cursor if loading worked
            loadArtwork(for: track.url)
            return true
        } catch {
            errorMessage = "\(track.url.lastPathComponent): \(error.localizedDescription)"
            return false
        }
    }
}
