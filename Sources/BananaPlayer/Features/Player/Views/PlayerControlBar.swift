import SwiftUI

struct PlayerControlBar: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.currentTrack?.title ?? "未开始播放")
                        .font(.headline)
                        .lineLimit(1)
                    Text(viewModel.currentTrack?.format.uppercased() ?? "文件格式")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    viewModel.playPrevious()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.08))
                        )
                }
                .disabled(viewModel.currentTrack == nil)
                .buttonStyle(.plain)
                .hoverInteractive(enabled: viewModel.currentTrack != nil, brightness: 0.14, scale: 1.03)

                Button {
                    viewModel.togglePlayPause()
                } label: {
                    Image(systemName: viewModel.state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.08))
                        )
                }
                .disabled(viewModel.currentTrack == nil)
                .buttonStyle(.plain)
                .hoverInteractive(enabled: viewModel.currentTrack != nil, brightness: 0.14, scale: 1.03)

                Button {
                    viewModel.playNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.08))
                        )
                }
                .disabled(viewModel.currentTrack == nil)
                .buttonStyle(.plain)
                .hoverInteractive(enabled: viewModel.currentTrack != nil, brightness: 0.14, scale: 1.03)
            }

            HStack(spacing: 10) {
                Text(viewModel.currentTimeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .trailing)

                Slider(
                    value: Binding(
                        get: { viewModel.state.progress },
                        set: { viewModel.seek(to: $0) }
                    ),
                    in: 0...1
                )
                .disabled(viewModel.currentTrack == nil)
                .hoverInteractive(enabled: viewModel.currentTrack != nil, brightness: 0.06)

                Text(viewModel.durationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .leading)

                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(viewModel.state.volume) },
                        set: { viewModel.setVolume(Float($0)) }
                    ),
                    in: 0...1
                )
                .frame(width: 120)
                .hoverInteractive(brightness: 0.06)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
