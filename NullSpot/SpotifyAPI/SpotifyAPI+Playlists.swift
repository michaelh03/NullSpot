//
//  SpotifyAPI+Playlists.swift
//  NullSpot
//
//  Playlist-related API calls.
//

import Foundation

extension SpotifyAPI {
    // MARK: - User Playlists

    /// Fetches user's playlists from Spotify Web API
    static func fetchUserPlaylists(session: SpotifySession, limit: Int = 50, offset: Int = 0) async throws -> PlaylistsResponse {
        let urlString = "\(baseURL)/me/playlists?limit=\(limit)&offset=\(offset)&fields=items(id,name,uri,description,images,items(total,items(item(duration_ms))),public,owner(id,display_name),external_urls(spotify)),total,next"

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
                        let decoded = try JSONDecoder().decode(UserPlaylistsCodable.self, from: data)
                        let playlists = decoded.items.map { $0.toAPIPlaylist() }
                        let hasMore = decoded.next != nil
                        return PlaylistsResponse(
                            hasMore: hasMore,
                            nextOffset: hasMore ? offset + limit : nil,
                            playlists: playlists,
                            total: decoded.total,
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

    // MARK: - Playlist Details

    /// Fetches a single playlist's details from Spotify Web API
    static func fetchPlaylistDetails(session: SpotifySession, playlistId: String) async throws -> APIPlaylist {
        let urlString = "\(baseURL)/playlists/\(playlistId)?fields=id,name,description,images,items(total,items(item(duration_ms))),uri,public,owner(id,display_name),external_urls(spotify)&market=from_token"

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
                        let playlist = try JSONDecoder().decode(PlaylistCodable.self, from: data)
                        return playlist.toAPIPlaylist()
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

    // MARK: - Playlist Management

    /// Creates a new playlist for the current user
    static func createPlaylist(
        session: SpotifySession,
        name: String,
        description: String? = nil,
        isPublic: Bool = false,
    ) async throws -> APIPlaylist {
        let urlString = "\(baseURL)/me/playlists"

        debugLog("SpotifyAPI", "[POST] \(urlString)")

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        let body: [String: Any] = [
            "name": name,
            "description": description ?? "",
            "public": isPublic,
        ]
        let bodyData = try? JSONSerialization.data(withJSONObject: body)

        return try await performAuthorizedRequest(
            session: session,
            build: { token in
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = bodyData
                return request
            },
            handle: { data, response in
                switch response.statusCode {
                case 200, 201:
                    do {
                        let playlist = try JSONDecoder().decode(PlaylistCodable.self, from: data)
                        return playlist.toAPIPlaylist()
                    } catch {
                        throw SpotifyAPIError.invalidResponse
                    }
                default:
                    try throwAuthorizedError(
                        data: data,
                        statusCode: response.statusCode,
                        forbiddenReason: .contextual(localizedKey: "error.forbidden.create_playlist"),
                    )
                }
            },
        )
    }

    /// Adds tracks to an existing playlist
    static func addTracksToPlaylist(
        session: SpotifySession,
        playlistId: String,
        trackUris: [String],
    ) async throws {
        let urlString = "\(baseURL)/playlists/\(playlistId)/items"

        debugLog("SpotifyAPI", "[POST] \(urlString)")

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        let body: [String: Any] = ["uris": trackUris]
        let bodyData = try? JSONSerialization.data(withJSONObject: body)

        try await performAuthorizedRequest(
            session: session,
            build: { token in
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = bodyData
                return request
            },
            handle: { data, response in
                switch response.statusCode {
                case 201:
                    return
                case 404:
                    throw SpotifyAPIError.notFound
                default:
                    try throwAuthorizedError(
                        data: data,
                        statusCode: response.statusCode,
                        forbiddenReason: .contextual(localizedKey: "error.forbidden.modify_playlist"),
                    )
                }
            },
        )
    }

    /// Updates playlist details (name and/or description)
    static func updatePlaylistDetails(
        session: SpotifySession,
        playlistId: String,
        name: String? = nil,
        description: String? = nil,
    ) async throws {
        let urlString = "\(baseURL)/playlists/\(playlistId)"

        debugLog("SpotifyAPI", "[PUT] \(urlString)")

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let description { body["description"] = description }
        let bodyData = try? JSONSerialization.data(withJSONObject: body)

        try await performAuthorizedRequest(
            session: session,
            build: { token in
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = bodyData
                return request
            },
            handle: { data, response in
                switch response.statusCode {
                case 200:
                    return
                case 404:
                    throw SpotifyAPIError.notFound
                default:
                    try throwAuthorizedError(
                        data: data,
                        statusCode: response.statusCode,
                        forbiddenReason: .contextual(localizedKey: "error.forbidden.modify_playlist"),
                    )
                }
            },
        )
    }

    /// Deletes (unfollows) a playlist
    static func deletePlaylist(session: SpotifySession, playlistId: String) async throws {
        let urlString = "\(baseURL)/me/library"

        debugLog("SpotifyAPI", "[DELETE] \(urlString)")

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        let body = try? JSONSerialization.data(withJSONObject: ["uris": ["spotify:playlist:\(playlistId)"]])

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
                case 200, 204:
                    return
                default:
                    try throwAuthorizedError(
                        data: data,
                        statusCode: response.statusCode,
                        forbiddenReason: .contextual(localizedKey: "error.forbidden.modify_playlist"),
                    )
                }
            },
        )
    }

    /// Follows (saves) a playlist to the user's library
    static func followPlaylist(session: SpotifySession, playlistId: String) async throws {
        let urlString = "\(baseURL)/me/library"

        debugLog("SpotifyAPI", "[PUT] \(urlString)")

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        let body = try? JSONSerialization.data(withJSONObject: ["uris": ["spotify:playlist:\(playlistId)"]])

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
                case 200, 204:
                    return
                default:
                    try throwAuthorizedError(
                        data: data,
                        statusCode: response.statusCode,
                        forbiddenReason: .contextual(localizedKey: "error.forbidden.follow_playlist"),
                    )
                }
            },
        )
    }

    /// Removes tracks from a playlist
    static func removeTracksFromPlaylist(
        session: SpotifySession,
        playlistId: String,
        trackUris: [String],
    ) async throws {
        let urlString = "\(baseURL)/playlists/\(playlistId)/items"

        debugLog("SpotifyAPI", "[DELETE] \(urlString)")

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        let items = trackUris.map { ["uri": $0] }
        let body: [String: Any] = ["items": items]
        let bodyData = try? JSONSerialization.data(withJSONObject: body)

        try await performAuthorizedRequest(
            session: session,
            build: { token in
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = bodyData
                return request
            },
            handle: { data, response in
                switch response.statusCode {
                case 200:
                    return
                case 404:
                    throw SpotifyAPIError.notFound
                default:
                    try throwAuthorizedError(
                        data: data,
                        statusCode: response.statusCode,
                        forbiddenReason: .contextual(localizedKey: "error.forbidden.modify_playlist"),
                    )
                }
            },
        )
    }

    /// Reorders tracks in a playlist
    static func reorderPlaylistTracks(
        session: SpotifySession,
        playlistId: String,
        rangeStart: Int,
        insertBefore: Int,
        rangeLength: Int = 1,
    ) async throws {
        let urlString = "\(baseURL)/playlists/\(playlistId)/items"

        debugLog("SpotifyAPI", "[PUT] \(urlString)")

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        let body: [String: Any] = [
            "range_start": rangeStart,
            "insert_before": insertBefore,
            "range_length": rangeLength,
        ]
        let bodyData = try? JSONSerialization.data(withJSONObject: body)

        try await performAuthorizedRequest(
            session: session,
            build: { token in
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = bodyData
                return request
            },
            handle: { data, response in
                switch response.statusCode {
                case 200:
                    return
                case 404:
                    throw SpotifyAPIError.notFound
                default:
                    try throwAuthorizedError(
                        data: data,
                        statusCode: response.statusCode,
                        forbiddenReason: .contextual(localizedKey: "error.forbidden.modify_playlist"),
                    )
                }
            },
        )
    }

    /// Replaces all tracks in a playlist
    static func replacePlaylistTracks(
        session: SpotifySession,
        playlistId: String,
        trackUris: [String],
    ) async throws {
        let urlString = "\(baseURL)/playlists/\(playlistId)/items"

        debugLog("SpotifyAPI", "[PUT] \(urlString)")

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        let body: [String: Any] = ["uris": trackUris]
        let bodyData = try? JSONSerialization.data(withJSONObject: body)

        try await performAuthorizedRequest(
            session: session,
            build: { token in
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = bodyData
                return request
            },
            handle: { data, response in
                switch response.statusCode {
                case 200, 201:
                    return
                case 404:
                    throw SpotifyAPIError.notFound
                default:
                    try throwAuthorizedError(
                        data: data,
                        statusCode: response.statusCode,
                        forbiddenReason: .contextual(localizedKey: "error.forbidden.modify_playlist"),
                    )
                }
            },
        )
    }
}
