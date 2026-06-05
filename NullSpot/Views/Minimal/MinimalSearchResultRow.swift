//
//  MinimalSearchResultRow.swift
//  NullSpot
//
//  Presentation-only row used by the minimal search results list for all
//  three filter types (songs / albums / playlists). Keeps the row visually
//  uniform whichever filter is active.
//

import SwiftUI

struct MinimalSearchResultRow: View {
    let artworkURL: URL?
    let title: String
    let subtitle: String
    let isSelected: Bool
    let showsDisclosure: Bool
    let accessibilityLabel: String
    let trailingAccessibilityLabel: LocalizedStringKey
    /// Podcast episode listening progress (0...1). When non-nil, a thin progress
    /// bar and `progressLabel` are shown under the subtitle. Nil for music rows.
    let progress: Double?
    /// Caption shown next to the progress bar (e.g. "12 min left" / "Played").
    let progressLabel: String?
    let onTap: () -> Void
    let onTrailingTap: () -> Void
    /// Bumped by the parent to trigger the "+" → ✓ animation from a path that
    /// didn't originate in this row (e.g. ⌘Return on the keyboard).
    let enqueueTrigger: Int

    @State private var didEnqueue = false

    init(
        artworkURL: URL?,
        title: String,
        subtitle: String,
        isSelected: Bool,
        showsDisclosure: Bool = false,
        accessibilityLabel: String,
        trailingAccessibilityLabel: LocalizedStringKey,
        progress: Double? = nil,
        progressLabel: String? = nil,
        onTap: @escaping () -> Void,
        onTrailingTap: @escaping () -> Void,
        enqueueTrigger: Int = 0,
    ) {
        self.artworkURL = artworkURL
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.showsDisclosure = showsDisclosure
        self.accessibilityLabel = accessibilityLabel
        self.trailingAccessibilityLabel = trailingAccessibilityLabel
        self.progress = progress
        self.progressLabel = progressLabel
        self.onTap = onTap
        self.onTrailingTap = onTrailingTap
        self.enqueueTrigger = enqueueTrigger
    }

    private let titleSize: CGFloat = MinimalTheme.rowTitleSize
    private let subtitleSize: CGFloat = MinimalTheme.rowArtistSize
    private let metaSize: CGFloat = MinimalTheme.rowMetaSize
    private let addIconSize: CGFloat = 10
    private let chevronSize: CGFloat = 10
    private let artworkSize: CGFloat = 36

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)

            HStack(spacing: 10) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: titleSize, weight: .medium))
                        .foregroundStyle(MinimalTheme.fg)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: subtitleSize))
                        .foregroundStyle(MinimalTheme.muted)
                        .lineLimit(1)
                    if let progress {
                        progressView(progress)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: didEnqueue ? "checkmark" : "plus")
                    .font(.system(size: addIconSize, weight: .semibold))
                    .foregroundStyle(didEnqueue ? MinimalTheme.fg : MinimalTheme.muted)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: handleTrailingTap)
                    .accessibilityLabel(Text(trailingAccessibilityLabel))
                    .accessibilityAddTraits(.isButton)
                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.system(size: chevronSize, weight: .semibold))
                        .foregroundStyle(MinimalTheme.muted)
                        .accessibilityHidden(true)
                }
            }
            .allowsHitTesting(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? MinimalTheme.selection : Color.clear)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(accessibilityLabel))
        .onChange(of: enqueueTrigger) { _, _ in
            playEnqueueAnimation()
        }
    }

    private func handleTrailingTap() {
        onTrailingTap()
        playEnqueueAnimation()
    }

    private func playEnqueueAnimation() {
        withAnimation(.easeInOut(duration: 0.2)) { didEnqueue = true }
        Task {
            try? await Task.sleep(for: .milliseconds(1000))
            withAnimation(.easeInOut(duration: 0.2)) { didEnqueue = false }
        }
    }

    /// Thin listening-progress bar + caption shown for podcast episode rows.
    @ViewBuilder
    private func progressView(_ progress: Double) -> some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MinimalTheme.divider)
                    Capsule()
                        .fill(MinimalTheme.fg)
                        .frame(width: max(0, geo.size.width * progress))
                }
            }
            .frame(width: 48, height: 3)
            if let progressLabel {
                Text(progressLabel)
                    .font(.system(size: metaSize))
                    .foregroundStyle(MinimalTheme.muted)
                    .lineLimit(1)
            }
        }
        .padding(.top, 1)
    }

    @ViewBuilder
    private var artwork: some View {
        AsyncImage(url: artworkURL) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFill()
            default:
                MinimalTheme.divider
            }
        }
        .frame(width: artworkSize, height: artworkSize)
        .clipped()
        .accessibilityHidden(true)
    }
}
