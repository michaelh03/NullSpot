//
//  SpotifyAPI.swift
//  NullSpot
//
//  Spotify Web API client - base definitions and utilities.
//

import Foundation

/// Spotify item types for generating external URLs
enum SpotifyItemType: String {
    case track
    case album
    case artist
    case playlist
    case user
}

/// Generates a Spotify external URL from item type and ID
func spotifyExternalUrl(type: SpotifyItemType, id: String) -> String {
    "https://open.spotify.com/\(type.rawValue)/\(id)"
}

/// Spotify Web API client
enum SpotifyAPI {
    static let baseURL = "https://api.spotify.com/v1"

    /// Helper to throw appropriate error from API error response data
    static func throwAPIError(data: Data, statusCode: Int) throws -> Never {
        if let errorResponse = try? JSONDecoder().decode(SpotifyErrorResponse.self, from: data) {
            throw SpotifyAPIError.apiError(errorResponse.error.message)
        }
        throw SpotifyAPIError.apiError("HTTP \(statusCode)")
    }

    /// Centralised classification for auth-relevant status codes. Endpoints route
    /// their `default:` case here (and may also route 403 explicitly when they want
    /// to attach a contextual reason via `forbiddenReason`).
    ///
    /// - 401 → `.unauthorized` (caught by `performAuthorizedRequest` to trigger
    ///   one retry after invalidating the cached token).
    /// - 403 → `.forbidden(reason)` where `reason` is parsed from the Spotify
    ///   error body's `reason` field (player endpoints), or supplied by the caller
    ///   via `forbiddenReason` for domain-specific cases (e.g. "can't modify this
    ///   playlist").
    /// - Otherwise → delegates to `throwAPIError`.
    static func throwAuthorizedError(
        data: Data,
        statusCode: Int,
        forbiddenReason: ForbiddenReason? = nil,
    ) throws -> Never {
        switch statusCode {
        case 401:
            throw SpotifyAPIError.unauthorized
        case 403:
            if let forbiddenReason {
                throw SpotifyAPIError.forbidden(forbiddenReason)
            }
            let errorBody = (try? JSONDecoder().decode(SpotifyErrorResponse.self, from: data))?.error
            #if DEBUG
                let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                debugLog(
                    "SpotifyAPI",
                    "[403] reason=\(errorBody?.reason ?? "nil") message=\(errorBody?.message ?? "nil") body=\(rawBody)",
                )
            #endif
            throw SpotifyAPIError.forbidden(
                ForbiddenReason(rawReason: errorBody?.reason, message: errorBody?.message),
            )
        default:
            try throwAPIError(data: data, statusCode: statusCode)
        }
    }

    /// Performs a Bearer-authenticated request and on 401 invalidates the cached
    /// token, fetches a fresh one, and retries the request exactly once.
    ///
    /// `build` constructs the `URLRequest` given a fresh access token; it is
    /// called up to twice. `handle` interprets the response — it should call
    /// `throwAuthorizedError(data:statusCode:)` (or throw `.unauthorized` directly)
    /// for failures so the retry logic can pick it up.
    static func performAuthorizedRequest<T>(
        session: SpotifySession,
        build: (String) -> URLRequest,
        handle: (Data, HTTPURLResponse) throws -> T,
    ) async throws -> T {
        let firstToken = await session.validAccessToken()
        do {
            return try await attemptRequest(token: firstToken, build: build, handle: handle)
        } catch SpotifyAPIError.unauthorized {
            // Token was rejected despite passing the local expiry check. Force a
            // refresh and retry exactly once.
            session.invalidateToken()
            let retryToken = await session.validAccessToken()
            // If invalidate+refresh returned the same token, the refresh itself
            // failed — don't retry, just rethrow so the caller surfaces re-login.
            guard retryToken != firstToken else {
                throw SpotifyAPIError.unauthorized
            }
            return try await attemptRequest(token: retryToken, build: build, handle: handle)
        }
    }

    private static func attemptRequest<T>(
        token: String,
        build: (String) -> URLRequest,
        handle: (Data, HTTPURLResponse) throws -> T,
    ) async throws -> T {
        let request = build(token)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SpotifyAPIError.networkError(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyAPIError.invalidResponse
        }
        return try handle(data, httpResponse)
    }

    /// Parses a Spotify URI (spotify:track:xxx) and returns the track ID
    static func parseTrackURI(_ uri: String) -> String? {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle spotify:track:ID format
        if trimmed.hasPrefix("spotify:track:") {
            return String(trimmed.dropFirst("spotify:track:".count))
        }

        // Handle open.spotify.com/track/ID format
        if trimmed.contains("open.spotify.com/track/") {
            if let range = trimmed.range(of: "open.spotify.com/track/") {
                var trackId = String(trimmed[range.upperBound...])
                // Remove query parameters if present
                if let queryIndex = trackId.firstIndex(of: "?") {
                    trackId = String(trackId[..<queryIndex])
                }
                return trackId.isEmpty ? nil : trackId
            }
        }

        return nil
    }
}
