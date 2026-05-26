//
//  MinimalTransportButton.swift
//  NullSpot
//

import SwiftUI

struct MinimalTransportButton: View {
    let titleKey: LocalizedStringKey
    let icon: String
    let baseSize: Double
    let isActive: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat = 13

    init(
        titleKey: LocalizedStringKey,
        icon: String,
        baseSize: Double,
        isActive: Bool = false,
        action: @escaping () -> Void,
    ) {
        self.titleKey = titleKey
        self.icon = icon
        self.baseSize = baseSize
        self.isActive = isActive
        self.action = action
        _scaledSize = ScaledMetric(wrappedValue: baseSize, relativeTo: .body)
    }

    var body: some View {
        Button(action: action) {
            Label(titleKey, systemImage: icon)
                .labelStyle(.iconOnly)
                .font(.system(size: scaledSize, weight: .semibold))
                .foregroundStyle(MinimalTheme.fg)
                .frame(width: 36, height: 28)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    if isActive {
                        Capsule()
                            .fill(MinimalTheme.fg)
                            .frame(width: 14, height: 1.5)
                            .offset(y: -2)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
