import Foundation

@MainActor
protocol PlaybackControlling: AnyObject {
    var playbackState: PlaybackState { get }
    var currentTrack: Track? { get }
    var onStateChange: ((PlaybackState) -> Void)? { get set }
    var onTrackChange: ((Track?) -> Void)? { get set }

    func play(track: Track, queue: [Track])
    func togglePlayPause()
    func playNext()
    func playPrevious()
    func seek(to progress: Double)
    func setVolume(_ volume: Float)
}
