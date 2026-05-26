//
//  MinimalSearchResultsView.swift
//  NullSpot
//
//  Minimal search surface — single-type results list (songs / albums / playlists),
//  pill row filter, recent-searches empty state, and infinite scroll on the
//  active type.
//

import SwiftUI

enum MinimalSearchPick {
    case track(Track)
    case album(Album)
    case artist(Artist)
    case playlist(Playlist)
    case show(Show)
}

/// An entity the user has drilled into from search to browse its contents
/// (tracks for albums/playlists/artists, episodes for shows).
enum MinimalSearchDetail: Hashable {
    case album(Album)
    case artist(Artist)
    case playlist(Playlist)
    case show(Show)
}

struct MinimalSearchResultsView: View {
    @Environment(AppStore.self) private var store
    @Environment(SearchService.self) private var searchService
    @Environment(SpotifySession.self) private var session
    @Environment(RecentSearchesStore.self) private var recentSearches

    @Binding var searchText: String
    @Binding var selectedIndex: Int
    @Binding var filter: MinimalSearchFilter
    let onPick: (MinimalSearchPick) -> Void
    let onEnqueue: (MinimalSearchPick) -> Void
    let onDrillIn: (MinimalSearchDetail) -> Void

    @State private var searchTask: Task<Void, Never>?
    @State private var paginateTask: Task<Void, Never>?
    @Namespace private var tabIndicatorNamespace

    var body: some View {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        VStack(spacing: 0) {
            tabRow
            MinimalDivider()
            content(trimmed: trimmed)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MinimalTheme.bg)
        .background(filterShortcutButtons)
        .onChange(of: searchText) { _, newValue in
            scheduleSearch(query: newValue)
        }
        .onChange(of: filter) { _, _ in
            selectedIndex = 0
        }
        .onDisappear {
            searchTask?.cancel()
            paginateTask?.cancel()
        }
    }

    // MARK: - Tab row (Material-style underlined tabs)

    private var tabRow: some View {
        HStack(spacing: 0) {
            ForEach(MinimalSearchFilter.allCases, id: \.self) { item in
                tab(for: item)
            }
        }
    }

    private func tab(for item: MinimalSearchFilter) -> some View {
        let isActive = item == filter
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { filter = item }
        } label: {
            VStack(spacing: 0) {
                Text(String(localized: item.localizedTitleKey))
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? MinimalTheme.fg : MinimalTheme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                ZStack {
                    Rectangle().fill(Color.clear).frame(height: 2)
                    if isActive {
                        Rectangle()
                            .fill(MinimalTheme.fg)
                            .frame(height: 2)
                            .matchedGeometryEffect(id: "tabIndicator", in: tabIndicatorNamespace)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var filterShortcutButtons: some View {
        ZStack {
            ForEach(Array(MinimalSearchFilter.allCases.enumerated()), id: \.offset) { idx, item in
                Button("") { filter = item }
                    .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: .command)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(trimmed: String) -> some View {
        if trimmed.isEmpty {
            recentsOrIdle
        } else if store.searchIsLoading, currentResultsCount == 0 {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if currentResultsCount == 0 {
            ContentUnavailableView.search(text: trimmed)
        } else {
            resultsList
        }
    }

    @ViewBuilder
    private var recentsOrIdle: some View {
        if recentSearches.entries.isEmpty {
            ContentUnavailableView(
                "minimal.search.idle_title",
                systemImage: "magnifyingglass",
                description: Text("minimal.search.idle_description"),
            )
        } else {
            recentSearchesList
        }
    }

    private var recentSearchesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("minimal.search.recent.title")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MinimalTheme.muted)
                    .tracking(1)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                ForEach(Array(recentSearches.entries.enumerated()), id: \.offset) { idx, query in
                    Button {
                        searchText = query
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                                .foregroundStyle(MinimalTheme.muted)
                                .frame(width: 16)
                            Text(query)
                                .font(.system(size: 12))
                                .foregroundStyle(MinimalTheme.fg)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(idx == selectedIndex ? MinimalTheme.selection : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    MinimalDivider()
                }
            }
        }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    switch filter {
                    case .songs:
                        tracksList
                    case .albums:
                        albumsList
                    case .artists:
                        artistsList
                    case .playlists:
                        playlistsList
                    case .podcasts:
                        showsList
                    }

                    if pagination(for: filter).hasMore {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                triggerPagination()
                            }
                        if pagination(for: filter).isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.vertical, 8)
                        }
                    }
                }
                .id(filter)
            }
            .onChange(of: selectedIndex) { _, new in
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var tracksList: some View {
        let tracks = store.searchResults?.tracks ?? []
        ForEach(Array(tracks.enumerated()), id: \.offset) { idx, track in
            MinimalSearchResultRow(
                artworkURL: track.images.url(for: 36),
                title: track.name,
                subtitle: track.artistName,
                isSelected: idx == selectedIndex,
                accessibilityLabel: "\(track.name), \(track.artistName)",
                trailingAccessibilityLabel: "minimal.search.add",
                onTap: { onPick(.track(track)) },
                onTrailingTap: { onEnqueue(.track(track)) },
            )
            .id(idx)
            MinimalDivider()
        }
    }

    @ViewBuilder
    private var albumsList: some View {
        let albums = store.searchResults?.albums ?? []
        ForEach(Array(albums.enumerated()), id: \.offset) { idx, album in
            MinimalSearchResultRow(
                artworkURL: album.images.url(for: 36),
                title: album.name,
                subtitle: albumSubtitle(album),
                isSelected: idx == selectedIndex,
                showsDisclosure: true,
                accessibilityLabel: "\(album.name), \(album.artistName)",
                trailingAccessibilityLabel: "minimal.search.queue_all",
                onTap: { onDrillIn(.album(album)) },
                onTrailingTap: { onEnqueue(.album(album)) },
            )
            .id(idx)
            MinimalDivider()
        }
    }

    @ViewBuilder
    private var artistsList: some View {
        let artists = store.searchResults?.artists ?? []
        ForEach(Array(artists.enumerated()), id: \.offset) { idx, artist in
            MinimalSearchResultRow(
                artworkURL: artist.images.url(for: 36),
                title: artist.name,
                subtitle: artistSubtitle(artist),
                isSelected: idx == selectedIndex,
                showsDisclosure: true,
                accessibilityLabel: artist.name,
                trailingAccessibilityLabel: "minimal.search.queue_all",
                onTap: { onDrillIn(.artist(artist)) },
                onTrailingTap: { onEnqueue(.artist(artist)) },
            )
            .id(idx)
            MinimalDivider()
        }
    }

    @ViewBuilder
    private var playlistsList: some View {
        let playlists = store.searchResults?.playlists ?? []
        ForEach(Array(playlists.enumerated()), id: \.offset) { idx, playlist in
            MinimalSearchResultRow(
                artworkURL: playlist.images.url(for: 36),
                title: playlist.name,
                subtitle: playlistSubtitle(playlist),
                isSelected: idx == selectedIndex,
                showsDisclosure: true,
                accessibilityLabel: "\(playlist.name), \(playlist.ownerName)",
                trailingAccessibilityLabel: "minimal.search.queue_all",
                onTap: { onDrillIn(.playlist(playlist)) },
                onTrailingTap: { onEnqueue(.playlist(playlist)) },
            )
            .id(idx)
            MinimalDivider()
        }
    }

    @ViewBuilder
    private var showsList: some View {
        let shows = store.searchResults?.shows ?? []
        ForEach(Array(shows.enumerated()), id: \.offset) { idx, show in
            MinimalSearchResultRow(
                artworkURL: show.images.url(for: 36),
                title: show.name,
                subtitle: showSubtitle(show),
                isSelected: idx == selectedIndex,
                showsDisclosure: true,
                accessibilityLabel: "\(show.name), \(show.publisher)",
                trailingAccessibilityLabel: "minimal.search.queue_latest",
                onTap: { onDrillIn(.show(show)) },
                onTrailingTap: { onEnqueue(.show(show)) },
            )
            .id(idx)
            MinimalDivider()
        }
    }

    /// Album subtitle prefixed with the release type (Album / Single / EP / Compilation),
    /// because singles and tracks otherwise look identical in this list.
    private func albumSubtitle(_ album: Album) -> String {
        let typeKey: String.LocalizationValue = switch album.albumType?.lowercased() {
        case "single": "minimal.search.album_type.single"
        case "compilation": "minimal.search.album_type.compilation"
        case "ep": "minimal.search.album_type.ep"
        default: "minimal.search.album_type.album"
        }
        return "\(String(localized: typeKey)) · \(album.artistName)"
    }

    private func playlistSubtitle(_ playlist: Playlist) -> String {
        String(localized: "minimal.search.playlist_owner \(playlist.ownerName)")
    }

    /// Artist subtitle: top genre if present, else the localized "Artist" label.
    private func artistSubtitle(_ artist: Artist) -> String {
        if let genre = artist.genres.first, !genre.isEmpty {
            return genre.capitalized
        }
        return String(localized: "minimal.search.artist_subtitle")
    }

    private func showSubtitle(_ show: Show) -> String {
        String(localized: "minimal.search.show_publisher \(show.publisher)")
    }

    // MARK: - Helpers

    private var currentResultsCount: Int {
        guard let results = store.searchResults else { return 0 }
        switch filter {
        case .songs: return results.tracks.count
        case .albums: return results.albums.count
        case .artists: return results.artists.count
        case .playlists: return results.playlists.count
        case .podcasts: return results.shows.count
        }
    }

    private func pagination(for filter: MinimalSearchFilter) -> PaginationState {
        switch filter {
        case .songs: store.searchTracksPagination
        case .albums: store.searchAlbumsPagination
        case .artists: store.searchArtistsPagination
        case .playlists: store.searchPlaylistsPagination
        case .podcasts: store.searchShowsPagination
        }
    }

    private func triggerPagination() {
        let activeFilter = filter
        guard pagination(for: activeFilter).hasMore,
              !pagination(for: activeFilter).isLoading
        else { return }

        paginateTask?.cancel()
        paginateTask = Task {
            await searchService.fetchMore(filter: activeFilter, session: session)
        }
    }

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchService.clearSearch()
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await searchService.search(session: session, query: trimmed)
            guard !Task.isCancelled else { return }
            if store.searchErrorMessage == nil {
                recentSearches.record(trimmed)
            }
        }
    }
}
