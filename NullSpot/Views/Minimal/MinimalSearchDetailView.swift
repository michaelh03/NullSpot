//
//  MinimalSearchDetailView.swift
//  NullSpot
//
//  Drill-in view shown when the user picks an album / playlist / podcast from
//  search results. Loads the entity's tracks (or episodes) and renders them
//  inline. Row tap enqueues a single track; the header offers Back and Play All.
//

import SwiftUI

struct MinimalSearchDetailView: View {
    @Environment(SpotifySession.self) private var session
    @Environment(AlbumService.self) private var albumService
    @Environment(ArtistService.self) private var artistService
    @Environment(PlaylistService.self) private var playlistService
    @Environment(ShowService.self) private var showService

    let detail: MinimalSearchDetail
    @FocusState.Binding var focusedField: MinimalPlayerWindow.Field?
    let onBack: () -> Void
    let onPlayAll: () -> Void
    let onPlayTrack: (Track, [Track]) -> Void
    let onPickTrack: (Track) -> Void
    let onEnqueueTrack: (Track) -> Void

    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var selectedIndex = 0
    /// Per-row trigger counters used to drive the "+" → ✓ animation when the
    /// user enqueues from the keyboard (⌘Return), where the tap never reaches
    /// the row itself.
    @State private var enqueueTriggers: [Int: Int] = [:]

    @ScaledMetric(relativeTo: .footnote) private var titleSize: CGFloat = MinimalTheme.rowTitleSize
    @ScaledMetric(relativeTo: .caption2) private var subtitleSize: CGFloat = MinimalTheme.rowArtistSize
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = MinimalTheme.headerIconSize

    var body: some View {
        VStack(spacing: 0) {
            header
            MinimalDivider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MinimalTheme.bg)
        .focusable()
        .focusEffectDisabled()
        .focused($focusedField, equals: .searchDetail)
        .onMoveCommand { direction in
            switch direction {
            case .up: moveSelection(-1)
            case .down: moveSelection(1)
            default: break
            }
        }
        .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.command) {
                enqueueSelected()
            } else {
                pickSelected()
            }
            return .handled
        }
        .onKeyPress(.delete) {
            onBack()
            return .handled
        }
        .onExitCommand(perform: onBack)
        .task(id: detail) { await load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(MinimalTheme.fg)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("minimal.search.back")

            artwork

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(MinimalTheme.fg)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: subtitleSize))
                    .foregroundStyle(MinimalTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onPlayAll) {
                Image(systemName: "play.fill")
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(MinimalTheme.fg)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("minimal.search.play_all")
        }
        .padding(.horizontal, 12)
        .frame(height: MinimalTheme.headerHeight)
    }

    @ViewBuilder
    private var artwork: some View {
        AsyncImage(url: artworkURL, transaction: .init(animation: .easeOut(duration: 0.15))) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFill()
            default:
                MinimalTheme.divider
            }
        }
        .frame(width: 28, height: 28)
        .clipped()
        .accessibilityHidden(true)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if tracks.isEmpty {
            ContentUnavailableView(
                "minimal.search.no_results_title",
                systemImage: "music.note.list",
            )
        } else {
            list
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { idx, track in
                        MinimalSearchResultRow(
                            artworkURL: track.images.url(for: 36),
                            title: track.name,
                            subtitle: track.artistName,
                            isSelected: idx == selectedIndex,
                            accessibilityLabel: "\(track.name), \(track.artistName)",
                            trailingAccessibilityLabel: "minimal.search.add",
                            progress: track.resumeProgress,
                            progressLabel: progressLabel(for: track),
                            onTap: {
                                selectedIndex = idx
                                onPlayTrack(track, tracks)
                            },
                            onTrailingTap: {
                                onEnqueueTrack(track)
                            },
                            enqueueTrigger: enqueueTriggers[idx] ?? 0,
                        )
                        .id(idx)
                        MinimalDivider()
                    }
                }
            }
            .onChange(of: selectedIndex) { _, new in
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }

    // MARK: - Derived

    /// Caption shown beside an episode's progress bar: "Played" for finished
    /// episodes, otherwise the remaining time ("12 min left"). Nil for tracks
    /// without resume data (regular music, unplayed episodes).
    private func progressLabel(for track: Track) -> String? {
        if track.fullyPlayed == true {
            return String(localized: "minimal.search.episode.played")
        }
        guard let resumePositionMs = track.resumePositionMs, resumePositionMs > 0 else {
            return nil
        }
        let remaining = max(0, track.durationMs - resumePositionMs)
        return String(localized: "minimal.search.episode.time_left \(formatDuration(milliseconds: remaining))")
    }

    private var title: String {
        switch detail {
        case let .album(album): album.name
        case let .artist(artist): artist.name
        case let .playlist(playlist): playlist.name
        case let .show(show): show.name
        }
    }

    private var subtitle: String {
        switch detail {
        case let .album(album): album.artistName
        case .artist:
            String(localized: "minimal.search.artist_top_tracks")
        case let .playlist(playlist):
            String(localized: "minimal.search.playlist_owner \(playlist.ownerName)")
        case let .show(show):
            String(localized: "minimal.search.show_publisher \(show.publisher)")
        }
    }

    private var artworkURL: URL? {
        switch detail {
        case let .album(album): album.images.url(for: 36)
        case let .artist(artist): artist.images.url(for: 36)
        case let .playlist(playlist): playlist.images.url(for: 36)
        case let .show(show): show.images.url(for: 36)
        }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            switch detail {
            case let .album(album):
                tracks = try await albumService.getAlbumTracks(
                    albumId: album.id,
                    session: session,
                )
            case let .artist(artist):
                tracks = try await artistService.fetchArtistTopTracks(
                    artistId: artist.id,
                    session: session,
                )
            case let .playlist(playlist):
                tracks = try await playlistService.getPlaylistTracks(
                    playlistId: playlist.id,
                    session: session,
                )
            case let .show(show):
                tracks = try await showService.getShowEpisodes(
                    showId: show.id,
                    showName: show.name,
                    showImages: show.images,
                    session: session,
                )
            }
        } catch {
            tracks = []
        }
        selectedIndex = 0
    }

    // MARK: - Selection

    private func moveSelection(_ delta: Int) {
        guard !tracks.isEmpty else { return }
        let next = (selectedIndex + delta).clamped(to: 0 ... (tracks.count - 1))
        selectedIndex = next
    }

    private func enqueueSelected() {
        guard tracks.indices.contains(selectedIndex) else { return }
        onEnqueueTrack(tracks[selectedIndex])
        enqueueTriggers[selectedIndex, default: 0] += 1
    }

    private func pickSelected() {
        guard tracks.indices.contains(selectedIndex) else { return }
        onPickTrack(tracks[selectedIndex])
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
