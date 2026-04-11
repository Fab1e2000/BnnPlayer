import Foundation

@MainActor
final class AppContainer: ObservableObject {
    let repository: MusicRepository
    let playbackEngine: AVPlaybackEngine
    let playerViewModel: PlayerViewModel
    let libraryViewModel: LibraryViewModel

    init() {
        let metadataService = MetadataService()
        let scannerService = LibraryScannerService(metadataService: metadataService)
        let libraryStore = LibraryStore()

        repository = MusicRepository(store: libraryStore, scanner: scannerService)
        playbackEngine = AVPlaybackEngine()
        playerViewModel = PlayerViewModel(controller: playbackEngine)
        libraryViewModel = LibraryViewModel(repository: repository, playerViewModel: playerViewModel)
    }
}
