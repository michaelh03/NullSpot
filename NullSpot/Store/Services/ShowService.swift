//
//  ShowService.swift
//  NullSpot
//
//  Service for show (podcast) related operations.
//  Episodes are exposed as synthetic Track values so they flow through the
//  existing MinimalPlaylist / PlaybackViewModel / SpotifyPlayer pipeline
//  unchanged — librespot accepts `spotify:episode:...` URIs in `uris` arrays
//  and queue endpoints just like track URIs.
//

import Foundation

@MainActor
@Observable
final class ShowService {
    private let store: AppStore

    init(store: AppStore) {
        self.store = store
    }

    // MARK: - Episodes

    /// Fetch a show's episodes (newest first per Spotify default) and return
    /// them as synthetic `Track` values. The show's name is reused as the
    /// "artist" + "album" for display purposes; episode artwork falls back to
    /// the show's artwork when an episode has none of its own.
    func getShowEpisodes(
        showId: String,
        showName: String,
        showImages: ImageSet,
        session: SpotifySession,
        limit: Int = 50,
        offset: Int = 0,
    ) async throws -> [Track] {
        let episodes = try await SpotifyAPI.getShowEpisodes(
            session: session,
            showId: showId,
            limit: limit,
            offset: offset,
        )

        return episodes.map { episode in
            let images = episode.images?.toImageSet ?? showImages
            return Track(
                id: episode.id,
                name: episode.name,
                uri: episode.uri,
                durationMs: episode.durationMs,
                trackNumber: nil,
                externalUrl: episode.externalUrls?.spotify,
                albumId: nil,
                artistId: nil,
                artistName: showName,
                albumName: showName,
                images: images,
                resumePositionMs: episode.resumePoint?.resumePositionMs,
                fullyPlayed: episode.resumePoint?.fullyPlayed,
            )
        }
    }
}
