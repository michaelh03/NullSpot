//
//  SpotifyAPI+Tracks.swift
//  NullSpot
//
//  Track-related API calls.
//

import Foundation

extension SpotifyAPI {
    // MARK: - Single Track

    /// Fetches a single track from Spotify Web API
    static func fetchTrack(trackId: String, session: SpotifySession) async throws -> APITrack {
        let urlString = "\(baseURL)/tracks/\(trackId)"

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
                        let track = try JSONDecoder().decode(TrackCodable.self, from: data)
                        return track.toAPITrack()
                    } catch {
                        throw SpotifyAPIError.invalidResponse
                    }
                case 404:
                    throw SpotifyAPIError.notFound
                default:
                    try throwAuthorizedError(data: data, statusCode: response.statusCode)
                }
            },
        )
    }

    // MARK: - Multiple Tracks

    /// Max concurrent in-flight single-track requests. Spotify's bulk `/v1/tracks?ids=...`
    /// endpoint is deprecated; firing N parallel singles unbounded triggers 429.
    private static let fetchTracksConcurrency = 4

    /// Fetches multiple tracks by their IDs using single-track requests with bounded concurrency.
    /// Returns a dictionary mapping track ID to APITrack (for found tracks).
    static func fetchTracks(session: SpotifySession, trackIds: [String]) async throws -> [String: APITrack] {
        guard !trackIds.isEmpty else { return [:] }

        return try await withThrowingTaskGroup(of: (String, APITrack?).self) { group in
            var iterator = trackIds.makeIterator()
            var inFlight = 0

            func addNext() {
                guard let trackId = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    do {
                        let track = try await fetchTrack(trackId: trackId, session: session)
                        return (trackId, track)
                    } catch SpotifyAPIError.notFound {
                        return (trackId, nil)
                    }
                }
            }

            for _ in 0 ..< min(fetchTracksConcurrency, trackIds.count) {
                addNext()
            }

            var result: [String: APITrack] = [:]
            while inFlight > 0, let (id, track) = try await group.next() {
                inFlight -= 1
                if let track {
                    result[id] = track
                }
                addNext()
            }
            return result
        }
    }

    // MARK: - Saved Tracks (Favorites)

    /// Fetches user's saved tracks (favorites) from Spotify Web API
    static func fetchUserSavedTracks(session: SpotifySession, limit: Int = 50, offset: Int = 0) async throws -> SavedTracksResponse {
        let urlString = "\(baseURL)/me/tracks?limit=\(limit)&offset=\(offset)&fields=items(added_at,track(id,name,uri,duration_ms,artists(id,name),album(id,name,images),external_urls(spotify))),total,next"

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
                        let decoded = try JSONDecoder().decode(SavedTracksCodable.self, from: data)
                        let tracks = decoded.items.map { item in
                            item.track.toAPITrack(addedAt: item.addedAt)
                        }
                        let hasMore = decoded.next != nil
                        return SavedTracksResponse(
                            hasMore: hasMore,
                            nextOffset: hasMore ? offset + limit : nil,
                            total: decoded.total,
                            tracks: tracks,
                        )
                    } catch {
                        throw SpotifyAPIError.invalidResponse
                    }
                case 404:
                    throw SpotifyAPIError.notFound
                default:
                    try throwAuthorizedError(data: data, statusCode: response.statusCode)
                }
            },
        )
    }

    /// Saves a track to user's library
    static func saveTrack(session: SpotifySession, trackId: String) async throws {
        let urlString = "\(baseURL)/me/library"

        debugLog("SpotifyAPI", "[PUT] \(urlString)")

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        let body = try? JSONSerialization.data(withJSONObject: ["uris": ["spotify:track:\(trackId)"]])

        try await performAuthorizedRequest(
            session: session,
            build: { token in
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = body
                return request
            },
            handle: { data, response in
                switch response.statusCode {
                case 200, 201:
                    return
                default:
                    try throwAuthorizedError(
                        data: data,
                        statusCode: response.statusCode,
                        forbiddenReason: .contextual(localizedKey: "error.forbidden.modify_library"),
                    )
                }
            },
        )
    }

    /// Checks if a track is saved in user's library
    static func checkSavedTrack(session: SpotifySession, trackId: String) async throws -> Bool {
        let results = try await checkSavedTracks(session: session, trackIds: [trackId])
        return results[trackId] ?? false
    }

    /// Checks if multiple tracks are saved in user's library
    static func checkSavedTracks(session: SpotifySession, trackIds: [String]) async throws -> [String: Bool] {
        guard !trackIds.isEmpty else { return [:] }

        let uris = trackIds.map { "spotify:track:\($0)" }.joined(separator: ",")
        guard let encodedUris = uris.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw SpotifyAPIError.invalidURI
        }
        let urlString = "\(baseURL)/me/library/contains?uris=\(encodedUris)"

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
                        let results = try JSONDecoder().decode([Bool].self, from: data)
                        var dict: [String: Bool] = [:]
                        for (index, trackId) in trackIds.enumerated() where index < results.count {
                            dict[trackId] = results[index]
                        }
                        return dict
                    } catch {
                        throw SpotifyAPIError.invalidResponse
                    }
                default:
                    try throwAuthorizedError(data: data, statusCode: response.statusCode)
                }
            },
        )
    }

    /// Removes a track from user's library
    static func removeSavedTrack(session: SpotifySession, trackId: String) async throws {
        let urlString = "\(baseURL)/me/library"

        debugLog("SpotifyAPI", "[DELETE] \(urlString)")

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        let body = try? JSONSerialization.data(withJSONObject: ["uris": ["spotify:track:\(trackId)"]])

        try await performAuthorizedRequest(
            session: session,
            build: { token in
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = body
                return request
            },
            handle: { data, response in
                switch response.statusCode {
                case 200:
                    return
                default:
                    try throwAuthorizedError(
                        data: data,
                        statusCode: response.statusCode,
                        forbiddenReason: .contextual(localizedKey: "error.forbidden.modify_library"),
                    )
                }
            },
        )
    }

    // MARK: - Album Tracks

    /// Fetches tracks for a specific album
    static func fetchAlbumTracks(
        session: SpotifySession,
        albumId: String,
        albumName: String? = nil,
        images: ImageSet = ImageSet.empty,
    ) async throws -> [APITrack] {
        let urlString = "\(baseURL)/albums/\(albumId)/tracks?limit=50&fields=items(id,name,uri,duration_ms,track_number,artists(id,name),external_urls(spotify))"

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
                        let decoded = try JSONDecoder().decode(AlbumTracksCodable.self, from: data)
                        return decoded.items.map { $0.toAPITrack(albumId: albumId, albumName: albumName, images: images) }
                    } catch {
                        throw SpotifyAPIError.invalidResponse
                    }
                case 404:
                    throw SpotifyAPIError.notFound
                default:
                    try throwAuthorizedError(data: data, statusCode: response.statusCode)
                }
            },
        )
    }

    // MARK: - Playlist Tracks

    /// Fetches tracks for a specific playlist
    static func fetchPlaylistTracks(session: SpotifySession, playlistId: String) async throws -> [APITrack] {
        let urlString = "\(baseURL)/playlists/\(playlistId)/tracks?limit=100&fields=items(added_at,track(id,name,uri,duration_ms,artists(id,name),album(id,name,images),external_urls(spotify)))&market=from_token"

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
                        let decoded = try JSONDecoder().decode(PlaylistItemsCodable.self, from: data)
                        return decoded.items.compactMap { item in
                            item.track?.toAPITrack(addedAt: item.addedAt)
                        }
                    } catch {
                        throw SpotifyAPIError.invalidResponse
                    }
                case 404:
                    throw SpotifyAPIError.notFound
                default:
                    try throwAuthorizedError(data: data, statusCode: response.statusCode)
                }
            },
        )
    }
}
