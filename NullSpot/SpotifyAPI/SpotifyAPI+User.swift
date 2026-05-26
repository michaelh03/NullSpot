//
//  SpotifyAPI+User.swift
//  NullSpot
//
//  User-related API calls.
//

import Foundation

extension SpotifyAPI {
    // MARK: - User Profile

    /// Gets the current user's full profile
    static func getCurrentUserProfile(session: SpotifySession) async throws -> UserProfile {
        let urlString = "\(baseURL)/me"

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
                        let codable = try JSONDecoder().decode(UserProfileCodable.self, from: data)
                        return UserProfile(from: codable)
                    } catch {
                        throw SpotifyAPIError.invalidResponse
                    }
                default:
                    // A 403 on /me means the Spotify app's allowlist doesn't include
                    // this user; surface that specific message rather than the
                    // generic "access denied".
                    try throwAuthorizedError(
                        data: data,
                        statusCode: response.statusCode,
                        forbiddenReason: .userNotRegistered,
                    )
                }
            },
        )
    }

    // MARK: - Recently Played

    /// Fetches the user's recently played tracks
    static func fetchRecentlyPlayed(session: SpotifySession, limit: Int = 50) async throws -> RecentlyPlayedResponse {
        let urlString = "\(baseURL)/me/player/recently-played?limit=\(limit)"

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
                        let decoded = try JSONDecoder().decode(RecentlyPlayedCodable.self, from: data)
                        return decoded.toRecentlyPlayedResponse()
                    } catch {
                        throw SpotifyAPIError.invalidResponse
                    }
                default:
                    try throwAuthorizedError(data: data, statusCode: response.statusCode)
                }
            },
        )
    }
}
