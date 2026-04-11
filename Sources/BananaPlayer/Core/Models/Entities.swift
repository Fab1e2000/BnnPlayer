import Foundation

struct Album: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String?
    let coverURL: URL?
    let trackCount: Int
}

struct Track: Identifiable, Hashable, Sendable {
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
}

struct LibraryFolder: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let folderURL: URL
    let bookmarkData: Data?
}

struct PlaybackState: Equatable, Sendable {
    var currentTrackID: String?
    var isPlaying: Bool
    var progress: Double
    var volume: Float
}

struct ScanSummary: Equatable, Sendable {
    var totalFiles: Int
    var playableFiles: Int
    var failedFiles: Int

    static let empty = ScanSummary(totalFiles: 0, playableFiles: 0, failedFiles: 0)
}

struct TrackMetadata: Sendable {
    let title: String
    let artist: String?
    let album: String?
    let albumArtist: String?
    let trackNumber: Int?
    let discNumber: Int?
    let artworkURL: URL?
    let duration: Double
    let format: String
}
