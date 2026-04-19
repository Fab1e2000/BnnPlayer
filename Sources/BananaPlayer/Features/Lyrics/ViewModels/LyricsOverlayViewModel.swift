import Combine
import Foundation

@MainActor
final class LyricsOverlayViewModel: ObservableObject {
    @Published private(set) var primaryLine = "无歌词"
    @Published private(set) var secondaryLine: String?

    private let playerViewModel: PlayerViewModel
    private let repository: any MusicRepositoryProtocol
    private let parser = LRCParser()

    private var cancellables: Set<AnyCancellable> = []
    private var loadedTrackID: String?
    private var lyricLines: [LyricLine] = []
    private var activeLineIndex: Int?
    private var lrcIndexByAlbumFolderPath: [String: [String: URL]] = [:]

    init(playerViewModel: PlayerViewModel, repository: any MusicRepositoryProtocol) {
        self.playerViewModel = playerViewModel
        self.repository = repository

        bindPlayerUpdates()
        loadLyrics(for: playerViewModel.currentTrack)
        syncLyrics(with: playerViewModel.state, track: playerViewModel.currentTrack, force: true)
    }

    private func bindPlayerUpdates() {
        playerViewModel.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                self?.loadLyrics(for: track)
            }
            .store(in: &cancellables)

        playerViewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else {
                    return
                }
                self.syncLyrics(with: state, track: self.playerViewModel.currentTrack)
            }
            .store(in: &cancellables)
    }

    private func loadLyrics(for track: Track?) {
        guard let track else {
            loadedTrackID = nil
            lyricLines = []
            activeLineIndex = nil
            primaryLine = "无歌词"
            secondaryLine = nil
            return
        }

        guard loadedTrackID != track.id else {
            return
        }
        loadedTrackID = track.id

        activeLineIndex = nil

        guard let lyricURL = resolveLyricURL(for: track) else {
            lyricLines = []
            primaryLine = "无歌词"
            secondaryLine = nil
            return
        }

        lyricLines = parser.parse(fileURL: lyricURL)

        guard !lyricLines.isEmpty else {
            primaryLine = "无歌词"
            secondaryLine = nil
            return
        }

        syncLyrics(with: playerViewModel.state, track: track, force: true)
    }

    private func syncLyrics(with state: PlaybackState, track: Track?, force: Bool = false) {
        guard let track else {
            return
        }

        guard !lyricLines.isEmpty else {
            return
        }

        let seconds = max(0, track.duration * state.progress)
        let currentMs = Int((seconds * 1000).rounded(.down))

        let nextActiveIndex = lyricLines.lastIndex { $0.timestampMs <= currentMs }
        guard force || activeLineIndex != nextActiveIndex else {
            return
        }

        activeLineIndex = nextActiveIndex

        guard let nextActiveIndex else {
            primaryLine = lyricLines.first?.primaryText ?? "..."
            secondaryLine = lyricLines.first?.secondaryText
            return
        }

        let line = lyricLines[nextActiveIndex]
        primaryLine = line.primaryText
        secondaryLine = line.secondaryText
    }

    private func resolveLyricURL(for track: Track) -> URL? {
        let directSiblingURL = track.fileURL
            .deletingPathExtension()
            .appendingPathExtension("lrc")

        if FileManager.default.fileExists(atPath: directSiblingURL.path) {
            return directSiblingURL
        }

        guard let albumID = albumID(for: track.id),
              let albumFolderURL = albumFolderURL(from: albumID)
        else {
            return nil
        }

        let folderPath = albumFolderURL.standardizedFileURL.path
        let index = lrcIndexByAlbumFolderPath[folderPath] ?? buildLyricIndex(in: albumFolderURL)
        lrcIndexByAlbumFolderPath[folderPath] = index

        let candidates = [
            normalizeLyricStem(track.fileURL.deletingPathExtension().lastPathComponent),
            normalizeLyricStem(track.title)
        ]

        for candidate in candidates {
            if let match = index[candidate] {
                return match
            }
        }

        return nil
    }

    private func albumID(for trackID: String) -> String? {
        repository.tracksByAlbum.first { _, tracks in
            tracks.contains(where: { $0.id == trackID })
        }?.key
    }

    private func albumFolderURL(from albumID: String) -> URL? {
        guard let splitter = albumID.lastIndex(of: "|") else {
            return nil
        }

        let pathStart = albumID.index(after: splitter)
        let folderPath = String(albumID[pathStart...])
        guard !folderPath.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: folderPath, isDirectory: true)
    }

    private func buildLyricIndex(in albumFolderURL: URL) -> [String: URL] {
        let fileManager = FileManager.default
        guard
            let enumerator = fileManager.enumerator(
                at: albumFolderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return [:]
        }

        var index: [String: URL] = [:]

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "lrc" else {
                continue
            }

            let key = normalizeLyricStem(fileURL.deletingPathExtension().lastPathComponent)
            if index[key] == nil {
                index[key] = fileURL
            }
        }

        return index
    }

    private func normalizeLyricStem(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"^\d{1,3}[\s._\-]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]"#, with: "", options: .regularExpression)
            .lowercased()
    }
}
