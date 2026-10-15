import Foundation

/// Tags we read from a file. Both can be missing.
struct TrackMetadata {
    var title: String?
    var artist: String?
}

/// One song in the library.
///
/// Swift concept: a `struct` is a value type, like a Python dataclass that is copied
/// when assigned. `Codable` means it can be turned into JSON and back automatically
/// (like dataclasses + json, but generated for you).
struct Track: Identifiable, Codable, Hashable {
    let id: UUID
    let url: URL
    var title: String?
    var artist: String?
    var metadataLoaded = false
    /// Lowercased "title artist filename", built once so searching is a cheap string check.
    var searchKey: String

    /// Which fields go into library.json. `searchKey` is left out on purpose: it is
    /// rebuilt from the other fields when loading, which keeps the file smaller
    /// and the launch faster.
    private enum CodingKeys: String, CodingKey {
        case id, url, title, artist, metadataLoaded
    }

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.searchKey = Track.makeKey(url: url, title: nil, artist: nil)
    }

    /// Custom "read from JSON" (like writing your own `from_dict` in Python).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let url = try container.decode(URL.self, forKey: .url)
        let title = try container.decodeIfPresent(String.self, forKey: .title)
        let artist = try container.decodeIfPresent(String.self, forKey: .artist)
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.metadataLoaded = try container.decodeIfPresent(Bool.self, forKey: .metadataLoaded) ?? false
        self.searchKey = Track.makeKey(url: url, title: title, artist: artist)
    }

    /// What the list shows: the tag title, or the file name if there is no tag.
    var displayTitle: String {
        title ?? url.deletingPathExtension().lastPathComponent
    }

    /// Called when background tag reading finishes for this track.
    mutating func apply(_ meta: TrackMetadata) {
        title = meta.title
        artist = meta.artist
        metadataLoaded = true
        searchKey = Track.makeKey(url: url, title: meta.title, artist: meta.artist)
    }

    private static func makeKey(url: URL, title: String?, artist: String?) -> String {
        [title, artist, url.lastPathComponent]
            .compactMap { $0 }          // drop the nils, like [x for x in ... if x is not None]
            .joined(separator: " ")
            .lowercased()
    }
}
