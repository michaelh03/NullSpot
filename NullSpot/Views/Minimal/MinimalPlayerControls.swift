//
//  MinimalPlayerControls.swift
//  NullSpot
//

import SwiftUI

struct MinimalPlayerControls: View {
    @Environment(AppStore.self) private var store
    @Environment(SpotifySession.self) private var session

    private let playbackViewModel = PlaybackViewModel.shared

    @State private var scrubPosition: Double = 0
    @State private var isScrubbing = false

    @ScaledMetric(relativeTo: .caption2) private var scrubLabelSize: CGFloat = MinimalTheme.scrubLabelSize

    var body: some View {
        VStack(spacing: 8) {
            progressRow
            controlsRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MinimalTheme.bg)
    }

    private var progressRow: some View {
        // Only drive a TimelineView while playing — paused state doesn't tick,
        // so the SwiftUI graph stops re-evaluating this subtree (and re-init'ing
        // the Slider) when the position can't change on its own.
        Group {
            if playbackViewModel.isPlaying {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    progressContent
                }
            } else {
                progressContent
            }
        }
    }

    @ViewBuilder
    private var progressContent: some View {
        let totalMs = Double(playbackViewModel.trackDurationMs)
        let currentMs = Double(playbackViewModel.interpolatedPositionMs)
        let displayValue = isScrubbing ? scrubPosition : currentMs

        HStack(spacing: 8) {
            Text(formatTrackTime(milliseconds: Int(displayValue)))
                .font(.system(size: scrubLabelSize, design: .monospaced))
                .foregroundStyle(MinimalTheme.muted)
                .frame(width: 32, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { displayValue },
                    set: { scrubPosition = $0 },
                ),
                in: 0 ... max(totalMs, 1),
            ) { editing in
                if editing {
                    scrubPosition = currentMs
                    isScrubbing = true
                } else {
                    playbackViewModel.seek(to: UInt32(scrubPosition))
                    isScrubbing = false
                }
            }
            .tint(MinimalTheme.fg)
            .controlSize(.mini)
            .disabled(totalMs <= 0)

            Text(totalMs > 0 ? formatTrackTime(milliseconds: Int(totalMs)) : "--:--")
                .font(.system(size: scrubLabelSize, design: .monospaced))
                .foregroundStyle(MinimalTheme.muted)
                .frame(width: 32, alignment: .leading)
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 20) {
            MinimalTransportButton(
                titleKey: "minimal.shuffle",
                icon: "shuffle",
                baseSize: MinimalTheme.transportSecondarySize,
                isActive: playbackViewModel.isShuffleEnabled,
                action: playbackViewModel.toggleShuffle,
            )
            MinimalTransportButton(
                titleKey: "minimal.previous_track",
                icon: "backward.fill",
                baseSize: MinimalTheme.transportSecondarySize,
                action: playbackViewModel.previous,
            )
            MinimalTransportButton(
                titleKey: playbackViewModel.isPlaying ? "minimal.pause" : "minimal.play",
                icon: playbackViewModel.isPlaying ? "pause.fill" : "play.fill",
                baseSize: MinimalTheme.transportPrimarySize,
                action: togglePlayPause,
            )
            MinimalTransportButton(
                titleKey: "minimal.next_track",
                icon: "forward.fill",
                baseSize: MinimalTheme.transportSecondarySize,
                action: playbackViewModel.next,
            )
            MinimalTransportButton(
                titleKey: "minimal.repeat",
                icon: "repeat",
                baseSize: MinimalTheme.transportSecondarySize,
                isActive: playbackViewModel.isRepeatEnabled,
                action: playbackViewModel.toggleRepeat,
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func togglePlayPause() {
        if playbackViewModel.isPlaying {
            playbackViewModel.pause()
        } else if playbackViewModel.currentTrackUri != nil {
            playbackViewModel.resume()
        } else if let firstNext = store.nextTrackEntities.first {
            Task {
                await playbackViewModel.playTrack(trackId: firstNext.id, session: session)
            }
        }
    }
}
