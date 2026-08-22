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
                onPlay: { playEntry($0) },
                onRemove: removeEntries,
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
            Task { await appendAndPlay(forAlbum: album) }
        case let .artist(artist):
            Task { await appendAndPlay(forArtist: artist) }
        case let .playlist(pl):
            Task { await appendAndPlay(forPlaylist: pl) }
        case let .show(show):
            Task { await appendAndPlay(forShow: show) }
        }
        exitSearch()
    }

    private func appendAndPlay(forAlbum album: Album) async {
        await appendAndPlay(tracks(forAlbum: album))
    }

    private func appendAndPlay(forArtist artist: Artist) async {
        await appendAndPlay(tracks(forArtist: artist))
    }

    private func appendAndPlay(forPlaylist pl: Playlist) async {
        await appendAndPlay(tracks(forPlaylist: pl))
    }

    private func appendAndPlay(forShow show: Show) async {
        // Episodes arrive newest-first (Spotify default order); appendAndPlay
        // starts from the first (newest) episode.
        await appendAndPlay(tracks(forShow: show))
    }

    // MARK: - Track fetching

    private func tracks(forAlbum album: Album) async -> [Track] {
        await (try? albumService.getAlbumTracks(albumId: album.id, session: session)) ?? []
    }

    private func tracks(forArtist artist: Artist) async -> [Track] {
        await (try? artistService.fetchArtistTopTracks(
            artistId: artist.id,
            session: session,
        )) ?? []
    }

    private func tracks(forPlaylist pl: Playlist) async -> [Track] {
        await (try? playlistService.getPlaylistTracks(playlistId: pl.id, session: session)) ?? []
    }

    private func tracks(forShow show: Show, limit: Int = 50) async -> [Track] {
        await (try? showService.getShowEpisodes(
            showId: show.id,
            showName: show.name,
            showImages: show.images,
            session: session,
            limit: limit,
        )) ?? []
    }

    private func pickTrack(_ track: Track) {
        let entry = playlist.append(track)
        playEntry(entry, resumeFrom: resumeInfo(for: track))
        exitSearch()
    }

    /// Append the given tracks to the end of the queue (existing entries are
    /// preserved) and immediately start playing from the first appended track.
    private func appendAndPlay(_ tracks: [Track]) {
        guard let first = tracks.first else { return }
        var firstEntry: MinimalPlaylist.Entry?
        for track in tracks {
            let entry = playlist.append(track)
            if firstEntry == nil { firstEntry = entry }
        }
        guard let firstEntry else { return }
        playEntry(firstEntry, resumeFrom: resumeInfo(for: first))
    }

    /// Resume position for a partially-played podcast episode, or nil for regular
    /// tracks / unplayed / finished episodes.
    private func resumeInfo(for track: Track) -> (uri: String, positionMs: UInt32)? {
        guard track.fullyPlayed != true, let pos = track.resumePositionMs, pos > 0 else {
            return nil
        }
        return (track.uri, UInt32(clamping: pos))
    }

    /// Trailing "+" on a search row. Containers (album / artist / playlist / show)
    /// are expanded into their tracks first: both Spirc's `add_to_queue` and
    /// `POST /me/player/queue` only accept track and episode URIs, so handing them
    /// a container URI enqueued nothing and never touched the visible queue.
    private func handleEnqueue(_ pick: MinimalSearchPick) {
        switch pick {
        case let .track(track):
            playlist.append(track)
            Task { await playbackViewModel.addToQueue(uri: track.uri, session: session) }
        case let .album(album):
            Task { await enqueue(tracks(forAlbum: album)) }
        case let .artist(artist):
            Task { await enqueue(tracks(forArtist: artist)) }
        case let .playlist(pl):
            Task { await enqueue(tracks(forPlaylist: pl)) }
        case let .show(show):
            Task { await enqueue(tracks(forShow: show, limit: 1)) }
        }
    }

    /// Append the given tracks to the visible queue and mirror them into the live
    /// player queue, without disturbing what is currently playing.
    private func enqueue(_ tracks: [Track]) async {
        guard !tracks.isEmpty else { return }
        for track in tracks {
            playlist.append(track)
            await playbackViewModel.addToQueue(uri: track.uri, session: session)
        }
        // Pull the full queue with metadata in one Web API call instead of letting
        // Mercury's set_queue events trigger N single-track GETs.
        await queueService.refreshQueue()
    }

    // MARK: - Playback helpers

    private func playContext(uri: String) {
        Task { await playbackViewModel.play(uriOrUrl: uri, session: session) }
    }

    private func playEntry(_ entry: MinimalPlaylist.Entry, resumeFrom: (uri: String, positionMs: UInt32)? = nil) {
        playlist.currentEntryId = entry.id
        let uris = playlist.urisStarting(at: entry.id)
        guard !uris.isEmpty else { return }
        Task { await playbackViewModel.playTracks(uris, session: session, resumeFrom: resumeFrom) }
    }

    /// Remove the given entries from the visible list. Local/cosmetic only — the
    /// live librespot queue is left untouched. If the currently-playing entry is
    /// among those removed and rows remain, skip to the next track so audio keeps
    /// going; if nothing remains (e.g. ⌘A then Delete), playback is left alone.
    private func removeEntries(_ ids: Set<UUID>) {
        let removingCurrent = playlist.currentEntryId.map(ids.contains) ?? false
        playlist.remove(entryIds: ids)
        if removingCurrent, !playlist.entries.isEmpty {
            playbackViewModel.next()
        }
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
