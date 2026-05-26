//
//  SpotifyAPI+Artists.swift
//  NullSpot
//
//  Artist-related API calls.
//

import Foundation

extension SpotifyAPI {
    // MARK: - Artist Details

    /// Fetches a single artist's details from Spotify Web API
    static func fetchArtistDetails(session: SpotifySession, artistId: String) async throws -> APIArtist {
        let urlString = "\(baseURL)/artists/\(artistId)?fields=id,name,uri,genres,images"

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
                        let artist = try JSONDecoder().decode(ArtistCodable.self, from: data)
                        guard let apiArtist = artist.toAPIArtist() else {
                            throw SpotifyAPIError.invalidResponse
                        }
                        return apiArtist
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

    // MARK: - Artist Top Tracks

    /// Fetches an artist's top tracks (catalog metadata, market scoped to the token).
    static func fetchArtistTopTracks(session: SpotifySession, artistId: String) async throws -> [APITrack] {
        let urlString = "\(baseURL)/artists/\(artistId)/top-tracks?market=from_token"

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
                        let decoded = try JSONDecoder().decode(ArtistTopTracksCodable.self, from: data)
                        return decoded.tracks.map { $0.toAPITrack() }
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

    // MARK: - User's Followed Artists

    /// Fetches user's followed artists from Spotify Web API
    static func fetchUserArtists(session: SpotifySession, limit: Int = 50, after: String? = nil) async throws -> ArtistsResponse {
        var urlString = "\(baseURL)/me/following?type=artist&limit=\(limit)"
        if let cursor = after {
            urlString += "&after=\(cursor)"
        }

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
                        let decoded = try JSONDecoder().decode(UserArtistsCodable.self, from: data)
                        let artists = decoded.artists.items.compactMap { $0.toAPIArtist() }
                        let afterCursor = decoded.artists.cursors?.after
                        return ArtistsResponse(
                            artists: artists,
                            hasMore: afterCursor != nil,
                            nextCursor: afterCursor,
                            total: decoded.artists.total,
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

    // MARK: - Unfollow Artist

    /// Unfollows an artist (removes from user's followed artists)
    static func unfollowArtist(session: SpotifySession, artistId: String) async throws {
        let urlString = "\(baseURL)/me/library"

        debugLog("SpotifyAPI", "[DELETE] \(urlString)")

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        let body = try? JSONSerialization.data(withJSONObject: ["uris": ["spotify:artist:\(artistId)"]])

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
                        forbiddenReason: .contextual(localizedKey: "error.forbidden.modify_followed_artists"),
                    )
                }
            },
        )
    }

    // MARK: - Follow Artist

    /// Follows an artist (adds to user's followed artists)
    static func followArtist(session: SpotifySession, artistId: String) async throws {
        let urlString = "\(baseURL)/me/library"

        debugLog("SpotifyAPI", "[PUT] \(urlString)")

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        let body = try? JSONSerialization.data(withJSONObject: ["uris": ["spotify:artist:\(artistId)"]])

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
                        forbiddenReason: .contextual(localizedKey: "error.forbidden.modify_followed_artists"),
                    )
                }
            },
        )
    }

    // MARK: - User's Top Artists

    /// Fetches user's top artists from Spotify Web API
    static func fetchUserTopArtists(
        session: SpotifySession,
        timeRange: TopItemsTimeRange = .mediumTerm,
        limit: Int = 50,
        offset: Int = 0,
    ) async throws -> TopArtistsResponse {
        let urlString = "\(baseURL)/me/top/artists?time_range=\(timeRange.rawValue)&limit=\(limit)&offset=\(offset)"

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
                        let decoded = try JSONDecoder().decode(TopArtistsCodable.self, from: data)
                        let artists = decoded.items.compactMap { $0.toAPIArtist() }
                        let nextOffset = offset + limit
                        let hasMore = nextOffset < decoded.total
                        return TopArtistsResponse(
                            artists: artists,
                            hasMore: hasMore,
                            nextOffset: hasMore ? nextOffset : nil,
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

    // MARK: - User's Top Tracks

    /// Fetches user's top tracks from Spotify Web API
    static func fetchUserTopTracks(
        session: SpotifySession,
        timeRange: TopItemsTimeRange = .mediumTerm,
        limit: Int = 50,
        offset: Int = 0,
    ) async throws -> TopTracksResponse {
        let urlString = "\(baseURL)/me/top/tracks?time_range=\(timeRange.rawValue)&limit=\(limit)&offset=\(offset)"

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
                        let decoded = try JSONDecoder().decode(TopTracksCodable.self, from: data)
                        let tracks = decoded.items.map { $0.toAPITrack() }
                        let nextOffset = offset + limit
                        let hasMore = nextOffset < decoded.total
                        return TopTracksResponse(
                            tracks: tracks,
                            hasMore: hasMore,
                            nextOffset: hasMore ? nextOffset : nil,
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
}
