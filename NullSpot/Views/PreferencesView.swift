//
//  PreferencesView.swift
//  NullSpot
//
//  Preferences window with tabbed interface
//

import SwiftUI
import UniformTypeIdentifiers

struct PreferencesView: View {
    var body: some View {
        TabView {
            Tab("preferences.playback", systemImage: "speaker.wave.3") {
                PlaybackSettingsView()
            }

            Tab("preferences.account", systemImage: "person.crop.circle") {
                AccountSettingsView()
            }

            Tab("preferences.info", systemImage: "info.circle") {
                InfoView()
            }
        }
        .frame(width: 450)
    }
}

// MARK: - Account Settings Tab

struct AccountSettingsView: View {
    var body: some View {
        Form {
            Section {
                Button(role: .destructive) {
                    NotificationCenter.default.post(name: .nullspotLogoutRequested, object: nil)
                } label: {
                    Label("auth.logout", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } footer: {
                Text("preferences.account.logout_footer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Playback Settings Tab

struct PlaybackSettingsView: View {
    @AppStorage("streamingBitrate") private var bitrateRawValue: Int = 1
    @AppStorage("gaplessPlayback") private var gaplessEnabled: Bool = true

    private var selectedBitrate: SpotifyPlayer.Bitrate {
        get { SpotifyPlayer.Bitrate(rawValue: UInt8(bitrateRawValue)) ?? .normal }
        set { bitrateRawValue = Int(newValue.rawValue) }
    }

    var body: some View {
        Form {
            Picker("preferences.streaming_quality", selection: Binding(
                get: { selectedBitrate },
                set: { newValue in
                    bitrateRawValue = Int(newValue.rawValue)
                    SpotifyPlayer.setBitrate(newValue)
                },
            )) {
                ForEach(SpotifyPlayer.Bitrate.allCases) { bitrate in
                    Text(bitrate.isDefault ? "\(bitrate.displayName) (\(String(localized: "preferences.default")))" : bitrate.displayName)
                        .tag(bitrate)
                }
            }

            Toggle("preferences.gapless_playback", isOn: Binding(
                get: { gaplessEnabled },
                set: { newValue in
                    gaplessEnabled = newValue
                    SpotifyPlayer.setGapless(newValue)
                },
            ))

            Text("preferences.restart_note")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear {
            // Sync UI with actual player settings
            SpotifyPlayer.setBitrate(selectedBitrate)
            SpotifyPlayer.setGapless(gaplessEnabled)
        }
    }
}

// MARK: - Info Tab

struct InfoView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var copyrightYear: String {
        let year = Calendar.current.component(.year, from: Date())
        return String(year)
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text("NullSpot")
                .font(.title2.weight(.semibold))

            Text("preferences.version \(appVersion) (\(buildNumber))")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("preferences.copyright \(copyrightYear)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }
}
