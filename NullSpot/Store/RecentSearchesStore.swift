//
//  RecentSearchesStore.swift
//  NullSpot
//
//  Persists the last 10 minimal-search query strings via UserDefaults.
//

import Foundation

@MainActor
@Observable
final class RecentSearchesStore {
    private let defaultsKey = "minimalRecentSearches"
    private let maxEntries = 10

    private(set) var entries: [String]

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        entries = stored
    }

    /// Record a successful search query. Deduplicates case-insensitively and trims to the max.
    func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var updated = entries.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        updated.insert(trimmed, at: 0)
        if updated.count > maxEntries {
            updated = Array(updated.prefix(maxEntries))
        }
        entries = updated
        UserDefaults.standard.set(updated, forKey: defaultsKey)
    }
}
