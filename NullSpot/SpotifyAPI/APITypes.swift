//
//  APITypes.swift
//  NullSpot
//
//  Data types for Spotify Web API responses.
//

import Foundation

// MARK: - Duration Formatting Protocol

/// Protocol for types that have a total duration in milliseconds
protocol DurationFormattable {
    var totalDurationMs: Int? { get }
}

extension DurationFormattable {
    /// Formats the total duration as "X hr Y min" or "Y min"
    var formattedDuration: String? {
        guard let totalDurationMs else { return nil }
        let totalSeconds = totalDurationMs / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours.formatted()) hr \(minutes.formatted()) min"
        } else {
            return "\(minutes.formatted()) min"
        }
    }
}

// MARK: - Unified Track Type

/// Unified track type from Spotify API.
/// Used for all track sources: search, saved, album, playlist, playback.
struct APITrack: Identifiable {
    let id: String
    let addedAt: String?
    let albumId: String?
    let albumName: String?
    let artistId: String?
    let artistName: String
    let durationMs: Int
    let externalUrl: String?
    let images: ImageSet
    let name: String
    let trackNumber: Int?
    let uri: String
}

// MARK: - Album Types

/// Album metadata from Spotify API
struct APIAlbum: Identifiable, DurationFormattable {
    let id: String
    let albumType: String?
    let artistId: String?
    let artistName: String
    let externalUrl: String?
    let images: ImageSet
    let name: String
    let releaseDate: String
    let totalDurationMs: Int?
    let trackCount: Int
    let uri: String
}

/// Response wrapper for albums endpoint
struct AlbumsResponse {
    let albums: [APIAlbum]
    let hasMore: Bool
    let nextOffset: Int?
    let total: Int
}

// MARK: - Artist Types

/// Artist metadata from Spotify API
struct APIArtist: Identifiable {
    let id: String
    let genres: [String]
    let images: ImageSet
    let name: String
    let uri: String
    let externalUrl: String?
}

/// Response wrapper for artists endpoint
struct ArtistsResponse {
    let artists: [APIArtist]
    let hasMore: Bool
    let nextCursor: String?
    let total: Int
}

/// Response wrapper for user's top artists endpoint
struct TopArtistsResponse {
    let artists: [APIArtist]
    let hasMore: Bool
    let nextOffset: Int?
    let total: Int
}

/// Response wrapper for user's top tracks endpoint
struct TopTracksResponse {
    let tracks: [APITrack]
    let hasMore: Bool
    let nextOffset: Int?
    let total: Int
}

// MARK: - Playlist Types

/// Playlist metadata from Spotify API
struct APIPlaylist: Identifiable, DurationFormattable {
    let id: String
    let description: String?
    let images: ImageSet
    let isPublic: Bool?
    var name: String
    let ownerId: String
    let ownerName: String
    let totalDurationMs: Int?
    var trackCount: Int
    let uri: String
    let externalUrl: String?
}

/// Response wrapper for playlists endpoint
struct PlaylistsResponse {
    let hasMore: Bool
    let nextOffset: Int?
    let playlists: [APIPlaylist]
    let total: Int
}

// MARK: - Saved Tracks

/// Response wrapper for saved tracks endpoint
struct SavedTracksResponse {
    let hasMore: Bool
    let nextOffset: Int?
    let total: Int
    let tracks: [APITrack]
}

// MARK: - Search Types

/// Search result type
enum SearchType: String {
    case album
    case artist
    case playlist
    case track
    case show
}

/// Search results wrapper (uses unified Entity types)
struct SearchResults: Encodable {
    let albums: [Album]
    let artists: [Artist]
    let playlists: [Playlist]
    let tracks: [Track]
    let shows: [Show]
}

// MARK: - Recently Played

/// Recently played context
struct PlaybackContext {
    let type: String // "album", "playlist", "artist"
    let uri: String
}

/// Recently played item
struct RecentlyPlayedItem: Identifiable {
    let id: String // Use played_at as ID since tracks can be played multiple times
    let context: PlaybackContext?
    let playedAt: String
    let track: APITrack
}

/// Recently played response wrapper
struct RecentlyPlayedResponse {
    let items: [RecentlyPlayedItem]
}

// MARK: - Playback & Connect Types

/// Devices response wrapper
struct DevicesResponse {
    let devices: [Device]
}

// MARK: - User Top Items

/// Time range for top items (artists/tracks)
enum TopItemsTimeRange: String {
    case longTerm = "long_term" // ~1 year
    case mediumTerm = "medium_term" // ~6 months (default)
    case shortTerm = "short_term" // ~4 weeks
}

// MARK: - Codable Response Types (Internal)

// These types are used only for JSON decoding from Spotify API responses.
// They map directly to the JSON structure, then convert to the public API types.

// MARK: Shared Primitives

struct SpotifyErrorResponse: Decodable {
    let error: SpotifyErrorBody
    struct SpotifyErrorBody: Decodable {
        let message: String
        let status: Int
        let reason: String?
    }
}

struct ImageCodable: Decodable {
    let url: String
    let height: Int?
    let width: Int?
}

extension [ImageCodable] {
    /// Convert API image response to an ImageSet with all available sizes.
    var toImageSet: ImageSet {
        let variants = compactMap { img -> ImageVariant? in
            guard let url = URL(string: img.url) else { return nil }
            let size = img.width ?? img.height ?? 0
            return ImageVariant(url: url, size: size)
        }
        return ImageSet(variants: variants.sorted { $0.size > $1.size })
    }

    /// Preferred single URL for contexts that only need one (e.g. UserProfile).
    var preferredURL: String? {
        let medium = first(where: { ($0.width ?? Int.max) <= 400 && ($0.width ?? 0) >= 100 })
        return (medium ?? first)?.url
    }
}

struct ExternalUrlsCodable: Decodable {
    let spotify: String?
}

struct ContextCodable: Decodable {
    let type: String
    let uri: String
}

struct OwnerCodable: Decodable {
    let id: String
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

struct CursorsCodable: Decodable {
    let after: String?
}

// MARK: Artist Codable

struct ArtistCodable: Decodable {
    let id: String?
    let name: String
    let uri: String?
    let genres: [String]?
    let images: [ImageCodable]?
    let externalUrls: ExternalUrlsCodable?

    enum CodingKeys: String, CodingKey {
        case id, name, uri, genres, images
        case externalUrls = "external_urls"
    }
}

extension ArtistCodable {
    func toAPIArtist() -> APIArtist? {
        guard let id, let uri else { return nil }
        return APIArtist(
            id: id,
            genres: genres ?? [],
            images: images?.toImageSet ?? ImageSet.empty,
            name: name,
            uri: uri,
            externalUrl: externalUrls?.spotify,
        )
    }
}

// MARK: Album Codable (simplified for nested use)

struct AlbumSimpleCodable: Decodable {
    let id: String?
    let name: String
    let images: [ImageCodable]?
}

// MARK: Album Codable (full)

struct AlbumCodable: Decodable {
    let id: String
    let name: String
    let uri: String
    let albumType: String?
    let totalTracks: Int?
    let releaseDate: String?
    let artists: [ArtistCodable]?
    let images: [ImageCodable]?
    let tracks: TracksPagingCodable?
    let externalUrls: ExternalUrlsCodable?

    enum CodingKeys: String, CodingKey {
        case id, name, uri, artists, images, tracks
        case albumType = "album_type"
        case totalTracks = "total_tracks"
        case releaseDate = "release_date"
        case externalUrls = "external_urls"
    }

    struct TracksPagingCodable: Decodable {
        let items: [TrackItemCodable]?
        struct TrackItemCodable: Decodable {
            let durationMs: Int?
            enum CodingKeys: String, CodingKey {
                case durationMs = "duration_ms"
            }
        }
    }

    func toAPIAlbum() -> APIAlbum {
        let artist = artists?.first
        let totalDurationMs = tracks?.items?.compactMap(\.durationMs).reduce(0, +)
        return APIAlbum(
            id: id,
            albumType: albumType,
            artistId: artist?.id,
            artistName: artist?.name ?? "Unknown",
            externalUrl: externalUrls?.spotify,
            images: images?.toImageSet ?? ImageSet.empty,
            name: name,
            releaseDate: releaseDate ?? "",
            totalDurationMs: totalDurationMs,
            trackCount: totalTracks ?? 0,
            uri: uri,
        )
    }
}

// MARK: Track Codable

struct TrackCodable: Decodable {
    let id: String
    let name: String
    let uri: String
    let durationMs: Int
    let trackNumber: Int?
    let artists: [ArtistCodable]?
    let album: AlbumSimpleCodable?
    let externalUrls: ExternalUrlsCodable?
    let previewUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, uri, artists, album
        case durationMs = "duration_ms"
        case trackNumber = "track_number"
        case externalUrls = "external_urls"
        case previewUrl = "preview_url"
    }

    func toAPITrack(addedAt: String? = nil, albumId: String? = nil, albumName: String? = nil, images: ImageSet? = nil) -> APITrack {
        let artist = artists?.first
        return APITrack(
            id: id,
            addedAt: addedAt,
            albumId: albumId ?? album?.id,
            albumName: albumName ?? album?.name,
            artistId: artist?.id,
            artistName: artist?.name ?? "Unknown",
            durationMs: durationMs,
            externalUrl: externalUrls?.spotify,
            images: images ?? album?.images?.toImageSet ?? ImageSet.empty,
            name: name,
            trackNumber: trackNumber,
            uri: uri,
        )
    }
}

// MARK: Playlist Codable

struct PlaylistCodable: Decodable {
    let id: String
    let name: String
    let uri: String
    let description: String?
    let images: [ImageCodable]?
    let owner: OwnerCodable
    let `public`: Bool?
    let tracks: PlaylistItemsCodable?
    let externalUrls: ExternalUrlsCodable?

    enum CodingKeys: String, CodingKey {
        case id, name, uri, description, images, owner
        case tracks = "items"
        case `public`
        case externalUrls = "external_urls"
    }

    struct PlaylistItemsCodable: Decodable {
        let total: Int?
        let items: [PlaylistItemWrapperCodable]?
    }

    struct PlaylistItemWrapperCodable: Decodable {
        let track: TrackDurationCodable?

        enum CodingKeys: String, CodingKey {
            case track = "item"
        }

        struct TrackDurationCodable: Decodable {
            let durationMs: Int?
            enum CodingKeys: String, CodingKey {
                case durationMs = "duration_ms"
            }
        }
    }

    func toAPIPlaylist() -> APIPlaylist {
        let durations = tracks?.items?.compactMap { $0.track?.durationMs } ?? []
        let totalDurationMs = durations.isEmpty ? nil : durations.reduce(0, +)
        return APIPlaylist(
            id: id,
            description: description,
            images: images?.toImageSet ?? ImageSet.empty,
            isPublic: `public`,
            name: name,
            ownerId: owner.id,
            ownerName: owner.displayName ?? owner.id,
            totalDurationMs: totalDurationMs,
            trackCount: tracks?.total ?? 0,
            uri: uri,
            externalUrl: externalUrls?.spotify,
        )
    }
}

// MARK: Show / Episode Codable

struct ShowCodable: Decodable {
    let id: String
    let name: String
    let uri: String
    let publisher: String?
    let description: String?
    let totalEpisodes: Int?
    let images: [ImageCodable]?
    let externalUrls: ExternalUrlsCodable?

    enum CodingKeys: String, CodingKey {
        case id, name, uri, publisher, description, images
        case totalEpisodes = "total_episodes"
        case externalUrls = "external_urls"
    }

    func toShow() -> Show {
        Show(
            id: id,
            name: name,
            uri: uri,
            images: images?.toImageSet ?? ImageSet.empty,
            publisher: publisher ?? "",
            description: description ?? "",
            totalEpisodes: totalEpisodes ?? 0,
            externalUrl: externalUrls?.spotify,
        )
    }
}

/// The user's most recent position in an episode. Only present when the access
/// token carries the `user-read-playback-position` scope.
struct ResumePointCodable: Decodable {
    let fullyPlayed: Bool?
    let resumePositionMs: Int?

    enum CodingKeys: String, CodingKey {
        case fullyPlayed = "fully_played"
        case resumePositionMs = "resume_position_ms"
    }
}

struct SimplifiedEpisodeCodable: Decodable {
    let id: String
    let name: String
    let uri: String
    let durationMs: Int
    let releaseDate: String?
    let images: [ImageCodable]?
    let externalUrls: ExternalUrlsCodable?
    let isPlayable: Bool?
    let resumePoint: ResumePointCodable?

    enum CodingKeys: String, CodingKey {
        case id, name, uri, images
        case durationMs = "duration_ms"
        case releaseDate = "release_date"
        case externalUrls = "external_urls"
        case isPlayable = "is_playable"
        case resumePoint = "resume_point"
    }
}

struct SimplifiedEpisodePagingCodable: Decodable {
    /// Items can be null for unavailable / restricted episodes.
    let items: [SimplifiedEpisodeCodable?]?
}

// MARK: Device Codable

struct DeviceCodable: Decodable {
    let id: String?
    let name: String
    let type: String
    let isActive: Bool?
    let isPrivateSession: Bool?
    let isRestricted: Bool?
    let volumePercent: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, type
        case isActive = "is_active"
        case isPrivateSession = "is_private_session"
        case isRestricted = "is_restricted"
        case volumePercent = "volume_percent"
    }

    func toDevice() -> Device? {
        guard let id else { return nil }
        return Device(
            id: id,
            name: name,
            type: type,
            isActive: isActive ?? false,
            isPrivateSession: isPrivateSession ?? false,
            isRestricted: isRestricted ?? false,
            volumePercent: volumePercent,
        )
    }
}

// MARK: - Response Codables

/// User profile
struct UserProfileCodable: Decodable {
    let id: String
    let displayName: String?
    let images: [ImageCodable]?
    let externalUrls: ExternalUrlsCodable?
    let uri: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case images
        case externalUrls = "external_urls"
        case uri
    }
}

/// Saved tracks
struct SavedTracksCodable: Decodable {
    let items: [SavedTrackItemCodable]
    let total: Int
    let next: String?

    struct SavedTrackItemCodable: Decodable {
        let addedAt: String?
        let track: TrackCodable

        enum CodingKeys: String, CodingKey {
            case addedAt = "added_at"
            case track
        }
    }
}

// Check saved tracks (returns array of bools)
// Note: This is just [Bool], decoded directly

/// Album tracks
struct AlbumTracksCodable: Decodable {
    let items: [AlbumTrackItemCodable]

    struct AlbumTrackItemCodable: Decodable {
        let id: String
        let name: String
        let uri: String
        let durationMs: Int
        let trackNumber: Int?
        let artists: [ArtistCodable]?
        let externalUrls: ExternalUrlsCodable?

        enum CodingKeys: String, CodingKey {
            case id, name, uri, artists
            case durationMs = "duration_ms"
            case trackNumber = "track_number"
            case externalUrls = "external_urls"
        }

        func toAPITrack(albumId: String, albumName: String?, images: ImageSet) -> APITrack {
            let artist = artists?.first
            return APITrack(
                id: id,
                addedAt: nil,
                albumId: albumId,
                albumName: albumName,
                artistId: artist?.id,
                artistName: artist?.name ?? "Unknown",
                durationMs: durationMs,
                externalUrl: externalUrls?.spotify,
                images: images,
                name: name,
                trackNumber: trackNumber,
                uri: uri,
            )
        }
    }
}

/// Playlist items
struct PlaylistItemsCodable: Decodable {
    let items: [PlaylistItemWrapperCodable]

    struct PlaylistItemWrapperCodable: Decodable {
        let addedAt: String?
        let track: TrackCodable?

        enum CodingKeys: String, CodingKey {
            case addedAt = "added_at"
            case track
        }
    }
}

/// User albums
struct UserAlbumsCodable: Decodable {
    let items: [UserAlbumItemCodable]
    let total: Int
    let next: String?

    struct UserAlbumItemCodable: Decodable {
        let album: AlbumCodable
    }
}

/// Artist albums
struct ArtistAlbumsCodable: Decodable {
    let items: [AlbumCodable]
}

/// Artist top tracks (`/artists/{id}/top-tracks`)
struct ArtistTopTracksCodable: Decodable {
    let tracks: [TrackCodable]
}

/// New releases
/// User artists (followed)
struct UserArtistsCodable: Decodable {
    let artists: ArtistsPagingCodable

    struct ArtistsPagingCodable: Decodable {
        let items: [ArtistCodable]
        let total: Int
        let cursors: CursorsCodable?
    }
}

/// Top artists
struct TopArtistsCodable: Decodable {
    let items: [ArtistCodable]
    let total: Int
    let next: String?
}

/// Top tracks
struct TopTracksCodable: Decodable {
    let items: [TrackCodable]
    let total: Int
    let next: String?
}

/// User playlists
struct UserPlaylistsCodable: Decodable {
    let items: [PlaylistCodable]
    let total: Int
    let next: String?
}

/// Devices
struct DevicesCodable: Decodable {
    let devices: [DeviceCodable]
}

/// Recently played
struct RecentlyPlayedCodable: Decodable {
    let items: [RecentlyPlayedItemCodable]

    struct RecentlyPlayedItemCodable: Decodable {
        let track: TrackCodable
        let playedAt: String
        let context: ContextCodable?

        enum CodingKeys: String, CodingKey {
            case track
            case playedAt = "played_at"
            case context
        }
    }

    func toRecentlyPlayedResponse() -> RecentlyPlayedResponse {
        let items = items.map { item in
            RecentlyPlayedItem(
                id: item.playedAt,
                context: item.context.map { PlaybackContext(type: $0.type, uri: $0.uri) },
                playedAt: item.playedAt,
                track: item.track.toAPITrack(),
            )
        }
        return RecentlyPlayedResponse(items: items)
    }
}

/// Search results
struct SearchResultsCodable: Decodable {
    let tracks: TracksPagingCodable?
    let albums: AlbumsPagingCodable?
    let artists: ArtistsPagingCodable?
    let playlists: PlaylistsPagingCodable?
    let shows: ShowsPagingCodable?

    struct TracksPagingCodable: Decodable {
        let items: [TrackCodable]?
    }

    struct AlbumsPagingCodable: Decodable {
        let items: [AlbumCodable]?
    }

    struct ArtistsPagingCodable: Decodable {
        let items: [ArtistCodable]?
    }

    struct PlaylistsPagingCodable: Decodable {
        /// Items can be null for deleted/unavailable playlists
        let items: [PlaylistCodable?]?
    }

    struct ShowsPagingCodable: Decodable {
        /// Items can be null for unavailable shows (mirrors playlist behavior).
        let items: [ShowCodable?]?
    }
}

// MARK: - Errors

/// Reason a 403 was returned. Player endpoints carry these in the `reason` field;
/// other endpoints can use `.contextual(localizedKey:)` to surface a domain-specific
/// localized message (e.g. "not authorized to modify this playlist").
enum ForbiddenReason: Sendable, Equatable {
    case premiumRequired
    case noActiveDevice
    case volumeControlDisallow
    case alreadyPaused
    case notPaused
    case notPlayingTrack
    case notPlayingContext
    case userNotRegistered
    /// Domain-specific reason carrying a `Localizable.strings` key for the message.
    case contextual(localizedKey: String)
    /// Fallback when Spotify returns a 403 we don't recognise. Carries the raw `reason`
    /// code (if any) and the human-readable `message` from the error body, so we can
    /// surface Spotify's actual explanation rather than a generic string.
    case unknown(reason: String?, message: String?)

    init(rawReason: String?, message: String? = nil) {
        switch rawReason {
        case "PREMIUM_REQUIRED": self = .premiumRequired
        case "NO_ACTIVE_DEVICE": self = .noActiveDevice
        case "VOLUME_CONTROL_DISALLOW": self = .volumeControlDisallow
        case "ALREADY_PAUSED": self = .alreadyPaused
        case "NOT_PAUSED": self = .notPaused
        case "NOT_PLAYING_TRACK": self = .notPlayingTrack
        case "NOT_PLAYING_CONTEXT": self = .notPlayingContext
        case "USER_NOT_REGISTERED": self = .userNotRegistered
        default: self = .unknown(reason: rawReason, message: message)
        }
    }

    nonisolated var localizedDescription: String {
        switch self {
        case .premiumRequired:
            return String(localized: "error.forbidden.premium_required")
        case .noActiveDevice:
            return String(localized: "error.forbidden.no_active_device")
        case .volumeControlDisallow:
            return String(localized: "error.forbidden.volume_control_disallowed")
        case .alreadyPaused, .notPaused, .notPlayingTrack, .notPlayingContext:
            // Benign playback-state mismatches; surface a generic message
            // if anyone does end up displaying them.
            return String(localized: "error.forbidden.unknown")
        case .userNotRegistered:
            return String(localized: "error.forbidden.user_not_registered")
        case let .contextual(localizedKey):
            return String(localized: String.LocalizationValue(localizedKey))
        case let .unknown(reason, message):
            // Prefer Spotify's human message; fall back to the raw reason code; final
            // fallback is the generic localized string.
            if let message, !message.isEmpty { return message }
            if let reason, !reason.isEmpty { return reason }
            return String(localized: "error.forbidden.unknown")
        }
    }
}

/// Errors from Spotify API
enum SpotifyAPIError: Error, LocalizedError {
    case apiError(String)
    case forbidden(ForbiddenReason)
    case invalidResponse
    case invalidURI
    case networkError(Error)
    case notFound
    case unauthorized

    nonisolated var errorDescription: String? {
        switch self {
        case let .apiError(message):
            "Spotify API error: \(message)"
        case let .forbidden(reason):
            reason.localizedDescription
        case .invalidResponse:
            "Invalid response from Spotify"
        case .invalidURI:
            "Invalid Spotify URI format"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case .notFound:
            "Track not found"
        case .unauthorized:
            String(localized: "error.unauthorized")
        }
    }
}
