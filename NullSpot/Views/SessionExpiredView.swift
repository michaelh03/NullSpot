//
//  SessionExpiredView.swift
//  NullSpot
//
//  Shown when the Spotify session can no longer be refreshed and the user must sign in again.
//

import SwiftUI

struct SessionExpiredView: View {
    let onLogout: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)

            Text("session.expired.title")
                .font(.title2.bold())

            Text("session.expired.message")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button(action: onLogout) {
                Text("auth.logout")
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding(40)
    }
}
