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
        "user-read-playback-position",
    ]

    // MARK: - librespot (Spotify Connect) credentials

    /// Spotify's "keymaster" client_id, used *only* for the librespot session.
    ///
    /// This must be distinct from `getClientId()`: librespot's native path
    /// (clienttoken.spotify.com, the access point, and login5) only accepts
    /// first-party native client ids. A Web API app id like ncspot's is
    /// rejected there — clienttoken answers HTTP 400, and login5 answers
    /// INVALID_CREDENTIALS for stored credentials minted by a different id.
    ///
    /// So we run a second PKCE flow with this id purely to obtain the token we
    /// hand to `SpotifyPlayer.initialize()`. This mirrors spotify-player, which
    /// uses ncspot's id for the Web API and this id for librespot.
    nonisolated static let librespotClientId = "65b708073fc0480ea92a077233ca87bd"

    /// Scopes for the librespot token. Playback/Connect only — this token is
    /// never used for Web API calls.
    nonisolated static let librespotScopes: [String] = [
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "app-remote-control",
        "streaming",
        "playlist-read-private",
        "playlist-read-collaborative",
        "user-follow-read",
        "user-read-playback-position",
        "user-top-read",
        "user-read-recently-played",
        "user-library-read",
    ]
}
