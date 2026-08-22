//
//  LibrespotAuth.swift
//  NullSpot
//
//  Supplies the OAuth access token used to start the librespot session.
//
//  This is deliberately separate from `SpotifySession`, which holds the Web API
//  token. librespot's native path (clienttoken.spotify.com → access point →
//  login5) only accepts a first-party native client_id, so the Connect token
//  must be minted by `SpotifyConfig.librespotClientId` rather than the Web API
//  app. Handing librespot a Web-API-issued token makes `Spirc::new()` fail with
//  login5 INVALID_CREDENTIALS, which leaves the device unregistered with
//  Spotify Connect and silently breaks all playback.
//

import Foundation

/// Mints, caches, and refreshes the librespot (Spotify Connect) access token.
@MainActor
@Observable
final class LibrespotAuth {
    /// Shared instance. The librespot token is process-wide state (Rust holds a
    /// single session), so it is not per-view.
    static let shared = LibrespotAuth()

    /// Set while an interactive authorization is in flight, so the UI can
    /// explain why a browser window just opened.
    private(set) var isAuthorizing = false

    /// In-memory copy of the stored token, kept so repeated reconnects within a
    /// session don't hit the keychain on every request.
    private var cached: SpotifyAuthResult?
    private var obtainedAt: Date?

    /// Coalesces concurrent callers (player init and Rust's token-request
    /// callback can race) onto a single refresh/authorize.
    private var inFlight: Task<String, Error>?

    init() {
        if let stored = KeychainManager.loadLibrespotAuthResult() {
            cached = stored
            obtainedAt = Date()
        }
    }

    /// Returns a valid librespot access token, refreshing or re-authorizing as
    /// needed. Opens a browser only when there is no usable refresh token.
    func validAccessToken() async throws -> String {
        if let token = unexpiredCachedToken() {
            return token
        }

        if let inFlight {
            return try await inFlight.value
        }

        let task = Task { try await obtainToken() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    /// Drops the stored token so the next request re-authorizes from scratch.
    func reset() {
        cached = nil
        obtainedAt = nil
        KeychainManager.clearLibrespotAuthResult()
    }

    // MARK: - Private

    /// Returns the cached token if it has more than 5 minutes of life left.
    private func unexpiredCachedToken() -> String? {
        guard let cached, let obtainedAt else { return nil }
        let expiresAt = obtainedAt.addingTimeInterval(TimeInterval(cached.expiresIn))
        guard Date().addingTimeInterval(300) < expiresAt else { return nil }
        return cached.accessToken
    }

    private func obtainToken() async throws -> String {
        if let refreshToken = cached?.refreshToken {
            do {
                let refreshed = try await SpotifyAuth.refreshAccessToken(
                    refreshToken: refreshToken,
                    clientId: SpotifyConfig.librespotClientId,
                )
                store(refreshed)
                debugLog("LibrespotAuth", "Refreshed librespot token")
                return refreshed.accessToken
            } catch {
                // Refresh tokens get revoked server-side; fall through to a
                // fresh authorization rather than leaving playback dead.
                debugLog("LibrespotAuth", "Refresh failed (\(error)), re-authorizing")
            }
        }

        return try await authorizeInteractively()
    }

    private func authorizeInteractively() async throws -> String {
        isAuthorizing = true
        defer { isAuthorizing = false }

        debugLog("LibrespotAuth", "Starting librespot authorization")
        let result = try await SpotifyAuth.authenticate(
            clientId: SpotifyConfig.librespotClientId,
            scopes: SpotifyConfig.librespotScopes,
        )
        store(result)
        debugLog("LibrespotAuth", "Obtained librespot token")
        return result.accessToken
    }

    private func store(_ result: SpotifyAuthResult) {
        // Spotify omits refresh_token on refresh responses; keep the existing one.
        let merged = SpotifyAuthResult(
            accessToken: result.accessToken,
            refreshToken: result.refreshToken ?? cached?.refreshToken,
            expiresIn: result.expiresIn,
        )
        cached = merged
        obtainedAt = Date()
        try? KeychainManager.saveLibrespotAuthResult(merged)
    }
}
