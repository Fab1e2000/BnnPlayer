import Foundation

@MainActor
protocol MusicRepositoryProtocol: AnyObject {
    var albums: [Album] { get }
    var tracksByAlbum: [String: [Track]] { get }
    var libraryFolders: [LibraryFolder] { get }

    func addFolder(_ url: URL) throws
    func removeFolder(id: String)
    func rescan() async -> ScanSummary
}
