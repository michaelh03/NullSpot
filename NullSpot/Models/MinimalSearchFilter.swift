//
//  MinimalSearchFilter.swift
//  NullSpot
//

import Foundation

enum MinimalSearchFilter: CaseIterable, Hashable {
    case songs
    case artists
    case albums
    case playlists
    case podcasts

    var searchType: SearchType {
        switch self {
        case .songs: .track
        case .artists: .artist
        case .albums: .album
        case .playlists: .playlist
        case .podcasts: .show
        }
    }

    var localizedTitleKey: String.LocalizationValue {
        switch self {
        case .songs: "minimal.search.filter.songs"
        case .artists: "minimal.search.filter.artists"
        case .albums: "minimal.search.filter.albums"
        case .playlists: "minimal.search.filter.playlists"
        case .podcasts: "minimal.search.filter.podcasts"
        }
    }

    func next() -> MinimalSearchFilter {
        let all = Self.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}
