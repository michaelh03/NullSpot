//
//  MinimalPlaylist.swift
//  NullSpot
//

import Foundation

/// Persistable snapshot of `MinimalPlaylist`. Marked `nonisolated` so its
/// `Codable` conformance is usable off the main actor — the project sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would otherwise pin it.
nonisolated struct MinimalPlaylistState: Codable, Sendable {
    nonisolated struct PersistedEntry: Codable, Sendable {
        let id: UUID
        let track: Track
    }

    let entries: [PersistedEntry]
    let currentEntryId: UUID?
}

@MainActor
@Observable
final class MinimalPlaylist {
    struct Entry: Identifiable {
        let id: UUID
        let track: Track

        init(id: UUID = UUID(), track: Track) {
            self.id = id
            self.track = track
        }
    }

    private(set) var entries: [Entry] = [] {
        didSet { scheduleSave() }
    }

    var currentEntryId: UUID? {
        didSet { scheduleSave() }
    }

    private var persistence: MinimalPlaylistPersistence?

    @discardableResult
    func append(_ track: Track) -> Entry {
        let entry = Entry(track: track)
        entries.append(entry)
        return entry
    }

    func clear() {
        entries.removeAll()
        currentEntryId = nil
    }

    func entry(matchingUri uri: String) -> Entry? {
        entries.first { $0.track.uri == uri }
    }

    func urisStarting(at entryId: UUID) -> [String] {
        guard let idx = entries.firstIndex(where: { $0.id == entryId }) else { return [] }
        return entries[idx...].map(\.track.uri)
    }

    var snapshot: MinimalPlaylistState {
        MinimalPlaylistState(
            entries: entries.map { .init(id: $0.id, track: $0.track) },
            currentEntryId: currentEntryId,
        )
    }

    func restore(from state: MinimalPlaylistState) {
        entries = state.entries.map { Entry(id: $0.id, track: $0.track) }
        currentEntryId = state.currentEntryId
    }

    /// Attach a persistence actor. Once attached, mutations are auto-saved off the main thread.
    func attachPersistence(_ persistence: MinimalPlaylistPersistence) {
        self.persistence = persistence
    }

    private func scheduleSave() {
        guard let persistence else { return }
        let state = snapshot
        Task { await persistence.save(state) }
    }
}
