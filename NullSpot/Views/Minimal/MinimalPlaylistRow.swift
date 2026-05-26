//
//  MinimalPlaylistRow.swift
//  NullSpot
//

import SwiftUI

struct MinimalPlaylistRow: View {
    let track: Track
    let isCurrent: Bool
    let isSelected: Bool
    let onPlay: () -> Void

    @ScaledMetric(relativeTo: .footnote) private var titleSize: CGFloat = MinimalTheme.rowTitleSize
    @ScaledMetric(relativeTo: .caption2) private var artistSize: CGFloat = MinimalTheme.rowArtistSize
    @ScaledMetric(relativeTo: .caption2) private var metaSize: CGFloat = MinimalTheme.rowMetaSize
    @ScaledMetric(relativeTo: .caption) private var markerSize: CGFloat = MinimalTheme.markerSize

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 8) {
                marker
                    .frame(width: 12, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(.system(size: titleSize, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(MinimalTheme.fg)
                        .lineLimit(1)
                    Text(track.artistName)
                        .font(.system(size: artistSize))
                        .foregroundStyle(MinimalTheme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(track.durationFormatted)
                    .font(.system(size: metaSize, design: .monospaced))
                    .foregroundStyle(MinimalTheme.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? MinimalTheme.selection : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(track.name), \(track.artistName)"))
    }

    @ViewBuilder
    private var marker: some View {
        if isCurrent {
            Image(systemName: "play.fill")
                .font(.system(size: markerSize))
                .foregroundStyle(MinimalTheme.fg)
        } else {
            Color.clear.frame(width: 3, height: 3)
        }
    }
}
