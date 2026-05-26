//
//  MinimalVisualizer.swift
//  NullSpot
//
//  12-band FFT visualizer driven by VisualizerTap (real PCM samples from the
//  local audio renderer). Falls back to the NULLSPOT wordmark when no audio
//  is flowing locally (paused, idle, or playing on a Connect device).
//

import SwiftUI

struct MinimalVisualizer: View {
    @ScaledMetric(relativeTo: .caption) private var titleSize: CGFloat = MinimalTheme.appTitleSize

    private let tap = VisualizerTap.shared
    private let playbackViewModel = PlaybackViewModel.shared

    private static let barGap: Double = 2
    private static let visualizerWidth: Double = 120
    private static let maxBarHeightRatio: Double = 0.65

    var body: some View {
        content
            .onAppear { tap.setMounted(true) }
            .onDisappear { tap.setMounted(false) }
    }

    @ViewBuilder
    private var content: some View {
        if playbackViewModel.isAwaitingPlayback {
            ProgressView()
                .controlSize(.small)
                .frame(width: Self.visualizerWidth)
                .accessibilityLabel("minimal.visualizer.loading")
        } else if tap.hasAudio {
            // Canvas is opaque to SwiftUI's animation system — an implicit
            // .animation(value:) here drives the subtree at display refresh
            // rate (60–120 Hz) trying to interpolate redraws it can't actually
            // interpolate. Smoothing is already applied in VisualizerTap.
            Canvas { context, size in
                draw(context: context, size: size, bands: tap.bands)
            }
            .frame(width: Self.visualizerWidth)
            .accessibilityHidden(true)
        } else {
            Text("minimal.app_title")
                .font(.system(size: titleSize, weight: .bold))
                .tracking(2)
                .foregroundStyle(MinimalTheme.fg)
        }
    }

    private func draw(context: GraphicsContext, size: CGSize, bands: [Float]) {
        let barCount = bands.count
        guard barCount > 0 else { return }
        let totalGap = Self.barGap * Double(barCount - 1)
        let barWidth = (size.width - totalGap) / Double(barCount)
        let maxBarHeight = size.height * Self.maxBarHeightRatio
        let centerY = size.height / 2

        // Build one Path with all 12 rects and issue a single fill, rather
        // than allocating 12 CGPaths + 12 fills per frame at 30 fps. Same
        // pixels on screen, ~12× less CoreGraphics work per redraw.
        var path = Path()
        for (i, value) in bands.enumerated() {
            let height = Double(value) * maxBarHeight
            let x = Double(i) * (barWidth + Self.barGap)
            let y = centerY - height / 2
            path.addRect(CGRect(x: x, y: y, width: barWidth, height: height))
        }
        context.fill(path, with: .color(MinimalTheme.fg))
    }
}
