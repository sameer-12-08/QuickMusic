import Foundation

/// Tags we read from a file. Everything can be missing.
struct TrackMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var trackNumber: Int?
    var discNumber: Int?
}

/// One song in the library.
///
/// Swift concept: a `struct` is a value type, like a Python dataclass that is copied
/// when assigned. `Codable` means it can be turned into JSON and back automatically
/// (like dataclasses + json, but generated for you).
struct Track: Identifiable, Codable, Hashable {
    /// Bump this when the app starts reading more tags. Songs saved with an older
    /// number get their tags re-read once, in the background, at the next launch.
    static let currentMetaVersion = 2

    let id: UUID
    let url: URL
    var title: String?
    var artist: String?
    var album: String?              // the ALBUM tag
    var trackNumber: Int?
    var discNumber: Int?
    /// Set when you use "Folder as Album…": this name wins over the tag.
    var albumOverride: String?
    var playCount = 0
    var metaVersion = 0
    /// Lowercased "title artist album filename", built once so searching is a cheap string check.
    var searchKey: String

    /// Which fields go into library.json. `searchKey` is left out on purpose: it is
    /// rebuilt from the other fields when loading, which keeps the file smaller
    /// and the launch faster.
    private enum CodingKeys: String, CodingKey {
        case id, url, title, artist, album, trackNumber, discNumber
        case albumOverride, playCount, metaVersion
    }

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.searchKey = Track.makeKey(url: url, title: nil, artist: nil, album: nil)
    }

    /// Custom "read from JSON" (like writing your own `from_dict` in Python).
    /// `decodeIfPresent` = "use None if the key is missing", so an old library.json still loads.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let url = try container.decode(URL.self, forKey: .url)
        let title = try container.decodeIfPresent(String.self, forKey: .title)
        let artist = try container.decodeIfPresent(String.self, forKey: .artist)
        let album = try container.decodeIfPresent(String.self, forKey: .album)
        let override = try container.decodeIfPresent(String.self, forKey: .albumOverride)
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.trackNumber = try container.decodeIfPresent(Int.self, forKey: .trackNumber)
        self.discNumber = try container.decodeIfPresent(Int.self, forKey: .discNumber)
        self.albumOverride = override
        self.playCount = try container.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
        self.metaVersion = try container.decodeIfPresent(Int.self, forKey: .metaVersion) ?? 0
        self.searchKey = Track.makeKey(url: url, title: title, artist: artist, album: override ?? album)
    }

    // MARK: - Names the UI shows

    /// What the list shows: the tag title, or the file name if there is no tag.
    var displayTitle: String {
        title ?? url.deletingPathExtension().lastPathComponent
    }

    var artistName: String { artist ?? "Unknown Artist" }

    var folderURL: URL { url.deletingLastPathComponent() }
    var folderName: String { folderURL.lastPathComponent }

    /// Album shown in the UI: your "Folder as Album" name, else the tag, else the folder name.
    var albumName: String { albumOverride ?? album ?? folderName }

    /// True until the newer tags (album, track number) have been read for this song.
    var needsMetadata: Bool { metaVersion < Track.currentMetaVersion }

    /// What decides which songs belong to the same album. Songs with an album name
    /// (tag or override) group by that name; songs without one group by folder.
    var albumKey: String {
        (albumOverride ?? album)?.lowercased() ?? ("folder:" + folderURL.path)
    }

    // MARK: - Changing a track

    /// Called when background tag reading finishes for this track.
    mutating func apply(_ meta: TrackMetadata) {
        title = meta.title
        artist = meta.artist
        album = meta.album
        trackNumber = meta.trackNumber
        discNumber = meta.discNumber
        metaVersion = Track.currentMetaVersion
        searchKey = Track.makeKey(url: url, title: title, artist: artist, album: albumOverride ?? album)
    }

    mutating func setAlbumOverride(_ name: String?) {
        albumOverride = name
        searchKey = Track.makeKey(url: url, title: title, artist: artist, album: albumOverride ?? album)
    }

    // MARK: - Ordering inside an album

    /// Disc, then folder (for CD1/CD2 subfolders), then track number, then file name.
    static func albumOrder(_ a: Track, _ b: Track) -> Bool {
        let discA = a.discNumber ?? 0, discB = b.discNumber ?? 0
        if discA != discB { return discA < discB }
        let folder = a.folderURL.path.localizedStandardCompare(b.folderURL.path)
        if folder != .orderedSame { return folder == .orderedAscending }
        let numA = a.trackNumber ?? Int.max, numB = b.trackNumber ?? Int.max
        if numA != numB { return numA < numB }
        return a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
    }

    private static func makeKey(url: URL, title: String?, artist: String?, album: String?) -> String {
        [title, artist, album, url.lastPathComponent]
            .compactMap { $0 }          // drop the nils, like [x for x in ... if x is not None]
            .joined(separator: " ")
            .lowercased()
    }
}
