//
//  MinimalMarqueeText.swift
//  NullSpot
//
//  Single-line text that scrolls horizontally Winamp-style when its natural
//  width exceeds the container, otherwise renders as a plain one-line Text.
//
//  Width is measured synchronously via NSFont so the scroll/static decision
//  is made before layout, never one frame behind. A hidden sizer Text gives
//  the cell its 1-line height and accepts the parent's proposed width; the
//  visible content (static or marquee HStack) sits in an overlay and is
//  clipped to that frame, so a long string can't inflate the parent layout.
//

import AppKit
import SwiftUI

struct MinimalMarqueeText: View {
    let text: String
    let fontSize: CGFloat
    let weight: Font.Weight
    let color: Color
    var pointsPerSecond: Double = 25
    var gap: CGFloat = 40
    var startDelay: Double = 1.5

    @State private var startDate: Date = .now

    private var font: Font { .system(size: fontSize, weight: weight) }

    var body: some View {
        let textWidth = measureWidth()
        Text(text)
            .font(font)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hidden()
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    if textWidth > geo.size.width {
                        scrollingContent(textWidth: textWidth)
                    } else {
                        Text(text)
                            .font(font)
                            .foregroundStyle(color)
                            .lineLimit(1)
                    }
                }
            }
            .clipped()
            .onChange(of: text) { _, _ in startDate = .now }
    }

    private func measureWidth() -> CGFloat {
        let nsFont = NSFont.systemFont(ofSize: fontSize, weight: nsFontWeight)
        let attrs: [NSAttributedString.Key: Any] = [.font: nsFont]
        return ceil((text as NSString).size(withAttributes: attrs).width)
    }

    private var nsFontWeight: NSFont.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }

    private func scrollingContent(textWidth: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let cycleWidth = textWidth + gap
            let cycleSeconds = cycleWidth / pointsPerSecond
            let elapsed = max(0, context.date.timeIntervalSince(startDate) - startDelay)
            let phase = CGFloat(elapsed.truncatingRemainder(dividingBy: cycleSeconds)) * pointsPerSecond

            HStack(spacing: gap) {
                cell
                cell
            }
            .offset(x: -phase)
        }
    }

    private var cell: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }
}
