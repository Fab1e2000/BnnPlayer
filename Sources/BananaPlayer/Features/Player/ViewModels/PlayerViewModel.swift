import Foundation

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var state: PlaybackState
    @Published private(set) var currentTrack: Track?

    private let controller: any PlaybackControlling

    init(controller: any PlaybackControlling) {
        self.controller = controller
        self.state = controller.playbackState
        self.currentTrack = controller.currentTrack

        controller.onStateChange = { [weak self] state in
            self?.state = state
        }

        controller.onTrackChange = { [weak self] track in
            self?.currentTrack = track
        }
    }

    func play(track: Track, queue: [Track]) {
        controller.play(track: track, queue: queue)
    }

    func togglePlayPause() {
        controller.togglePlayPause()
    }

    func playNext() {
        controller.playNext()
    }

    func playPrevious() {
        controller.playPrevious()
    }

    func seek(to progress: Double) {
        controller.seek(to: progress)
    }

    func setVolume(_ volume: Float) {
        controller.setVolume(volume)
    }

    var currentTimeText: String {
        let duration = currentTrack?.duration ?? 0
        return formatDuration(duration * state.progress)
    }

    var durationText: String {
        formatDuration(currentTrack?.duration ?? 0)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }

        return String(format: "%02d:%02d", minutes, secs)
    }
}
