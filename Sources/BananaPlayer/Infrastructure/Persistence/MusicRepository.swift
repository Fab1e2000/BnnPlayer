import Foundation

@MainActor
final class MusicRepository: MusicRepositoryProtocol {
    private let store: LibraryStore
    private let scanner: LibraryScannerService

    private(set) var albums: [Album] = []
    private(set) var tracksByAlbum: [String: [Track]] = [:]
    private(set) var libraryFolders: [LibraryFolder]

    init(store: LibraryStore, scanner: LibraryScannerService) {
        self.store = store
        self.scanner = scanner
        self.libraryFolders = store.loadFolders()

        if let cached = store.loadLibraryCache() {
            self.albums = cached.albums
            self.tracksByAlbum = cached.tracksByAlbum
        }
    }

    func addFolder(_ url: URL) throws {
        let normalized = url.standardizedFileURL
        guard !libraryFolders.contains(where: { $0.folderURL.standardizedFileURL == normalized }) else {
            return
        }

        let folder = LibraryFolder(id: normalized.path, folderURL: normalized, bookmarkData: nil)
        libraryFolders.append(folder)
        store.saveFolders(libraryFolders)
    }

    func removeFolder(id: String) {
        libraryFolders.removeAll { $0.id == id }
        store.saveFolders(libraryFolders)
    }

    func rescan() async -> ScanSummary {
        let foldersSnapshot = libraryFolders
        let scannerSnapshot = scanner

        let result = await Task.detached(priority: .userInitiated) {
            scannerSnapshot.scan(folders: foldersSnapshot)
        }.value

        albums = result.albums
        tracksByAlbum = result.tracksByAlbum
        store.saveLibraryCache(albums: albums, tracksByAlbum: tracksByAlbum)
        return result.summary
    }
}
