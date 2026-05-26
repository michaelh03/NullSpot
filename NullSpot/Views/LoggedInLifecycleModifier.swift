//
//  LoggedInLifecycleModifier.swift
//  NullSpot
//
//  Encapsulates startup and session lifecycle side effects for the logged-in root view.
//

import AppKit
import SwiftUI

enum BlockingState {
    case premiumRequired
    case userNotWhitelisted
    case sessionExpired
}

struct LoggedInLifecycleModifier: ViewModifier {
    let session: SpotifySession
    let store: AppStore
    let topItemsTimeRange: String
    let reconnectWatchdogTimeoutSeconds: Double
    let playbackViewModel: PlaybackViewModel
    let queueService: QueueService
    let deviceService: DeviceService
    let recentlyPlayedService: RecentlyPlayedService
    let topItemsService: TopItemsService
    let playlist: MinimalPlaylist
    @Binding var blockingState: BlockingState?

    @State private var reconnectWatchdogTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .task {
                #if DEBUG
                    AppStore.current = store
                    SpotifySession.current = session
                #endif

                do {
                    let profile = try await SpotifyAPI.getCurrentUserProfile(session: session)
                    store.setUserProfile(profile)

                    // Restore the previously saved queue for this user, then attach
                    // persistence so subsequent mutations auto-save off the main thread.
                    let persistence = MinimalPlaylistPersistence(userId: profile.id)
                    if let savedState = await persistence.load() {
                        playlist.restore(from: savedState)
                    }
                    playlist.attachPersistence(persistence)
                } catch SpotifyAPIError.forbidden(_) {
                    blockingState = .userNotWhitelisted
                    return
                } catch SpotifyAPIError.unauthorized {
                    blockingState = .sessionExpired
                    return
                } catch {
                    // Continue without profile if the request fails for a non-auth reason.
                }

                do {
                    _ = try await SpotifyAPI.fetchAvailableDevices(session: session)
                } catch SpotifyAPIError.forbidden(_) {
                    blockingState = .premiumRequired
                    return
                } catch SpotifyAPIError.unauthorized {
                    blockingState = .sessionExpired
                    return
                } catch {
                    // Continue on transient failures and let playback surface any later errors.
                }

                let timeRange = TopItemsTimeRange(rawValue: topItemsTimeRange) ?? .mediumTerm
                async let topArtists: () = topItemsService.loadTopArtists(session: session, timeRange: timeRange)
                async let topTracks: () = topItemsService.loadTopTracks(session: session, timeRange: timeRange)
                async let recentlyPlayed: () = recentlyPlayedService.loadRecentlyPlayed(session: session)

                _ = await (topArtists, topTracks, recentlyPlayed)

                playbackViewModel.setSession(session)
                SpotifyPlayer.setTokenProvider(session)

                await playbackViewModel.initializeIfNeeded(session: session)
                await queueService.fetchInitialPlaybackState()
            }
            .onReceive(SpotifyPlayer.sessionConnected) {
                reconnectWatchdogTask?.cancel()
                reconnectWatchdogTask = nil

                Task {
                    await deviceService.waitForTransferSettling()
                    await queueService.fetchInitialPlaybackState()
                }
            }
            .onReceive(SpotifyPlayer.sessionDisconnected) {
                reconnectWatchdogTask?.cancel()
                reconnectWatchdogTask = Task {
                    try? await Task.sleep(for: .seconds(reconnectWatchdogTimeoutSeconds))
                    guard !Task.isCancelled, !SpotifyPlayer.isSessionConnected else { return }
                    debugLog(
                        "LoggedInLifecycle",
                        "Watchdog: still disconnected after \(Int(reconnectWatchdogTimeoutSeconds))s, forcing reinit",
                    )
                    await playbackViewModel.forceReinitialize(session: session)
                }
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
                debugLog("LoggedInLifecycle", "System will sleep, disconnecting from Spotify")
                SpotifyPlayer.disconnect()
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                debugLog("LoggedInLifecycle", "System wake detected, forcing full reinit")
                Task {
                    await playbackViewModel.forceReinitialize(session: session)
                }
            }
            .onDisappear {
                reconnectWatchdogTask?.cancel()
                reconnectWatchdogTask = nil
            }
    }
}

extension View {
    func loggedInLifecycle(
        session: SpotifySession,
        store: AppStore,
        topItemsTimeRange: String,
        reconnectWatchdogTimeoutSeconds: Double,
        playbackViewModel: PlaybackViewModel,
        queueService: QueueService,
        deviceService: DeviceService,
        recentlyPlayedService: RecentlyPlayedService,
        topItemsService: TopItemsService,
        playlist: MinimalPlaylist,
        blockingState: Binding<BlockingState?>,
    ) -> some View {
        modifier(
            LoggedInLifecycleModifier(
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
                blockingState: blockingState,
            ),
        )
    }
}
