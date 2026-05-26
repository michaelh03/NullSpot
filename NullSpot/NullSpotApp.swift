//
//  NullSpotApp.swift
//  NullSpot
//
//  Created by Michael H on 30.12.25.
//

import AppKit
import SwiftUI

// MARK: - Focused Values for Menu Commands

struct FocusedSession: FocusedValueKey {
    typealias Value = SpotifySession
}

extension FocusedValues {
    var session: SpotifySession? {
        get { self[FocusedSession.self] }
        set { self[FocusedSession.self] = newValue }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_: Notification) {
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024,
            diskPath: "nullspot-images",
        )
    }

    func applicationWillTerminate(_: Notification) {
        // Shut down Spirc to send goodbye to other Spotify Connect devices
        SpotifyPlayer.shutdown()
    }
}

// MARK: - App

@main
struct NullSpotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var windowState = WindowState()

    init() {
        // Set activation policy to regular to support media keys
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { notification in
                    windowState.exitMiniPlayerMode(window: notification.object as? NSWindow)
                }
                .environment(windowState)
        }
        .windowResizability(.contentSize)
        .commands {
            NullSpotCommands()
        }

        Settings {
            PreferencesView()
        }
    }
}

// MARK: - Menu Commands

struct NullSpotCommands: Commands {
    private var playbackViewModel: PlaybackViewModel {
        PlaybackViewModel.shared
    }

    var body: some Commands {
        // Replace default New Window command
        CommandGroup(replacing: .newItem) {}

        // Playback menu
        CommandMenu("menu.playback") {
            Button("menu.play_pause") {
                if playbackViewModel.isPlaying {
                    playbackViewModel.pause()
                } else {
                    playbackViewModel.resume()
                }
            }
            .keyboardShortcut(" ", modifiers: [])

            Button("menu.next_track") {
                playbackViewModel.next()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)

            Button("menu.previous_track") {
                playbackViewModel.previous()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
        }

        #if DEBUG
            CommandMenu("Debug") {
                Button("Dump Store to Clipboard") {
                    AppStore.current?.debugDumpJSON()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Copy OAuth Token") {
                    if let token = SpotifySession.current?.accessToken {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(token, forType: .string)
                    }
                }
            }
        #endif
    }
}
