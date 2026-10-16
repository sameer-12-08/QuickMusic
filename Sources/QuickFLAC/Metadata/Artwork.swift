import AppKit
import ImageIO

/// Finds cover art for a song and shrinks it to a small thumbnail.
///
/// Memory rules: this runs only for the song that is playing (never for the whole
/// library), and the original image is thrown away right after the thumbnail is made.
/// A 3000x3000 cover would cost ~36 MB decoded; a 160 px thumbnail costs ~100 KB.
///
/// Where we look:
///   1. FLAC files: the picture embedded in the file's header (block type 6).
///   2. Any file: cover.jpg / folder.png / front.jpg ... in the same folder.
enum ArtworkLoader {
    static let maxPixels = 160                 // longest side of the thumbnail, in pixels
    private static let maxEmbeddedBytes = 12_000_000   // ignore absurdly large embedded pictures

    /// `maxPixels` defaults to the small thumbnail size; the full-screen player asks for more.
    static func load(for url: URL, maxPixels: Int = ArtworkLoader.maxPixels) -> NSImage? {
        if url.pathExtension.lowercased() == "flac",
           let data = embeddedFLACPicture(url),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = thumbnail(from: source, maxPixels: maxPixels) {
            return image
        }
        return folderArtwork(near: url, maxPixels: maxPixels)
    }

    // MARK: - Shrinking

    /// ImageIO can decode straight to a small size, so the full-size bitmap is never built.
    private static func thumbnail(from source: CGImageSource, maxPixels: Int) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,     // respect rotation
            kCGImageSourceShouldCacheImmediately: true,           // decode now, not lazily
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    // MARK: - Folder art

    private static func folderArtwork(near url: URL, maxPixels: Int) -> NSImage? {
        let folder = url.deletingLastPathComponent()
        for name in ["cover", "folder", "front", "album", "artwork"] {
            for ext in ["jpg", "jpeg", "png"] {
                let candidate = folder.appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: candidate.path),
                   let source = CGImageSourceCreateWithURL(candidate as CFURL, nil),
                   let image = thumbnail(from: source, maxPixels: maxPixels) {
                    return image
                }
            }
        }
        return nil
    }

    // MARK: - FLAC embedded picture

    /// Walks the FLAC header blocks (same idea as MetadataReader) looking for a
    /// PICTURE block (type 6). Prefers the "front cover" picture (type 3).
    private static func embeddedFLACPicture(_ url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let magic = try? handle.read(upToCount: 4), magic == Data("fLaC".utf8) else { return nil }

        var fallback: Data?     // first picture that isn't a front cover
        while true {
            guard let headerData = try? handle.read(upToCount: 4), headerData.count == 4 else { break }
            let header = [UInt8](headerData)
            let isLast = (header[0] & 0x80) != 0
            let type = header[0] & 0x7F
            let length = (Int(header[1]) << 16) | (Int(header[2]) << 8) | Int(header[3])

            if type == 6 && length < maxEmbeddedBytes {
                guard let body = try? handle.read(upToCount: length), body.count == length else { break }
                if let picture = parsePicture([UInt8](body)) {
                    if picture.kind == 3 { return picture.image }     // 3 = front cover
                    if fallback == nil { fallback = picture.image }
                }
            } else {
                // Not a picture: jump over it without reading it.
                guard let position = try? handle.offset() else { break }
                do { try handle.seek(toOffset: position + UInt64(length)) } catch { break }
            }
            if isLast { break }
        }
        return fallback
    }

    /// PICTURE block layout (all numbers 4 bytes, BIG-endian this time):
    /// kind, mime length + mime, description length + description,
    /// width, height, depth, colors, data length + the image bytes.
    private static func parsePicture(_ bytes: [UInt8]) -> (kind: Int, image: Data)? {
        var pos = 0

        func readUInt32() -> Int? {
            guard pos + 4 <= bytes.count else { return nil }
            var value = 0
            for i in 0..<4 { value = (value << 8) | Int(bytes[pos + i]) }
            pos += 4
            return value
        }

        guard let kind = readUInt32(),
              let mimeLength = readUInt32(), pos + mimeLength <= bytes.count else { return nil }
        pos += mimeLength
        guard let descriptionLength = readUInt32(), pos + descriptionLength <= bytes.count else { return nil }
        pos += descriptionLength
        guard pos + 16 <= bytes.count else { return nil }
        pos += 16                                   // width, height, depth, colors: not needed
        guard let dataLength = readUInt32(), pos + dataLength <= bytes.count else { return nil }
        return (kind, Data(bytes[pos..<(pos + dataLength)]))
    }
}

/// Remembers the recent thumbnails (so going back a song is instant) and
/// forgets them automatically if the system needs memory.
final class ArtworkCache {
    static let shared = ArtworkCache()

    private let cache = NSCache<NSURL, NSImage>()     // NSCache = a dict that evicts itself
    private init() { cache.countLimit = 60 }          // 60 x ~100 KB = about 6 MB at most (the icon grid shows many covers)

    /// Returns the cached thumbnail, or loads it on a background thread.
    func image(for url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let loaded = await Task.detached(priority: .utility) { ArtworkLoader.load(for: url) }.value
        if let loaded { cache.setObject(loaded, forKey: url as NSURL) }
        return loaded
    }
}
