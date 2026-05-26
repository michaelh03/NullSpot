//
//  SpotifyConfig.swift
//  NullSpot
//
//  Configuration for Spotify API credentials
//

import Foundation

enum SpotifyConfig {
    // ncspot's published Web API client_id. Same one spotify-player uses via
    // rspotify. It's a production-approved Spotify Developer app (not Dev
    // Mode), so calls like GET /v1/playlists/{id}/tracks succeed on
    // non-owned playlists.
    nonisolated static func getClientId() -> String {
        "d420a117a32841c2b3474932e49fb54b"
    }

    /// Redirect URI for OAuth callback. The ncspot client_id is registered with
    /// this loopback URL — Spotify requires an exact match.
    nonisolated static let redirectUri = "http://127.0.0.1:8989/login"

    /// Port for the local loopback HTTP listener that receives the OAuth callback.
    nonisolated static let loopbackPort: UInt16 = 8989

    /// OAuth scopes required by the app
    nonisolated static let scopes: [String] = [
        "user-read-private",
        "user-read-email",
        "streaming",
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "playlist-read-private",
        "playlist-read-collaborative",
        "playlist-modify-public",
        "playlist-modify-private",
        "user-library-read",
        "user-library-modify",
        "user-follow-read",
        "user-read-recently-played",
        "user-top-read",
    ]
}
