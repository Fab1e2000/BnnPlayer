import Foundation

struct LibraryScannerService: Sendable {
    private let supportedExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "flac"]
    private let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "tiff", "bmp", "gif"]
    private let metadataService: MetadataProviding

    init(metadataService: MetadataProviding) {
        self.metadataService = metadataService
    }

    func scan(folders: [LibraryFolder]) -> (albums: [Album], tracksByAlbum: [String: [Track]], summary: ScanSummary) {
        var summary = ScanSummary.empty
        var groupedTracks: [AlbumGroupKey: [Track]] = [:]
        var groupedAlbumArtists: [AlbumGroupKey: [String]] = [:]
        var artworkFolderCache: [URL: Bool] = [:]

        for folder in folders {
            let enumerator = FileManager.default.enumerator(
                at: folder.folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            guard let enumerator else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard
                    let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                    values.isRegularFile == true
                else {
                    continue
                }

                let ext = fileURL.pathExtension.lowercased()
                guard supportedExtensions.contains(ext) else {
                    continue
                }

                summary.totalFiles += 1

                let metadata = metadataService.readMetadata(for: fileURL)
                let albumFolder = resolveAlbumFolder(for: fileURL, libraryRoot: folder.folderURL, artworkFolderCache: &artworkFolderCache)
                let groupKey = AlbumGroupKey(folderURL: albumFolder.standardizedFileURL)

                let track = Track(
                    id: fileURL.path,
                    fileURL: fileURL,
                    title: metadata.title,
                    artist: metadata.artist,
                    album: metadata.album,
                    albumID: nil,
                    trackNumber: metadata.trackNumber,
                    discNumber: metadata.discNumber,
                    artworkURL: metadata.artworkURL,
                    duration: metadata.duration,
                    format: metadata.format
                )

                groupedTracks[groupKey, default: []].append(track)
                if let albumArtist = metadata.albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines), !albumArtist.isEmpty {
                    groupedAlbumArtists[groupKey, default: []].append(albumArtist)
                }
                summary.playableFiles += 1
            }
        }

        var albums: [Album] = []
        var tracksByAlbum: [String: [Track]] = [:]

        for (key, rawTracks) in groupedTracks {
            let albumTitle = preferredValue(from: rawTracks.compactMap(\.album), fallback: key.folderURL.lastPathComponent)
            let explicitAlbumArtists = groupedAlbumArtists[key] ?? []
            let albumArtist = preferredOptionalValue(from: explicitAlbumArtists)
                ?? preferredOptionalValue(from: rawTracks.compactMap(\.artist))
            let albumID = makeAlbumID(folderURL: key.folderURL, title: albumTitle)
            let coverURL = detectCover(in: key.folderURL, tracks: rawTracks)

            let sortedTracks = rawTracks
                .map {
                    Track(
                        id: $0.id,
                        fileURL: $0.fileURL,
                        title: $0.title,
                        artist: $0.artist,
                        album: $0.album,
                        albumID: albumID,
                        trackNumber: $0.trackNumber,
                        discNumber: $0.discNumber,
                        artworkURL: $0.artworkURL,
                        duration: $0.duration,
                        format: $0.format
                    )
                }
                .sorted(by: trackSort)

            let album = Album(
                id: albumID,
                title: albumTitle,
                artist: albumArtist,
                coverURL: coverURL,
                trackCount: sortedTracks.count
            )

            albums.append(album)
            tracksByAlbum[albumID] = sortedTracks
        }

        albums.sort { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        return (albums, tracksByAlbum, summary)
    }

    private func trackSort(_ lhs: Track, _ rhs: Track) -> Bool {
        let lhsDisc = lhs.discNumber ?? 0
        let rhsDisc = rhs.discNumber ?? 0
        if lhsDisc != rhsDisc {
            return lhsDisc < rhsDisc
        }

        switch (lhs.trackNumber, rhs.trackNumber) {
        case let (left?, right?):
            if left != right {
                return left < right
            }
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        default:
            break
        }

        let filenameCompare = lhs.fileURL.lastPathComponent.localizedCaseInsensitiveCompare(rhs.fileURL.lastPathComponent)
        if filenameCompare != .orderedSame {
            return filenameCompare == .orderedAscending
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func detectCover(in folderURL: URL, tracks: [Track]) -> URL? {
        if let embedded = tracks.compactMap(\.artworkURL).first {
            return embedded
        }

        let fileManager = FileManager.default
        let preferredNames = ["folder", "cover", "front", "album", "artwork"]

        guard let files = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else {
            return nil
        }

        let imageFiles = files.filter {
            imageExtensions.contains($0.pathExtension.lowercased())
        }

        for preferred in preferredNames {
            if let match = imageFiles.first(where: {
                $0.deletingPathExtension().lastPathComponent.lowercased() == preferred
            }) {
                return match
            }
        }

        if let anyLocalImage = imageFiles
            .sorted(by: {
                $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
            })
            .first
        {
            return anyLocalImage
        }

        return nil
    }

    private func resolveAlbumFolder(for fileURL: URL, libraryRoot: URL, artworkFolderCache: inout [URL: Bool]) -> URL {
        let root = libraryRoot.standardizedFileURL
        let parent = fileURL.deletingLastPathComponent().standardizedFileURL
        let fileManager = FileManager.default

        var cursor = parent
        while cursor.path.hasPrefix(root.path) {
            if containsArtworkImage(in: cursor, fileManager: fileManager, artworkFolderCache: &artworkFolderCache) {
                return cursor
            }

            if cursor.path == root.path {
                break
            }

            cursor.deleteLastPathComponent()
        }

        let rootComponents = root.pathComponents
        let parentComponents = parent.pathComponents

        if parentComponents.count > rootComponents.count {
            let topLevelName = parentComponents[rootComponents.count]
            return root.appendingPathComponent(topLevelName, isDirectory: true)
        }

        return parent
    }

    private func containsArtworkImage(in folderURL: URL, fileManager: FileManager, artworkFolderCache: inout [URL: Bool]) -> Bool {
        let normalizedURL = folderURL.standardizedFileURL

        if let cached = artworkFolderCache[normalizedURL] {
            return cached
        }

        guard let files = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else {
            artworkFolderCache[normalizedURL] = false
            return false
        }

        let hasImage = files.contains { imageExtensions.contains($0.pathExtension.lowercased()) }
        artworkFolderCache[normalizedURL] = hasImage
        return hasImage
    }

    private func preferredValue(from candidates: [String], fallback: String?) -> String {
        let normalized = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalized.isEmpty else {
            return fallback ?? "Unknown Album"
        }

        var counts: [String: Int] = [:]
        normalized.forEach { counts[$0, default: 0] += 1 }
        return counts.max { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value < rhs.value
            }
            return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedDescending
        }?.key ?? (fallback ?? "Unknown Album")
    }

    private func preferredOptionalValue(from candidates: [String]) -> String? {
        let normalized = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalized.isEmpty else {
            return nil
        }

        var counts: [String: Int] = [:]
        normalized.forEach { counts[$0, default: 0] += 1 }
        return counts.max { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value < rhs.value
            }
            return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedDescending
        }?.key
    }

    private func makeAlbumID(folderURL: URL, title: String) -> String {
        "\(title)|\(folderURL.path)"
    }
}

private struct AlbumGroupKey: Hashable {
    let folderURL: URL
}
