//
//  SpotifyAPI+Search.swift
//  NullSpot
//
//  Search API calls.
//

import Foundation

extension SpotifyAPI {
    // MARK: - Search

    /// Searches Spotify for tracks, albums, artists, playlists, and shows
    static func search(
        session: SpotifySession,
        query: String,
        types: [SearchType] = [.track, .album, .artist, .playlist, .show],
        limit: Int = 10,
        offset: Int = 0,
    ) async throws -> SearchResults {
        let typesString = types.map(\.rawValue).joined(separator: ",")
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "\(baseURL)/search?q=\(encodedQuery)&type=\(typesString)&limit=\(limit)&offset=\(offset)&market=from_token"
        debugLog("SpotifyAPI", "[GET] \(urlString)")

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        return try await performAuthorizedRequest(
            session: session,
            build: { token in
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return request
            },
            handle: { data, response in
                switch response.statusCode {
                case 200:
                    do {
                        let decoded = try JSONDecoder().decode(SearchResultsCodable.self, from: data)

                        // Convert tracks
                        let tracks: [Track] = decoded.tracks?.items?.map { track in
                            let artist = track.artists?.first
                            return Track(
                                id: track.id,
                                name: track.name,
                                uri: track.uri,
                                durationMs: track.durationMs,
                                trackNumber: track.trackNumber,
                                externalUrl: track.externalUrls?.spotify,
                                albumId: track.album?.id,
                                artistId: artist?.id,
                                artistName: artist?.name ?? "Unknown",
                                albumName: track.album?.name,
                                images: track.album?.images?.toImageSet ?? ImageSet.empty,
                            )
                        } ?? []

                        // Convert albums
                        let albums: [Album] = decoded.albums?.items?.map { album in
                            let artist = album.artists?.first
                            return Album(
                                id: album.id,
                                name: album.name,
                                uri: album.uri,
                                images: album.images?.toImageSet ?? ImageSet.empty,
                                releaseDate: album.releaseDate,
                                albumType: album.albumType,
                                externalUrl: album.externalUrls?.spotify,
                                artistId: artist?.id,
                                artistName: artist?.name ?? "Unknown",
                                trackIds: [],
                                totalDurationMs: nil,
                                knownTrackCount: album.totalTracks ?? 0,
                            )
                        } ?? []

                        // Convert artists
                        let artists: [Artist] = decoded.artists?.items?.compactMap { artist -> Artist? in
                            guard let id = artist.id, let uri = artist.uri else { return nil }
                            return Artist(
                                id: id,
                                name: artist.name,
                                uri: uri,
                                images: artist.images?.toImageSet ?? ImageSet.empty,
                                genres: artist.genres ?? [],
                                externalUrl: artist.externalUrls?.spotify,
                            )
                        } ?? []

                        // Convert playlists (filter out null items for deleted/unavailable playlists)
                        let playlists: [Playlist] = decoded.playlists?.items?.compactMap { playlist -> Playlist? in
                            guard let playlist else { return nil }
                            return Playlist(
                                id: playlist.id,
                                name: playlist.name,
                                description: playlist.description,
                                images: playlist.images?.toImageSet ?? ImageSet.empty,
                                uri: playlist.uri,
                                isPublic: playlist.public ?? true,
                                ownerId: playlist.owner.id,
                                ownerName: playlist.owner.displayName ?? playlist.owner.id,
                                externalUrl: playlist.externalUrls?.spotify,
                                trackIds: [],
                                totalDurationMs: nil,
                                knownTrackCount: playlist.tracks?.total ?? 0,
                            )
                        } ?? []

                        // Convert shows (filter out null items for unavailable shows)
                        let shows: [Show] = decoded.shows?.items?.compactMap { show -> Show? in
                            show?.toShow()
                        } ?? []

                        return SearchResults(
                            albums: albums,
                            artists: artists,
                            playlists: playlists,
                            tracks: tracks,
                            shows: shows,
                        )
                    } catch {
                        debugLog("SpotifyAPI", "[Search] Decoding error: \(error)")
                        if let jsonString = String(data: data, encoding: .utf8) {
                            debugLog("SpotifyAPI", "[Search] Response: \(String(jsonString.prefix(500)))")
                        }
                        throw SpotifyAPIError.invalidResponse
                    }
                default:
                    try throwAuthorizedError(data: data, statusCode: response.statusCode)
                }
            },
        )
    }
}
