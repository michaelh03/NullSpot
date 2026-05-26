//
//  MinimalDivider.swift
//  NullSpot
//

import SwiftUI

struct MinimalDivider: View {
    var body: some View {
        Rectangle()
            .fill(MinimalTheme.divider)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
