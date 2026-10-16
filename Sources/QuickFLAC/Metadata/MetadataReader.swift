import Foundation
import AVFoundation

/// Reads title, artist, album and track/disc numbers from a file's tags.
///
/// FLAC: we read the file's header ourselves. A FLAC file starts with the bytes "fLaC",
/// then a chain of small metadata blocks. Block type 4 holds "KEY=value" text tags
/// (Vorbis comments). We only read those few bytes, never the audio.
/// I do this instead of trusting AVFoundation to expose FLAC tags, which I'm not sure it does.
///
/// WAV (and anything else): ask AVFoundation for its common metadata.
enum MetadataReader {

    static func read(_ url: URL) async -> TrackMetadata {
        if url.pathExtension.lowercased() == "flac" {
            return readFLAC(url)
        }
        return await readWithAVFoundation(url)
    }

    // MARK: - FLAC

    private static func readFLAC(_ url: URL) -> TrackMetadata {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return TrackMetadata() }
        defer { try? handle.close() }

        // Every FLAC file begins with the 4 bytes "fLaC".
        guard let magic = try? handle.read(upToCount: 4), magic == Data("fLaC".utf8) else {
            return TrackMetadata()
        }

        while true {
            // Each block has a 4-byte header: 1 byte (last-block flag + type), 3 bytes length.
            guard let headerData = try? handle.read(upToCount: 4), headerData.count == 4 else { break }
            let header = [UInt8](headerData)
            let isLast = (header[0] & 0x80) != 0
            let type = header[0] & 0x7F
            let length = (Int(header[1]) << 16) | (Int(header[2]) << 8) | Int(header[3])

            if type == 4 {   // VORBIS_COMMENT: the tags
                guard length < 1_000_000,
                      let body = try? handle.read(upToCount: length),
                      body.count == length else { break }
                return parseVorbisComment([UInt8](body))
            }

            // Not the tag block (e.g. album art): jump over it without reading it.
            guard let position = try? handle.offset() else { break }
            do { try handle.seek(toOffset: position + UInt64(length)) } catch { break }
            if isLast { break }
        }
        return TrackMetadata()
    }

    /// Layout: [vendor length][vendor text][count] then count x ([length]["KEY=value"]).
    /// All numbers are 4 bytes, little-endian.
    private static func parseVorbisComment(_ bytes: [UInt8]) -> TrackMetadata {
        var pos = 0

        func readUInt32() -> Int? {
            guard pos + 4 <= bytes.count else { return nil }
            var value = 0
            for i in 0..<4 { value |= Int(bytes[pos + i]) << (8 * i) }
            pos += 4
            return value
        }

        guard let vendorLength = readUInt32(), pos + vendorLength <= bytes.count else { return TrackMetadata() }
        pos += vendorLength
        guard let count = readUInt32() else { return TrackMetadata() }

        var meta = TrackMetadata()
        for _ in 0..<count {
            guard let length = readUInt32(), pos + length <= bytes.count else { break }
            let text = String(decoding: bytes[pos..<(pos + length)], as: UTF8.self)
            pos += length

            guard let equals = text.firstIndex(of: "=") else { continue }
            let key = text[..<equals].uppercased()
            let value = String(text[text.index(after: equals)...])
            if key == "TITLE", meta.title == nil { meta.title = value }
            if key == "ARTIST", meta.artist == nil { meta.artist = value }
            if key == "ALBUM", meta.album == nil { meta.album = value }
            if key == "TRACKNUMBER", meta.trackNumber == nil { meta.trackNumber = leadingNumber(value) }
            if key == "DISCNUMBER", meta.discNumber == nil { meta.discNumber = leadingNumber(value) }
        }
        return meta
    }

    /// "3" -> 3, "3/12" -> 3 (tags often store "track/total").
    private static func leadingNumber(_ text: String) -> Int? {
        Int(text.split(separator: "/").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "")
    }

    // MARK: - Everything else (WAV)

    private static func readWithAVFoundation(_ url: URL) async -> TrackMetadata {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return TrackMetadata() }

        func text(for identifier: AVMetadataIdentifier) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first
            else { return nil }
            return try? await item.load(.stringValue)
        }

        return TrackMetadata(title: await text(for: .commonIdentifierTitle),
                             artist: await text(for: .commonIdentifierArtist),
                             album: await text(for: .commonIdentifierAlbumName))
    }
}
