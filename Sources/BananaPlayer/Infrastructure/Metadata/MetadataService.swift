import AVFoundation
import CryptoKit
import Foundation

struct MetadataService: MetadataProviding {
    func readMetadata(for fileURL: URL) -> TrackMetadata {
        let asset = AVURLAsset(
            url: fileURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )
        let commonMetadata = asset.commonMetadata
        let fullMetadata = asset.metadata

        let rawTitle = metadataValue(for: .commonIdentifierTitle, in: commonMetadata)
            ?? fileURL.deletingPathExtension().lastPathComponent
        let artist = metadataValue(for: .commonIdentifierArtist, in: commonMetadata)
        let album = metadataValue(for: .commonIdentifierAlbumName, in: commonMetadata)
        let albumArtist = firstNonEmpty([
            metadataValue(for: .iTunesMetadataAlbumArtist, in: fullMetadata),
            metadataValue(for: .id3MetadataBand, in: fullMetadata),
            firstMetadataValue(containing: "albumartist", in: fullMetadata),
            firstMetadataValue(containing: "album artist", in: fullMetadata),
            artist
        ])
        let duration = max(0, CMTimeGetSeconds(asset.duration))
        let format = fileURL.pathExtension.lowercased()
        let filename = fileURL.deletingPathExtension().lastPathComponent
        let trackNumber = parseNumberPair(
            metadataValue(for: .iTunesMetadataTrackNumber, in: fullMetadata)
                ?? metadataValue(for: .id3MetadataTrackNumber, in: fullMetadata)
                ?? firstMetadataValue(containing: "track", in: fullMetadata)
        )?.first ?? parseLeadingTrackNumber(filename)
        let title = normalizeTitle(rawTitle, trackNumber: trackNumber)
        let discNumber = parseNumberPair(
            metadataValue(for: .iTunesMetadataDiscNumber, in: fullMetadata)
                ?? metadataValue(for: .id3MetadataPartOfASet, in: fullMetadata)
                ?? firstMetadataValue(containing: "disc", in: fullMetadata)
        )?.first
        let artworkURL = extractArtworkURL(commonMetadata: commonMetadata, fullMetadata: fullMetadata, sourceFileURL: fileURL)

        return TrackMetadata(
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            trackNumber: trackNumber,
            discNumber: discNumber,
            artworkURL: artworkURL,
            duration: duration,
            format: format
        )
    }

    private func metadataValue(for identifier: AVMetadataIdentifier, in metadata: [AVMetadataItem]) -> String? {
        AVMetadataItem
            .metadataItems(from: metadata, filteredByIdentifier: identifier)
            .compactMap(textValue)
            .first
    }

    private func firstMetadataValue(containing keyword: String, in metadata: [AVMetadataItem]) -> String? {
        metadata
            .first {
                $0.identifier?.rawValue.localizedCaseInsensitiveContains(keyword) == true
                    || $0.commonKey?.rawValue.localizedCaseInsensitiveContains(keyword) == true
            }.flatMap(textValue)
    }

    private func textValue(from item: AVMetadataItem) -> String? {
        if let string = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty {
            return string
        }

        if let value = item.value as? NSString {
            let string = String(value).trimmingCharacters(in: .whitespacesAndNewlines)
            if !string.isEmpty {
                return string
            }
        }

        if let value = item.value as? NSNumber {
            return value.stringValue
        }

        return nil
    }

    private func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func parseNumberPair(_ value: String?) -> (first: Int, second: Int?)? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let components = trimmed.split(separator: "/", maxSplits: 1).map(String.init)
        if let first = Int(components[0].trimmingCharacters(in: .whitespaces)) {
            let second = components.count > 1 ? Int(components[1].trimmingCharacters(in: .whitespaces)) : nil
            return (first, second)
        }

        return nil
    }

    private func parseLeadingTrackNumber(_ filename: String) -> Int? {
        guard
            let match = Self.leadingTrackRegex.firstMatch(in: filename, range: NSRange(location: 0, length: filename.utf16.count)),
            let range = Range(match.range(at: 1), in: filename)
        else {
            return nil
        }

        return Int(filename[range])
    }

    private func normalizeTitle(_ title: String, trackNumber: Int?) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return title
        }

        let candidateNumbers: [Int]
        if let trackNumber {
            candidateNumbers = [trackNumber]
        } else {
            candidateNumbers = []
        }

        for number in candidateNumbers {
            if let stripped = stripLeadingTrackNumber(from: trimmed, number: number) {
                return stripped
            }
        }

        return stripGenericLeadingTrackNumber(from: trimmed) ?? trimmed
    }

    private func stripLeadingTrackNumber(from title: String, number: Int) -> String? {
        for regex in Self.numberedLeadingTrackRegexes {
            guard
                let match = regex.firstMatch(in: title, range: NSRange(location: 0, length: title.utf16.count)),
                let numberRange = Range(match.range(at: 1), in: title),
                Int(title[numberRange]) == number,
                let range = Range(match.range(at: 2), in: title)
            else {
                continue
            }

            let cleaned = title[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        return nil
    }

    private func stripGenericLeadingTrackNumber(from title: String) -> String? {
        for regex in Self.genericLeadingTrackRegexes {
            guard
                let match = regex.firstMatch(in: title, range: NSRange(location: 0, length: title.utf16.count)),
                let range = Range(match.range(at: 1), in: title)
            else {
                continue
            }

            let cleaned = title[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        return nil
    }

    private func extractArtworkURL(commonMetadata: [AVMetadataItem], fullMetadata: [AVMetadataItem], sourceFileURL: URL) -> URL? {
        let candidates = (
            AVMetadataItem.metadataItems(from: commonMetadata, filteredByIdentifier: .commonIdentifierArtwork)
            + AVMetadataItem.metadataItems(from: fullMetadata, filteredByIdentifier: .id3MetadataAttachedPicture)
            + AVMetadataItem.metadataItems(from: fullMetadata, filteredByIdentifier: .iTunesMetadataCoverArt)
            + fullMetadata.filter {
                let identifier = $0.identifier?.rawValue.lowercased() ?? ""
                return identifier.contains("artwork") || identifier.contains("picture") || identifier.contains("cover")
            }
        )

        guard
            let data = candidates.compactMap(\.dataValue).first(where: { !$0.isEmpty })
        else {
            return nil
        }

        let ext = imageExtension(for: data)
        let fileURL = artworkCacheDirectory().appendingPathComponent(artworkFilename(for: sourceFileURL, ext: ext))

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? data.write(to: fileURL, options: .atomic)
        }

        return fileURL
    }

    private func artworkCacheDirectory() -> URL {
        Self.artworkDirectory
    }

    private func artworkFilename(for sourceFileURL: URL, ext: String) -> String {
        let digest = SHA256.hash(data: Data(sourceFileURL.path.utf8))
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        return "\(hex).\(ext)"
    }

    private func imageExtension(for data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "png"
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "jpg"
        }
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) {
            return "gif"
        }
        if data.starts(with: [0x52, 0x49, 0x46, 0x46]) && data.count >= 12 {
            let header = String(data: data.subdata(in: 8..<12), encoding: .ascii)
            if header == "WEBP" {
                return "webp"
            }
        }
        return "img"
    }

    private static let leadingTrackRegex = try! NSRegularExpression(pattern: #"^\s*(\d{1,3})(?:[\s._-]|$)"#)

    private static let genericLeadingTrackRegexes: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"^\s*\d{1,3}(?:\s+|[._\-:：、,，)）]+\s*)(.+)$"#, options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: #"^\s*(?:tr(?:ack)?\.?\s*)\d{1,3}(?:\s+|[._\-:：、,，)）]*\s*)(.+)$"#, options: [.caseInsensitive])
    ]

    private static let numberedLeadingTrackRegexes: [NSRegularExpression] = [
        try! NSRegularExpression(
            pattern: #"^\s*0*(\d{1,3})(?:\s+|[._\-:：、,，)）]+\s*)(.+)$"#,
            options: [.caseInsensitive]
        ),
        try! NSRegularExpression(
            pattern: #"^\s*(?:tr(?:ack)?\.?\s*)0*(\d{1,3})(?:\s+|[._\-:：、,，)）]*\s*)(.+)$"#,
            options: [.caseInsensitive]
        )
    ]

    private static let artworkDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = base.appendingPathComponent("BananaPlayer/Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()
}
