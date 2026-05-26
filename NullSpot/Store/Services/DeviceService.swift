//
//  DeviceService.swift
//  NullSpot
//
//  Service for Spotify Connect device operations.
//  Handles API calls and updates AppStore on success.
//

import Combine
import Foundation

@MainActor
@Observable
final class DeviceService {
    private let store: AppStore
    private var loadDevicesTask: Task<Void, Never>?

    /// Timestamp of the last outgoing transfer, used to delay the
    /// `fetchInitialPlaybackState` that fires on reconnect (Web API is stale).
    private var lastTransferTime: ContinuousClock.Instant?

    /// Subject for event-driven load requests. Throttled so that bursts of triggers
    /// (e.g. sessionConnected firing right after the post-transfer delay) collapse
    /// into a single HTTP request.
    @ObservationIgnored private let loadSubject = PassthroughSubject<Void, Never>()
    @ObservationIgnored private var loadCancellable: AnyCancellable?
    @ObservationIgnored private var activeDeviceCancellable: AnyCancellable?

    init(store: AppStore) {
        self.store = store
        loadCancellable = loadSubject
            .throttle(for: .seconds(10), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self, let session = pendingSession else { return }
                    await loadDevices(session: session)
                }
            }
        activeDeviceCancellable = SpotifyPlayer.activeDeviceChanged
            .sink { [weak self] deviceId in
                self?.store.setActiveDevice(deviceId)
            }
    }

    /// Session stored when scheduleLoad is invoked, consumed by the throttled sink.
    @ObservationIgnored private var pendingSession: SpotifySession?

    // MARK: - Device Loading

    /// Schedules an event-driven device list refresh, throttled to at most once per 10 seconds.
    /// Use for automatic triggers (sessionConnected, post-transfer confirmation).
    func scheduleLoad(session: SpotifySession) {
        pendingSession = session
        loadSubject.send(())
    }

    /// Loads available Spotify Connect devices immediately (no throttle).
    func loadDevices(session: SpotifySession) async {
        // If already loading, await existing task instead of starting a new one.
        // This handles view recreation where .task fires again before loading finishes.
        if let existingTask = loadDevicesTask {
            await existingTask.value
            return
        }

        store.devicesIsLoading = true
        store.devicesErrorMessage = nil

        loadDevicesTask = Task {
            defer {
                self.loadDevicesTask = nil
                self.store.devicesIsLoading = false
            }

            do {
                let response = try await SpotifyAPI.fetchAvailableDevices(session: session)
                self.store.upsertDevices(response.devices)
            } catch is CancellationError {
                // Task was cancelled (e.g., view dismissed) - don't show error
            } catch let error as SpotifyAPIError {
                self.store.devicesErrorMessage = error.localizedDescription
            } catch {
                self.store.devicesErrorMessage = String(localized: "speakers.error.failed_to_load")
            }
        }

        await loadDevicesTask?.value
    }

    // MARK: - Playback Transfer

    /// Transfer playback to a specific device.
    /// Uses native Spotify Connect protocol for seamless handoff.
    /// Returns true if transfer succeeded (caller should activate Connect mode)
    func transferPlayback(to device: Device, session: SpotifySession) async -> Bool {
        // Record transfer time so sessionConnected handler can delay its Web API fetch
        lastTransferTime = .now

        // Optimistically mark the target device as active for immediate UI feedback
        store.setActiveDevice(device.id)

        // Check if target is our local device
        let isLocalDevice = device.id == store.connection?.deviceId

        if isLocalDevice {
            // Transfer TO local - use Spirc's native transfer
            SpotifyPlayer.transferToLocal()
        } else {
            // Transfer FROM local to remote device
            SpotifyPlayer.transferPlayback(to: device.id)
        }

        // Schedule a throttled refresh after the transfer settles.
        // Using scheduleLoad means the sessionConnected-triggered load that fires
        // ~250ms later collapses into this one via the 10s throttle window.
        Task {
            try? await Task.sleep(for: .milliseconds(750))
            scheduleLoad(session: session)
        }

        return true
    }

    /// Waits if a transfer happened recently, giving the Web API time to reflect the new state.
    /// Call before `fetchInitialPlaybackState` on reconnect.
    func waitForTransferSettling() async {
        guard let transferTime = lastTransferTime else { return }
        let elapsed = transferTime.duration(to: .now)
        let staleWindow = Duration.seconds(5)
        if elapsed < staleWindow {
            try? await Task.sleep(for: staleWindow - elapsed)
        }
    }

    // MARK: - Helpers

    /// Get appropriate icon name for device type
    func deviceIcon(for type: String) -> String {
        switch type.lowercased() {
        case "computer":
            "desktopcomputer"
        case "smartphone":
            "iphone"
        case "speaker":
            "hifispeaker"
        case "tv":
            "tv"
        case "avr", "stb":
            "appletv"
        case "automobile":
            "car"
        default:
            "speaker.wave.2"
        }
    }
}
