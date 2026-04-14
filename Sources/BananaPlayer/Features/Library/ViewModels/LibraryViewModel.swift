import AppKit
import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var albums: [Album] = []
    @Published private(set) var libraryFolders: [LibraryFolder] = []
    @Published var selectedAlbumID: String?
    @Published var searchText = ""
    @Published var isScanning = false
    @Published var scanSummary = ScanSummary.empty
    @Published var errorMessage: String?

    private var normalizedAlbumSearchTextByID: [String: String] = [:]
    private var normalizedTrackTitlesByAlbumID: [String: [String]] = [:]

    private let repository: any MusicRepositoryProtocol
    private let playerViewModel: PlayerViewModel

    init(repository: any MusicRepositoryProtocol, playerViewModel: PlayerViewModel) {
        self.repository = repository
        self.playerViewModel = playerViewModel
    }

    func bootstrap() {
        refreshData()
    }

    func addFolderFromDialog() {
        let panel = NSOpenPanel()
        panel.title = "选择音乐文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK else {
            return
        }

        for url in panel.urls {
            do {
                try repository.addFolder(url)
            } catch {
                errorMessage = "无法添加文件夹：\(url.lastPathComponent)"
            }
        }

        refreshData()
        scanLibrary()
    }

    func removeFolder(id: String) {
        repository.removeFolder(id: id)
        refreshData()
        scanLibrary()
    }

    func scanLibrary() {
        guard !isScanning else {
            return
        }

        isScanning = true

        Task { [weak self] in
            guard let self else {
                return
            }

            let summary = await self.repository.rescan()
            self.scanSummary = summary
            self.refreshData()
            self.isScanning = false
        }
    }

    var selectedAlbum: Album? {
        guard let selectedAlbumID else {
            return nil
        }
        return albums.first { $0.id == selectedAlbumID }
    }

    var filteredAlbums: [Album] {
        let keyword = normalizedSearchKeyword
        guard !keyword.isEmpty else {
            return albums
        }

        return albums.filter { album in
            let albumMatch = normalizedAlbumSearchTextByID[album.id]?.contains(keyword) ?? false

            let trackMatch = normalizedTrackTitlesByAlbumID[album.id]?.contains(where: { $0.contains(keyword) }) ?? false

            return albumMatch || trackMatch
        }
    }

    func tracks(for album: Album) -> [Track] {
        let tracks = repository.tracksByAlbum[album.id] ?? []

        let keyword = normalizedSearchKeyword
        guard !keyword.isEmpty else {
            return tracks
        }

        let normalizedTitles = normalizedTrackTitlesByAlbumID[album.id] ?? []
        guard normalizedTitles.count == tracks.count else {
            return tracks.filter { $0.title.lowercased().contains(keyword) }
        }

        return zip(tracks, normalizedTitles)
            .compactMap { track, normalizedTitle in
                normalizedTitle.contains(keyword) ? track : nil
            }
    }

    func openAlbum(_ album: Album) {
        selectedAlbumID = album.id
    }

    func closeAlbum() {
        selectedAlbumID = nil
    }

    func play(track: Track, in album: Album) {
        let queue = repository.tracksByAlbum[album.id] ?? []
        playerViewModel.play(track: track, queue: queue)
    }

    private func refreshData() {
        albums = repository.albums
        libraryFolders = repository.libraryFolders
        rebuildSearchIndexes()

        if let selectedAlbumID, !albums.contains(where: { $0.id == selectedAlbumID }) {
            self.selectedAlbumID = nil
        }
    }

    private var normalizedSearchKeyword: String {
        searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func rebuildSearchIndexes() {
        normalizedAlbumSearchTextByID = Dictionary(uniqueKeysWithValues: albums.map { album in
            let albumBlob = [album.title, album.artist ?? ""]
                .joined(separator: " ")
                .lowercased()
            return (album.id, albumBlob)
        })

        normalizedTrackTitlesByAlbumID = repository.tracksByAlbum.mapValues { tracks in
            tracks.map { $0.title.lowercased() }
        }
    }
}
