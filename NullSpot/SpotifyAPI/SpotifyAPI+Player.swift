//
//  SpotifyAPI+Player.swift
//  NullSpot
//
//  Playback and Spotify Connect API calls.
//

import Foundation

extension SpotifyAPI {
    // MARK: - Devices

    /// Fetches available Spotify Connect devices
    static func fetchAvailableDevices(session: SpotifySession) async throws -> DevicesResponse {
        let urlString = "\(baseURL)/me/player/devices"

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
                        let decoded = try JSONDecoder().decode(DevicesCodable.self, from: data)
                        let devices = decoded.devices.compactMap { $0.toDevice() }
                        return DevicesResponse(devices: devices)
                    } catch {
                        throw SpotifyAPIError.invalidResponse
                    }
                default:
                    try throwAuthorizedError(data: data, statusCode: response.statusCode)
                }
            },
        )
    }

    // MARK: - Queue

    /// Response from GET /me/player/queue
    struct QueueResponse: Decodable {
        let currentlyPlaying: TrackCodable?
        let queue: [TrackCodable]

        enum CodingKeys: String, CodingKey {
            case currentlyPlaying = "currently_playing"
            case queue
        }
    }

    /// Adds a track (or episode) to the active device's queue via Web API.
    /// Use this when controlling a remote device (not the local Spirc).
    static func addToQueue(session: SpotifySession, uri: String) async throws {
        var components = URLComponents(string: "\(baseURL)/me/player/queue")
        components?.queryItems = [URLQueryItem(name: "uri", value: uri)]
        guard let url = components?.url else {
            throw SpotifyAPIError.invalidURI
        }

        #if DEBUG
            debugLog("SpotifyAPI", "[POST] \(url.absoluteString)")
        #endif

        try await performAuthorizedRequest(
            session: session,
            build: { token in
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return request
            },
            handle: { data, response in
                switch response.statusCode {
                case 200, 204:
                    return
                default:
                    try throwAuthorizedError(data: data, statusCode: response.statusCode)
                }
            },
        )
    }

    /// Fetches the current playback queue from Spotify Web API.
    /// Returns the currently playing track and upcoming queue.
    static func fetchQueue(session: SpotifySession) async throws -> QueueResponse {
        let urlString = "\(baseURL)/me/player/queue"

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
                    try JSONDecoder().decode(QueueResponse.self, from: data)
                case 204:
                    // No content - nothing playing
                    QueueResponse(currentlyPlaying: nil, queue: [])
                default:
                    try throwAuthorizedError(data: data, statusCode: response.statusCode)
                }
            },
        )
    }

    // MARK: - Remote Playback Control

    /// Pauses playback on the active device via Web API.
    /// Use this when controlling a remote device (not the local Spirc).
    static func pausePlayback(session: SpotifySession) async throws {
        let urlString = "\(baseURL)/me/player/pause"

        #if DEBUG
            debugLog("SpotifyAPI", "[PUT] \(urlString)")
        #endif

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        try await performAuthorizedRequest(
            session: session,
            build: { token in
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return request
            },
            handle: { data, response in
                switch response.statusCode {
                case 200, 204:
                    return
                default:
                    try throwAuthorizedError(data: data, statusCode: response.statusCode)
                }
            },
        )
    }

    /// Resumes playback on the active device via Web API.
    /// Use this when controlling a remote device (not the local Spirc).
    static func resumePlayback(session: SpotifySession) async throws {
        let urlString = "\(baseURL)/me/player/play"

        #if DEBUG
            debugLog("SpotifyAPI", "[PUT] \(urlString)")
        #endif

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        try await performAuthorizedRequest(
            session: session,
            build: { token in
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return request
            },
            handle: { data, response in
                switch response.statusCode {
                case 200, 204:
                    return
                default:
                    try throwAuthorizedError(data: data, statusCode: response.statusCode)
                }
            },
        )
    }

    /// Skips to the next track on the active device via Web API.
    /// Use this when controlling a remote device (not the local Spirc).
    static func skipToNext(session: SpotifySession) async throws {
        let urlString = "\(baseURL)/me/player/next"

        #if DEBUG
            debugLog("SpotifyAPI", "[POST] \(urlString)")
        #endif

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        try await performAuthorizedRequest(
            session: session,
            build: { token in
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return request
            },
            handle: { data, response in
                switch response.statusCode {
                case 200, 204:
                    return
                default:
                    try throwAuthorizedError(data: data, statusCode: response.statusCode)
                }
            },
        )
    }

    /// Skips to the previous track on the active device via Web API.
    /// Use this when controlling a remote device (not the local Spirc).
    static func skipToPrevious(session: SpotifySession) async throws {
        let urlString = "\(baseURL)/me/player/previous"

        #if DEBUG
            debugLog("SpotifyAPI", "[POST] \(urlString)")
        #endif

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        try await performAuthorizedRequest(
            session: session,
            build: { token in
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return request
            },
            handle: { data, response in
                switch response.statusCode {
                case 200, 204:
                    return
                default:
                    try throwAuthorizedError(data: data, statusCode: response.statusCode)
                }
            },
        )
    }

    /// Seeks to a position in the currently playing track via Web API.
    /// Use this when controlling a remote device (not the local Spirc).
    static func seekToPosition(session: SpotifySession, positionMs: Int) async throws {
        let urlString = "\(baseURL)/me/player/seek?position_ms=\(positionMs)"

        #if DEBUG
            debugLog("SpotifyAPI", "[PUT] \(urlString)")
        #endif

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        try await performAuthorizedRequest(
            session: session,
            build: { token in
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return request
            },
            handle: { data, response in
                switch response.statusCode {
                case 200, 204:
                    return
                default:
                    try throwAuthorizedError(data: data, statusCode: response.statusCode)
                }
            },
        )
    }

    /// Sets the playback volume on the active device via Web API.
    /// Use this when controlling a remote device (not the local Spirc).
    /// - Parameter percent: Volume level 0–100
    static func setVolume(session: SpotifySession, percent: Int) async throws {
        let percent = max(0, min(100, percent))
        let urlString = "\(baseURL)/me/player/volume?volume_percent=\(percent)"

        #if DEBUG
            debugLog("SpotifyAPI", "[PUT] \(urlString)")
        #endif

        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        try await performAuthorizedRequest(
            session: session,
            build: { token in
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return request
            },
            handle: { data, response in
                switch response.statusCode {
                case 200, 204:
                    return
                default:
                    try throwAuthorizedError(data: data, statusCode: response.statusCode)
                }
            },
        )
    }

    /// Enables or disables shuffle on the active device via Web API.
    /// Use this when controlling a remote device (not the local Spirc).
    static func setShuffle(session: SpotifySession, enabled: Bool) async throws {
        let urlString = "\(baseURL)/me/player/shuffle?state=\(enabled)"
        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        #if DEBUG
            debugLog("SpotifyAPI", "[PUT] \(urlString)")
        #endif

        try await performAuthorizedRequest(
            session: session,
            build: { token in
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return request
            },
            handle: { data, response in
                switch response.statusCode {
                case 200, 204:
                    return
                default:
                    try throwAuthorizedError(data: data, statusCode: response.statusCode)
                }
            },
        )
    }

    /// Repeat mode for /me/player/repeat.
    enum RepeatMode: String {
        case off
        case context
        case track
    }

    /// Sets the repeat mode on the active device via Web API.
    static func setRepeat(session: SpotifySession, mode: RepeatMode) async throws {
        let urlString = "\(baseURL)/me/player/repeat?state=\(mode.rawValue)"
        guard let url = URL(string: urlString) else {
            throw SpotifyAPIError.invalidURI
        }

        #if DEBUG
            debugLog("SpotifyAPI", "[PUT] \(urlString)")
        #endif

        try await performAuthorizedRequest(
            session: session,
            build: { token in
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return request
            },
            handle: { data, response in
                switch response.statusCode {
                case 200, 204:
                    return
                default:
                    try throwAuthorizedError(data: data, statusCode: response.statusCode)
                }
            },
        )
    }

    // MARK: - Playback State

    /// Response from GET /me/player
    struct PlaybackStateResponse: Decodable {
        let device: DeviceCodable?
        let repeatState: String?
        let shuffleState: Bool?
        let timestamp: Int64?
        let progressMs: Int?
        let isPlaying: Bool
        let item: TrackCodable?

        enum CodingKeys: String, CodingKey {
            case device
            case repeatState = "repeat_state"
            case shuffleState = "shuffle_state"
            case timestamp
            case progressMs = "progress_ms"
            case isPlaying = "is_playing"
            case item
        }
    }

    /// Fetches the current playback state from Spotify Web API.
    /// Returns the currently playing track, device, and playback position.
    static func fetchPlaybackState(session: SpotifySession) async throws -> PlaybackStateResponse? {
        let urlString = "\(baseURL)/me/player"

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
                    try JSONDecoder().decode(PlaybackStateResponse.self, from: data)
                case 204:
                    nil
                default:
                    try throwAuthorizedError(data: data, statusCode: response.statusCode)
                }
            },
        )
    }
}
