//
//  SpotifyAPI+Albums.swift
//  NullSpot
//
//  Album-related API calls.
//

import Foundation

extension SpotifyAPI {
    // MARK: - Album Details

    /// Fetches a single album's details from Spotify Web API
    static func fetchAlbumDetails(session: SpotifySession, albumId: String) async throws -> APIAlbum {
        let urlString = "\(baseURL)/albums/\(albumId)?fields=id,name,uri,total_tracks,release_date,artists(id,name),images,tracks(items(duration_ms)),external_urls(spotify)"

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
                        let album = try JSONDecoder().decode(AlbumCodable.self, from: data)
                        return album.toAPIAlbum()
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

    // MARK: - User's Saved Albums

    /// Fetches user's saved albums from Spotify Web API
    static func fetchUserAlbums(session: SpotifySession, limit: Int = 50, offset: Int = 0) async throws -> AlbumsResponse {
        let urlString = "\(baseURL)/me/albums?limit=\(limit)&offset=\(offset)&fields=items(album(id,name,uri,total_tracks,release_date,album_type,artists(id,name),images,tracks(items(duration_ms)),external_urls(spotify))),total,next"

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
                        let decoded = try JSONDecoder().decode(UserAlbumsCodable.self, from: data)
                        let albums = decoded.items.map { $0.album.toAPIAlbum() }
                        let hasMore = decoded.next != nil
                        return AlbumsResponse(
                            albums: albums,
                            hasMore: hasMore,
                            nextOffset: hasMore ? offset + limit : nil,
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

    // MARK: - Artist Albums

    /// Fetches albums for a specific artist
    static func fetchArtistAlbums(
        session: SpotifySession,
        artistId: String,
        limit: Int = 50,
    ) async throws -> [APIAlbum] {
        let urlString = "\(baseURL)/artists/\(artistId)/albums?include_groups=album,single&market=from_token&limit=\(limit)"

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
                        let decoded = try JSONDecoder().decode(ArtistAlbumsCodable.self, from: data)
                        return decoded.items.map { $0.toAPIAlbum() }
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

    // MARK: - Remove Saved Album

    /// Removes an album from the user's library
    static func removeUserAlbum(session: SpotifySession, albumId: String) async throws {
        let urlString = "\(baseURL)/me/library"

        debugLog("SpotifyAPI", "[DELETE] \(urlString)")

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        let body = try? JSONSerialization.data(withJSONObject: ["uris": ["spotify:album:\(albumId)"]])

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

    // MARK: - Save Album

    /// Saves an album to the user's library
    static func saveUserAlbum(session: SpotifySession, albumId: String) async throws {
        let urlString = "\(baseURL)/me/library"

        debugLog("SpotifyAPI", "[PUT] \(urlString)")

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        let body = try? JSONSerialization.data(withJSONObject: ["uris": ["spotify:album:\(albumId)"]])

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
}
