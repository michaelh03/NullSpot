//
//  SearchService.swift
//  NullSpot
//
//  Service for search functionality.
//  Performs searches and stores returned entities in AppStore.
//

import Foundation

@MainActor
@Observable
final class SearchService {
    private let store: AppStore
    private let pageSize: Int = 10
    private var currentQuery: String = ""

    init(store: AppStore) {
        self.store = store
    }

    // MARK: - Search

    func search(session: SpotifySession, query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            store.clearSearch()
            currentQuery = ""
            return
        }

        guard !store.searchIsLoading else { return }

        store.searchIsLoading = true
        store.searchErrorMessage = nil
        currentQuery = trimmed

        // Reset per-type pagination for a fresh query.
        store.searchTracksPagination.reset()
        store.searchAlbumsPagination.reset()
        store.searchArtistsPagination.reset()
        store.searchPlaylistsPagination.reset()
        store.searchShowsPagination.reset()

        do {
            let results = try await SpotifyAPI.search(
                session: session,
                query: trimmed,
                types: [.track, .album, .artist, .playlist, .show],
                limit: pageSize,
                offset: 0,
            )

            store.setSearchResults(results)
            store.upsertTracks(results.tracks)
            store.upsertAlbums(results.albums)
            store.upsertArtists(results.artists)
            store.upsertPlaylists(results.playlists)
            store.upsertShows(results.shows)

            updatePagination(&store.searchTracksPagination, fetched: results.tracks.count)
            updatePagination(&store.searchAlbumsPagination, fetched: results.albums.count)
            updatePagination(&store.searchArtistsPagination, fetched: results.artists.count)
            updatePagination(&store.searchPlaylistsPagination, fetched: results.playlists.count)
            updatePagination(&store.searchShowsPagination, fetched: results.shows.count)

        } catch {
            store.searchErrorMessage = error.localizedDescription
            store.setSearchResults(nil)
        }

        store.searchIsLoading = false
    }

    /// Loads the next page for a single filter type.
    /// Safe to call repeatedly — guards against duplicate in-flight requests and end-of-results.
    func fetchMore(filter: MinimalSearchFilter, session: SpotifySession) async {
        guard !currentQuery.isEmpty else { return }

        let pagination = pagination(for: filter)
        guard pagination.hasMore, !pagination.isLoading else { return }
        guard let offset = pagination.nextOffset else { return }

        setPaginationLoading(filter, loading: true)
        defer { setPaginationLoading(filter, loading: false) }

        do {
            let results = try await SpotifyAPI.search(
                session: session,
                query: currentQuery,
                types: [filter.searchType],
                limit: pageSize,
                offset: offset,
            )

            switch filter {
            case .songs:
                store.upsertTracks(results.tracks)
                store.appendSearchTracks(results.tracks)
                updatePagination(&store.searchTracksPagination, fetched: results.tracks.count)
            case .albums:
                store.upsertAlbums(results.albums)
                store.appendSearchAlbums(results.albums)
                updatePagination(&store.searchAlbumsPagination, fetched: results.albums.count)
            case .artists:
                store.upsertArtists(results.artists)
                store.appendSearchArtists(results.artists)
                updatePagination(&store.searchArtistsPagination, fetched: results.artists.count)
            case .playlists:
                store.upsertPlaylists(results.playlists)
                store.appendSearchPlaylists(results.playlists)
                updatePagination(&store.searchPlaylistsPagination, fetched: results.playlists.count)
            case .podcasts:
                store.upsertShows(results.shows)
                store.appendSearchShows(results.shows)
                updatePagination(&store.searchShowsPagination, fetched: results.shows.count)
            }
        } catch {
            store.searchErrorMessage = error.localizedDescription
        }
    }

    func clearSearch() {
        currentQuery = ""
        store.clearSearch()
    }

    // MARK: - Pagination helpers

    private func pagination(for filter: MinimalSearchFilter) -> PaginationState {
        switch filter {
        case .songs: store.searchTracksPagination
        case .albums: store.searchAlbumsPagination
        case .artists: store.searchArtistsPagination
        case .playlists: store.searchPlaylistsPagination
        case .podcasts: store.searchShowsPagination
        }
    }

    private func setPaginationLoading(_ filter: MinimalSearchFilter, loading: Bool) {
        switch filter {
        case .songs: store.searchTracksPagination.isLoading = loading
        case .albums: store.searchAlbumsPagination.isLoading = loading
        case .artists: store.searchArtistsPagination.isLoading = loading
        case .playlists: store.searchPlaylistsPagination.isLoading = loading
        case .podcasts: store.searchShowsPagination.isLoading = loading
        }
    }

    private func updatePagination(_ pagination: inout PaginationState, fetched: Int) {
        pagination.isLoaded = true
        pagination.hasMore = fetched == pageSize
        pagination.nextOffset = (pagination.nextOffset ?? 0) + fetched
    }
}
