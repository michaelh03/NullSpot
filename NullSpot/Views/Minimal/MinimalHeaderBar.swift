//
//  MinimalHeaderBar.swift
//  NullSpot
//

import SwiftUI

struct MinimalHeaderBar: View {
    @Environment(AppStore.self) private var store

    @Binding var isSearching: Bool
    @Binding var searchText: String
    @Binding var selectedSearchIndex: Int
    let resultCount: Int
    @FocusState.Binding var focusedField: MinimalPlayerWindow.Field?
    let onSubmit: () -> Void
    let onSubmitEnqueue: () -> Void
    let onCycleFilter: () -> Void

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = MinimalTheme.headerIconSize
    @ScaledMetric(relativeTo: .body) private var fieldSize: CGFloat = MinimalTheme.searchFieldSize
    @ScaledMetric(relativeTo: .footnote) private var nowPlayingTitleSize: CGFloat = MinimalTheme.nowPlayingTitleSize
    @ScaledMetric(relativeTo: .caption) private var nowPlayingArtistSize: CGFloat = MinimalTheme.nowPlayingArtistSize

    var body: some View {
        HStack(spacing: 10) {
            if isSearching {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: iconSize))
                    .foregroundStyle(MinimalTheme.muted)
                    .accessibilityHidden(true)
                TextField("minimal.search_tracks", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: fieldSize))
                    .foregroundStyle(MinimalTheme.fg)
                    .focused($focusedField, equals: .search)
                    .onSubmit(onSubmit)
                    .onExitCommand(perform: exitSearch)
                    .onKeyPress(.downArrow) {
                        moveSelection(1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        moveSelection(-1)
                        return .handled
                    }
                    .onKeyPress(.tab) {
                        onCycleFilter()
                        return .handled
                    }
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.command) {
                            onSubmitEnqueue()
                            return .handled
                        }
                        return .ignored
                    }
            } else {
                MinimalVisualizer()
                nowPlayingInfo
            }

            Button(action: toggle) {
                Label(
                    isSearching ? "minimal.close" : "minimal.search",
                    systemImage: isSearching ? "xmark" : "magnifyingglass",
                )
                .labelStyle(.iconOnly)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(MinimalTheme.fg)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .frame(height: MinimalTheme.headerHeight)
        .background {
            Button("minimal.search", action: toggle)
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var nowPlayingInfo: some View {
        let current = currentTrack
        return VStack(alignment: .leading, spacing: 2) {
            MinimalMarqueeText(
                text: current?.name ?? String(localized: "minimal.placeholder.dash"),
                fontSize: nowPlayingTitleSize,
                weight: .semibold,
                color: MinimalTheme.fg,
            )
            MinimalMarqueeText(
                text: current?.artistName ?? String(localized: "minimal.nothing_playing"),
                fontSize: nowPlayingArtistSize,
                weight: .regular,
                color: MinimalTheme.muted,
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Prefer the URI from PlaybackViewModel (updated ~180ms after track change via
    // Spirc's loading callback) over store.currentTrackEntity, which waits for the
    // Mercury queue update + debounced metadata fetch.
    private var currentTrack: Track? {
        if let uri = PlaybackViewModel.shared.currentTrackUri,
           let trackId = SpotifyAPI.parseTrackURI(uri),
           let track = store.tracks[trackId] {
            return track
        }
        return store.currentTrackEntity
    }

    private func toggle() {
        if isSearching {
            exitSearch()
        } else {
            isSearching = true
        }
    }

    private func exitSearch() {
        isSearching = false
        searchText = ""
    }

    private func moveSelection(_ delta: Int) {
        guard resultCount > 0 else { return }
        let next = (selectedSearchIndex + delta).clamped(to: 0 ... (resultCount - 1))
        selectedSearchIndex = next
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
