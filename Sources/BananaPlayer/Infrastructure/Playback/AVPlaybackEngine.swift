import AVFoundation
import Foundation

@MainActor
final class AVPlaybackEngine: NSObject, PlaybackControlling {
    private var player: AVAudioPlayer?
    private var queue: [PlaybackQueueEntry] = []
    private var currentIndex: Int?
    private var progressTimer: Timer?

    var onStateChange: ((PlaybackState) -> Void)?
    var onTrackChange: ((Track?) -> Void)?

    private(set) var playbackState = PlaybackState(
        currentTrackID: nil,
        isPlaying: false,
        progress: 0,
        volume: 1
    ) {
        didSet {
            onStateChange?(playbackState)
        }
    }

    private(set) var currentTrack: Track? {
        didSet {
            onTrackChange?(currentTrack)
        }
    }

    override init() {
        super.init()
    }

    func play(track: Track, queue: [Track]) {
        self.queue = queue.map(PlaybackQueueEntry.init)
        currentIndex = self.queue.firstIndex(where: { $0.id == track.id })
        startCurrentTrack()
    }

    func togglePlayPause() {
        guard let player else {
            return
        }

        if player.isPlaying {
            player.pause()
            playbackState.isPlaying = false
        } else {
            player.play()
            playbackState.isPlaying = true
        }
    }

    func playNext() {
        guard let index = currentIndex else {
            return
        }

        let next = index + 1
        guard queue.indices.contains(next) else {
            playbackState.isPlaying = false
            playbackState.progress = 1
            stopProgressTimer()
            return
        }

        currentIndex = next
        startCurrentTrack()
    }

    func playPrevious() {
        guard let index = currentIndex else {
            return
        }

        let previous = max(0, index - 1)
        currentIndex = previous
        startCurrentTrack()
    }

    func seek(to progress: Double) {
        guard let player else {
            return
        }

        let bounded = min(max(progress, 0), 1)
        player.currentTime = bounded * player.duration
        playbackState.progress = bounded
    }

    func setVolume(_ volume: Float) {
        let bounded = min(max(volume, 0), 1)
        player?.volume = bounded
        playbackState.volume = bounded
    }

    private func startCurrentTrack() {
        guard let currentIndex, queue.indices.contains(currentIndex) else {
            return
        }

        let entry = queue[currentIndex]
        currentTrack = entry.toTrack()

        do {
            player = try AVAudioPlayer(contentsOf: entry.fileURL)
            player?.delegate = self
            player?.volume = playbackState.volume
            player?.prepareToPlay()
            player?.play()

            playbackState.currentTrackID = entry.id
            playbackState.isPlaying = true
            playbackState.progress = 0

            startProgressTimer()
        } catch {
            playbackState.isPlaying = false
            stopProgressTimer()
        }
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        let timer = Timer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(handleProgressTimerTick),
            userInfo: nil,
            repeats: true
        )
        progressTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    @objc private func handleProgressTimerTick() {
        syncProgress()
    }

    private func syncProgress() {
        guard let player, player.duration > 0 else {
            playbackState.progress = 0
            return
        }

        playbackState.progress = min(max(player.currentTime / player.duration, 0), 1)
    }
}

extension AVPlaybackEngine: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            playNext()
        }
    }
}

private struct PlaybackQueueEntry {
    let id: String
    let fileURL: URL
    let title: String
    let duration: Double
    let format: String

    init(_ track: Track) {
        id = track.id
        fileURL = track.fileURL
        title = track.title
        duration = track.duration
        format = track.format
    }

    func toTrack() -> Track {
        Track(
            id: id,
            fileURL: fileURL,
            title: title,
            artist: nil,
            album: nil,
            trackNumber: nil,
            discNumber: nil,
            artworkURL: nil,
            duration: duration,
            format: format
        )
    }
}
