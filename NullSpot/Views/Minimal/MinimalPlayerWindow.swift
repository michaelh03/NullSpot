//
//  MinimalPlayerWindow.swift
//  NullSpot
//

import SwiftUI

struct MinimalPlayerWindow: View {
    enum Field: Hashable {
        case search
        case searchDetail
        case playlist
    }

    @Environment(AppStore.self) private var store
    @Environment(SpotifySession.self) private var session
    @Environment(MinimalPlaylist.self) private var playlist
    @Environment(RecentSearchesStore.self) private var recentSearches
    @Environment(QueueService.self) private var queueService
    @Environment(AlbumService.self) private var albumService
    @Environment(ArtistService.self) private var artistService
    @Environment(PlaylistService.self) private var playlistService
    @Environment(ShowService.self) private var showService
    @Environment(SearchService.self) private var searchService

    private let playbackViewModel = PlaybackViewModel.shared

    @State private var isSearching = false
    @State private var searchText = ""
    @State private var selectedSearchIndex = 0
    @State private var searchFilter: MinimalSearchFilter = .songs
    @State private var searchDetail: MinimalSearchDetail?
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: 0) {
            MinimalHeaderBar(
                isSearching: $isSearching,
                searchText: $searchText,
                selectedSearchIndex: $selectedSearchIndex,
                resultCount: visibleRowCount,
                focusedField: $focusedField,
                onSubmit: submitSelectedResult,
                onSubmitEnqueue: enqueueSelectedResult,
                onCycleFilter: { searchFilter = searchFilter.next() },
            )
            MinimalDivider()
            MinimalPlayerControls()
            MinimalDivider()
            middleContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: MinimalTheme.windowWidth, height: MinimalTheme.windowHeight)
        .background(MinimalTheme.bg)
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.18), value: isSearching)
        .onChange(of: searchText) { _, _ in
            selectedSearchIndex = 0
        }
        .onChange(of: searchFilter) { _, _ in
            selectedSearchIndex = 0
        }
        .onChange(of: isSearching) { _, newValue in
            focusedField = newValue ? .search : .playlist
            if newValue {
                // Always reset filter when opening search.
                searchFilter = .songs
            } else {
                searchDetail = nil
                searchService.clearSearch()
            }
        }
        .onChange(of: searchDetail) { _, newValue in
            // Move focus into the detail view so Return plays the highlighted
            // track; restore focus to the search field when the user backs out.
            focusedField = newValue == nil ? .search : .searchDetail
        }
        .onChange(of: playbackViewModel.currentTrackUri) { _, newUri in
            syncCurrentEntry(uri: newUri)
        }
        .onAppear {
            syncCurrentEntry(uri: playbackViewModel.currentTrackUri)
            focusedField = .playlist
        }
        .onWindowVisibilityChange { visible in
            VisualizerTap.shared.setWindowVisible(visible)
        }
    }

    @ViewBuilder
    private var middleContent: some View {
        if isSearching {
            if let detail = searchDetail {
                MinimalSearchDetailView(
                    detail: detail,
                    focusedField: $focusedField,
                    onBack: { searchDetail = nil },
                    onPlayAll: { playAllForDetail(detail) },
                    onPlayTrack: { track, all in playFromDetail(picked: track, allTracks: all) },
                    onPickTrack: { track in pickTrack(track) },
                    onEnqueueTrack: { track in
                        playlist.append(track)
                        Task { await playbackViewModel.addToQueue(uri: track.uri, session: session) }
                    },
                )
                .transition(.opacity)
            } else {
                MinimalSearchResultsView(
                    searchText: $searchText,
                    selectedIndex: $selectedSearchIndex,
                    filter: $searchFilter,
                    onPick: handlePick,
                    onEnqueue: handleEnqueue,
                    onDrillIn: { searchDetail = $0 },
                )
                .transition(.opacity)
            }
        } else {
            MinimalPlaylistView(
                onPlay: playEntry,
                focusedField: $focusedField,
            )
            .transition(.opacity)
        }
    }

    // MARK: - Row counts (for header bar's arrow-key clamping)

    private var visibleRowCount: Int {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return recentSearches.entries.count
        }
        switch searchFilter {
        case .songs: return store.searchResults?.tracks.count ?? 0
        case .albums: return store.searchResults?.albums.count ?? 0
        case .artists: return store.searchResults?.artists.count ?? 0
        case .playlists: return store.searchResults?.playlists.count ?? 0
        case .podcasts: return store.searchResults?.shows.count ?? 0
        }
    }

    // MARK: - Submit (Return / Cmd+Return)

    /// Return key: play tracks, drill into albums/playlists/shows.
    private func submitSelectedResult() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let entries = recentSearches.entries
            guard entries.indices.contains(selectedSearchIndex) else { return }
            searchText = entries[selectedSearchIndex]
            return
        }

        guard let pick = currentSelectionPick() else { return }
        handlePick(pick)
    }

    /// Cmd+Return: enqueue current selection (same as the row's trailing + button).
    private func enqueueSelectedResult() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let pick = currentSelectionPick() else { return }
        handleEnqueue(pick)
    }

    private func currentSelectionPick() -> MinimalSearchPick? {
        guard let results = store.searchResults else { return nil }
        switch searchFilter {
        case .songs:
            guard results.tracks.indices.contains(selectedSearchIndex) else { return nil }
            return .track(results.tracks[selectedSearchIndex])
        case .albums:
            guard results.albums.indices.contains(selectedSearchIndex) else { return nil }
            return .album(results.albums[selectedSearchIndex])
        case .artists:
            guard results.artists.indices.contains(selectedSearchIndex) else { return nil }
            return .artist(results.artists[selectedSearchIndex])
        case .playlists:
            guard results.playlists.indices.contains(selectedSearchIndex) else { return nil }
            return .playlist(results.playlists[selectedSearchIndex])
        case .podcasts:
            guard results.shows.indices.contains(selectedSearchIndex) else { return nil }
            return .show(results.shows[selectedSearchIndex])
        }
    }

    // MARK: - Pick handlers

    private func handlePick(_ pick: MinimalSearchPick) {
        switch pick {
        case let .track(track):
            pickTrack(track)
        case let .album(album):
            searchDetail = .album(album)
        case let .artist(artist):
            searchDetail = .artist(artist)
        case let .playlist(pl):
            searchDetail = .playlist(pl)
        case let .show(show):
            searchDetail = .show(show)
        }
    }

    private func playAllForDetail(_ detail: MinimalSearchDetail) {
        switch detail {
        case let .album(album):
            Task { await replaceAndPlay(forAlbum: album) }
        case let .artist(artist):
            Task { await replaceAndPlay(forArtist: artist) }
        case let .playlist(pl):
            Task { await replaceAndPlay(forPlaylist: pl) }
        case let .show(show):
            Task { await replaceAndPlay(forShow: show) }
        }
        exitSearch()
    }

    private func replaceAndPlay(forAlbum album: Album) async {
        let tracks = await (try? albumService.getAlbumTracks(albumId: album.id, session: session)) ?? []
        playlist.clear()
        for track in tracks {
            playlist.append(track)
        }
        await playbackViewModel.play(uriOrUrl: album.uri, session: session)
    }

    private func replaceAndPlay(forArtist artist: Artist) async {
        let tracks = await (try? artistService.fetchArtistTopTracks(
            artistId: artist.id,
            session: session,
        )) ?? []
        guard !tracks.isEmpty else { return }
        playlist.clear()
        for track in tracks {
            playlist.append(track)
        }
        await playbackViewModel.playTracks(tracks.map(\.uri), session: session)
    }

    private func replaceAndPlay(forPlaylist pl: Playlist) async {
        let tracks = await (try? playlistService.getPlaylistTracks(playlistId: pl.id, session: session)) ?? []
        playlist.clear()
        for track in tracks {
            playlist.append(track)
        }
        await playbackViewModel.play(uriOrUrl: pl.uri, session: session)
    }

    private func replaceAndPlay(forShow show: Show) async {
        let episodes = await (try? showService.getShowEpisodes(
            showId: show.id,
            showName: show.name,
            showImages: show.images,
            session: session,
        )) ?? []
        guard !episodes.isEmpty else { return }
        playlist.clear()
        for episode in episodes {
            playlist.append(episode)
        }
        // playTracks plays uris[0] first — newest episode (Spotify default order).
        await playbackViewModel.playTracks(episodes.map(\.uri), session: session)
    }

    private func pickTrack(_ track: Track) {
        let entry = playlist.append(track)
        if playbackViewModel.currentTrackUri == nil {
            playEntry(entry)
        } else {
            let uri = track.uri
            Task { await playbackViewModel.addToQueue(uri: uri, session: session) }
        }
        exitSearch()
    }

    private func handleEnqueue(_ pick: MinimalSearchPick) {
        switch pick {
        case let .track(track):
            playlist.append(track)
            Task { await playbackViewModel.addToQueue(uri: track.uri, session: session) }
        case let .album(album):
            Task {
                await playbackViewModel.addToQueue(uri: album.uri, session: session)
                // For album/playlist enqueue, pull the full queue with metadata in one Web API call
                // instead of letting Mercury's set_queue event trigger N single-track GETs.
                await queueService.refreshQueue()
            }
        case let .artist(artist):
            Task { await enqueueTopTracks(forArtist: artist) }
        case let .playlist(pl):
            Task {
                await playbackViewModel.addToQueue(uri: pl.uri, session: session)
                await queueService.refreshQueue()
            }
        case let .show(show):
            Task { await enqueueLatestEpisode(forShow: show) }
        }
    }

    private func enqueueTopTracks(forArtist artist: Artist) async {
        let tracks = await (try? artistService.fetchArtistTopTracks(
            artistId: artist.id,
            session: session,
        )) ?? []
        guard !tracks.isEmpty else { return }
        for track in tracks {
            playlist.append(track)
            await playbackViewModel.addToQueue(uri: track.uri, session: session)
        }
        await queueService.refreshQueue()
    }

    private func enqueueLatestEpisode(forShow show: Show) async {
        let episodes = await (try? showService.getShowEpisodes(
            showId: show.id,
            showName: show.name,
            showImages: show.images,
            session: session,
            limit: 1,
        )) ?? []
        guard let latest = episodes.first else { return }
        await playbackViewModel.addToQueue(uri: latest.uri, session: session)
    }

    // MARK: - Playback helpers

    private func playContext(uri: String) {
        Task { await playbackViewModel.play(uriOrUrl: uri, session: session) }
    }

    private func playEntry(_ entry: MinimalPlaylist.Entry) {
        playlist.currentEntryId = entry.id
        let uris = playlist.urisStarting(at: entry.id)
        guard !uris.isEmpty else { return }
        Task { await playbackViewModel.playTracks(uris, session: session) }
    }

    /// Load the full track list into the Minimal playlist and start playback
    /// at the picked track. Used when the user clicks a single track inside the
    /// drill-in detail view (album / playlist / show).
    private func playFromDetail(picked: Track, allTracks: [Track]) {
        guard !allTracks.isEmpty else { return }
        playlist.clear()
        var pickedEntryId: UUID?
        for track in allTracks {
            let entry = playlist.append(track)
            if track.id == picked.id, pickedEntryId == nil {
                pickedEntryId = entry.id
            }
        }
        guard let pickedEntryId else { return }
        playlist.currentEntryId = pickedEntryId
        let uris = playlist.urisStarting(at: pickedEntryId)
        guard !uris.isEmpty else { return }
        // Resume a partially-played podcast episode from its saved position.
        var resumeFrom: (uri: String, positionMs: UInt32)?
        if picked.fullyPlayed != true, let pos = picked.resumePositionMs, pos > 0 {
            resumeFrom = (picked.uri, UInt32(clamping: pos))
        }
        Task { await playbackViewModel.playTracks(uris, session: session, resumeFrom: resumeFrom) }
        exitSearch()
    }

    private func syncCurrentEntry(uri: String?) {
        guard let uri else {
            playlist.currentEntryId = nil
            return
        }
        playlist.currentEntryId = playlist.entry(matchingUri: uri)?.id
    }

    private func exitSearch() {
        isSearching = false
        searchText = ""
        selectedSearchIndex = 0
        searchDetail = nil
    }
}
