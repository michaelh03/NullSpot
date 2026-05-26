//
//  MinimalTheme.swift
//  NullSpot
//

import SwiftUI

enum MinimalTheme {
    static let bg = Color.white
    static let fg = Color.black
    static let muted = Color.black.opacity(0.55)
    static let divider = Color.black.opacity(0.15)
    static let selection = Color.black.opacity(0.08)

    static let windowWidth: Double = 380
    static let windowHeight: Double = 580
    static let headerHeight: Double = 56

    // Baseline font sizes — wrap with @ScaledMetric in each view for Dynamic Type.
    static let appTitleSize: Double = 11
    static let headerIconSize: Double = 13
    static let nowPlayingTitleSize: Double = 13
    static let nowPlayingArtistSize: Double = 11
    static let rowTitleSize: Double = 12
    static let rowArtistSize: Double = 10
    static let rowMetaSize: Double = 10
    static let markerSize: Double = 9
    static let scrubLabelSize: Double = 9
    static let transportPrimarySize: Double = 18
    static let transportSecondarySize: Double = 13
    static let searchFieldSize: Double = 14
    static let searchHintSize: Double = 12
    static let dismissIconSize: Double = 11
    static let emptyIconSize: Double = 28
}
