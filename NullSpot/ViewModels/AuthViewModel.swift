//
//  AuthViewModel.swift
//  NullSpot
//
//  Created by Ralph von der Heyden on 30.12.25.
//

import SwiftUI

extension Notification.Name {
    /// Posted when the user requests logout from a detached scene
    /// (e.g. the Settings window) that can't reach AuthViewModel directly.
    static let nullspotLogoutRequested = Notification.Name("com.nullspot.logoutRequested")
}

@MainActor
@Observable
final class AuthViewModel {
    var isAuthenticating = false
    var authResult: SpotifyAuthResult?
    var errorMessage: String?
    var isLoading = true

    init() {
        // Try to load existing auth from keychain on init
        loadFromKeychain()
    }

    func loadFromKeychain() {
        isLoading = true
        Task {
            // Attempt to load and refresh if needed
            if let savedResult = await KeychainManager.loadAuthResultWithRefresh() {
                await MainActor.run {
                    self.authResult = savedResult
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }

    func startOAuth() {
        isAuthenticating = true
        errorMessage = nil

        Task {
            do {
                let result = try await SpotifyAuth.authenticate()
                self.authResult = result
                self.isAuthenticating = false

                // Save to keychain
                do {
                    try KeychainManager.saveAuthResult(result)
                } catch {
                    #if DEBUG
                        print("Failed to save to keychain: \(error)")
                    #endif
                }
            } catch {
                self.errorMessage = "Authentication failed: \(error.localizedDescription)"
                self.isAuthenticating = false
            }
        }
    }

    func logout() {
        SpotifyAuth.clearAuthResult()
        KeychainManager.clearAuthResult()
        authResult = nil
    }
}
