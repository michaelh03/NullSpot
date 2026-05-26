//
//  MinimalPlaylistPersistence.swift
//  NullSpot
//
//  Per-user JSON persistence for the Minimal queue. Reads/writes happen on the
//  actor's executor (off the main thread) so even a large queue never stalls UI.
//

import Foundation

actor MinimalPlaylistPersistence {
    private let userId: String

    init(userId: String) {
        self.userId = userId
    }

    func load() -> MinimalPlaylistState? {
        guard let url = Self.fileURL(forUserId: userId) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MinimalPlaylistState.self, from: data)
    }

    func save(_ state: MinimalPlaylistState) {
        guard let url = Self.fileURL(forUserId: userId) else { return }
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clear() {
        Self.deleteFile(forUserId: userId)
    }

    /// Synchronous file delete usable from any context (e.g. logout teardown).
    nonisolated static func deleteFile(forUserId userId: String) {
        guard let url = fileURL(forUserId: userId) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated static func fileURL(forUserId userId: String) -> URL? {
        let fm = FileManager.default
        guard let base = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true,
        ) else { return nil }
        let dir = base.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "NullSpot",
            isDirectory: true,
        )
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("queue-\(userId).json")
    }
}
