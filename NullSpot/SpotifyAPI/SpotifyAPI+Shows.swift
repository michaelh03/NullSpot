//
//  SpotifyAPI+Shows.swift
//  NullSpot
//
//  Show / podcast related API calls.
//

import Foundation

extension SpotifyAPI {
    // MARK: - Show Episodes

    /// Fetches a show's episodes (newest first by Spotify default).
    static func getShowEpisodes(
        session: SpotifySession,
        showId: String,
        limit: Int = 50,
        offset: Int = 0,
    ) async throws -> [SimplifiedEpisodeCodable] {
        let urlString = "\(baseURL)/shows/\(showId)/episodes?limit=\(limit)&offset=\(offset)&market=from_token"

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
                        let decoded = try JSONDecoder().decode(SimplifiedEpisodePagingCodable.self, from: data)
                        return decoded.items?.compactMap(\.self) ?? []
                    } catch {
                        debugLog("SpotifyAPI", "[Shows] Decoding error: \(error)")
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
