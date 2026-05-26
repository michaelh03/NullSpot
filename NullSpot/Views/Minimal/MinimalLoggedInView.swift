//
//  MinimalLoggedInView.swift
//  NullSpot
//
//  Minimal Winamp-inspired root for the logged-in state.
//  Mirrors LoggedInView's wiring (services, environment, lifecycle) so all
//  data flow keeps working — only the rendered surface changes.
//

import SwiftUI

struct MinimalLoggedInView: View {
    let authResult: SpotifyAuthResult
    private let onLogoutOriginal: () -> Void

    @State private var session: SpotifySession
    private let playbackViewModel = PlaybackViewModel.shared

    @State private var store: AppStore
    @State private var playlistService: PlaylistService
    @State private var albumService: AlbumService
    @State private var artistService: ArtistService
    @State private var queueService: QueueService
    @State private var connectionService: ConnectionService
    @State private var deviceService: DeviceService
    @State private var trackService: TrackService
    @State private var recentlyPlayedService: RecentlyPlayedService
    @State private var searchService: SearchService
    @State private var topItemsService: TopItemsService
    @State private var showService: ShowService
    @State private var playlist = MinimalPlaylist()
    @State private var recentSearches = RecentSearchesStore()

    @AppStorage("topItemsTimeRange") private var topItemsTimeRange: String = TopItemsTimeRange.mediumTerm.rawValue

    @State private var blockingState: BlockingState?

    private let reconnectWatchdogTimeoutSeconds: Double = 120

    init(authResult: SpotifyAuthResult, onLogout: @escaping () -> Void) {
        self.authResult = authResult
        onLogoutOriginal = onLogout

        let store = AppStore()
        let session = SpotifySession(authResult: authResult)

        _store = State(initialValue: store)
        _session = State(initialValue: session)
        _playlistService = State(initialValue: PlaylistService(store: store))
        _albumService = State(initialValue: AlbumService(store: store))
        _artistService = State(initialValue: ArtistService(store: store))
        _queueService = State(initialValue: QueueService(store: store, session: session))
        _connectionService = State(initialValue: ConnectionService(store: store))
        _deviceService = State(initialValue: DeviceService(store: store))
        _trackService = State(initialValue: TrackService(store: store))
        _recentlyPlayedService = State(initialValue: RecentlyPlayedService(store: store))
        _searchService = State(initialValue: SearchService(store: store))
        _topItemsService = State(initialValue: TopItemsService(store: store))
        _showService = State(initialValue: ShowService(store: store))

        playbackViewModel.setStore(store)
    }

    /// Clears the persisted queue for the current user and then calls the
    /// original logout callback. Used by in-view logout buttons.
    private func onLogout() {
        clearPersistedQueueForCurrentUser()
        onLogoutOriginal()
    }

    private func clearPersistedQueueForCurrentUser() {
        if let userId = store.userProfile?.id {
            MinimalPlaylistPersistence.deleteFile(forUserId: userId)
        }
    }

    var body: some View {
        switch blockingState {
        case .premiumRequired:
            PremiumRequiredView(
                displayName: store.userProfile?.displayName,
                onLogout: onLogout,
            )
            .frame(width: MinimalTheme.windowWidth, height: MinimalTheme.windowHeight)
            .preferredColorScheme(.light)

        case .userNotWhitelisted:
            UserNotWhitelistedView(
                clientId: SpotifyConfig.getClientId(),
                onLogout: onLogout,
            )
            .frame(width: MinimalTheme.windowWidth, height: MinimalTheme.windowHeight)
            .preferredColorScheme(.light)

        case .sessionExpired:
            SessionExpiredView(onLogout: onLogout)
                .frame(width: MinimalTheme.windowWidth, height: MinimalTheme.windowHeight)
                .preferredColorScheme(.light)

        case nil:
            mainView
        }
    }

    private var mainView: some View {
        MinimalPlayerWindow()
            .environment(session)
            .environment(connectionService)
            .environment(deviceService)
            .environment(queueService)
            .environment(recentlyPlayedService)
            .environment(searchService)
            .environment(topItemsService)
            .environment(store)
            .environment(trackService)
            .environment(playlistService)
            .environment(albumService)
            .environment(artistService)
            .environment(showService)
            .environment(playlist)
            .environment(recentSearches)
            .loggedInLifecycle(
                session: session,
                store: store,
                topItemsTimeRange: topItemsTimeRange,
                reconnectWatchdogTimeoutSeconds: reconnectWatchdogTimeoutSeconds,
                playbackViewModel: playbackViewModel,
                queueService: queueService,
                deviceService: deviceService,
                recentlyPlayedService: recentlyPlayedService,
                topItemsService: topItemsService,
                playlist: playlist,
                blockingState: $blockingState,
            )
            .onReceive(NotificationCenter.default.publisher(for: .nullspotLogoutRequested)) { _ in
                clearPersistedQueueForCurrentUser()
            }
    }
}
