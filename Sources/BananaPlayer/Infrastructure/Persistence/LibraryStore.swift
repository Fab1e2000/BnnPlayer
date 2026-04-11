import Foundation

final class LibraryStore {
    private let defaults: UserDefaults
    private let foldersKey = "banana_player.library_folders"
    private let cacheKey = "banana_player.library_cache"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadFolders() -> [LibraryFolder] {
        guard let data = defaults.data(forKey: foldersKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([LibraryFolder].self, from: data)
        } catch {
            return []
        }
    }

    func saveFolders(_ folders: [LibraryFolder]) {
        guard let data = try? JSONEncoder().encode(folders) else {
            return
        }

        defaults.set(data, forKey: foldersKey)
    }

    func loadLibraryCache() -> (albums: [Album], tracksByAlbum: [String: [Track]])? {
        guard let data = defaults.data(forKey: cacheKey) else {
            return nil
        }

        do {
            let payload = try JSONDecoder().decode(LibraryCachePayload.self, from: data)
            let albums = payload.albums.map { $0.toEntity() }
            let tracksByAlbum = payload.tracksByAlbum.mapValues { records in records.map { $0.toEntity() } }
            return (albums, tracksByAlbum)
        } catch {
            return nil
        }
    }

    func saveLibraryCache(albums: [Album], tracksByAlbum: [String: [Track]]) {
        let payload = LibraryCachePayload(
            albums: albums.map(AlbumCacheRecord.init),
            tracksByAlbum: tracksByAlbum.mapValues { tracks in tracks.map(TrackCacheRecord.init) }
        )

        guard let data = try? JSONEncoder().encode(payload) else {
            return
        }

        defaults.set(data, forKey: cacheKey)
    }

    func clearLibraryCache() {
        defaults.removeObject(forKey: cacheKey)
    }
}

private struct LibraryCachePayload: Codable {
    let albums: [AlbumCacheRecord]
    let tracksByAlbum: [String: [TrackCacheRecord]]
}

private struct AlbumCacheRecord: Codable {
    let id: String
    let title: String
    let artist: String?
    let coverURL: URL?
    let trackCount: Int

    init(_ album: Album) {
        id = album.id
        title = album.title
        artist = album.artist
        coverURL = album.coverURL
        trackCount = album.trackCount
    }

    func toEntity() -> Album {
        Album(
            id: id,
            title: title,
            artist: artist,
            coverURL: coverURL,
            trackCount: trackCount
        )
    }
}

private struct TrackCacheRecord: Codable {
    let id: String
    let fileURL: URL
    let title: String
    let artist: String?
    let album: String?
    let albumID: String?
    let trackNumber: Int?
    let discNumber: Int?
    let artworkURL: URL?
    let duration: Double
    let format: String

    init(_ track: Track) {
        id = track.id
        fileURL = track.fileURL
        title = track.title
        artist = track.artist
        album = track.album
        albumID = track.albumID
        trackNumber = track.trackNumber
        discNumber = track.discNumber
        artworkURL = track.artworkURL
        duration = track.duration
        format = track.format
    }

    func toEntity() -> Track {
        Track(
            id: id,
            fileURL: fileURL,
            title: title,
            artist: artist,
            album: album,
            albumID: albumID,
            trackNumber: trackNumber,
            discNumber: discNumber,
            artworkURL: artworkURL,
            duration: duration,
            format: format
        )
    }
}
