// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Compact physical-notch strip for the Shelf Drop Live Activity.
/// Hovering over it expands the Shelf directly instead of Control Center.
struct NotchShelfStrip: View {
    @ObservedObject var service: NotchService
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var shelf = ShelfService.shared
    @ObservedObject private var l10n = L10n.shared

    private var geometry: NotchGeometry { displayGeometry ?? service.compactActivityGeometry }
    private var iconSize: CGFloat { NotchTimerSupport.stripIconSize(height: geometry.compactActivityContentHeight) }
    private var textSize: CGFloat { NotchTimerSupport.stripTextSize(height: geometry.compactActivityContentHeight) }
    private var iconInset: CGFloat {
        guard !geometry.compactActivityUsesFooter else { return 0 }
        return geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2)
    }
    private var textInset: CGFloat {
        guard !geometry.compactActivityUsesFooter else { return 0 }
        return geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0)
    }

    var body: some View {
        let countdown = ShelfLiveActivitySupport.countdownText(shelf.liveActivityRemaining)
        HStack(spacing: 0) {
            Group {
                if geometry.compactActivityWingWidth >= 28 {
                    HStack(spacing: 4) {
                        Image(systemName: "tray.full.fill")
                            .font(.system(size: iconSize * 0.9, weight: .medium))
                            .foregroundStyle(Color.cyan)
                        if geometry.compactActivityWingWidth >= 56 {
                            Text("\(shelf.itemCount)")
                                .font(.system(size: max(10, textSize - 2), weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.88))
                        }
                    }
                }
            }
            .padding(.leading, iconInset)
            .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight, alignment: .leading)

            Color.clear.frame(width: geometry.compactActivityCameraGap)

            Group {
                if geometry.compactActivityWingWidth >= 42 {
                    Text(countdown)
                        .font(.system(size: textSize, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Color.cyan)
                        .lineLimit(1).minimumScaleFactor(0.65)
                        .contentTransition(.numericText(countsDown: true))
                        .onChange(of: NotchAgentSupport.readingShape(countdown)) { _, _ in
                            DispatchQueue.main.async { service.refreshPresentation() }
                        }
                }
            }
            .padding(.trailing, textInset)
            .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight, alignment: .trailing)
        }
        .frame(height: geometry.compactActivityContentHeight)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(FeatureStrings.notch(l10n.language).files), \(shelf.itemCount)")
        .accessibilityValue(countdown)
    }
}

/// Floating-capsule strip for the Shelf Drop Live Activity.
struct NotchCapsuleShelfStrip: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var shelf = ShelfService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let geometry = displayGeometry ?? service.geometry
        let side = NotchCapsuleLayout.side(geometry)
        let countdown = ShelfLiveActivitySupport.countdownText(shelf.liveActivityRemaining)
        HStack(spacing: NotchCapsuleLayout.spacing) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: NotchCapsuleLayout.symbolSize, weight: .medium))
                .foregroundStyle(.cyan)
                .frame(width: NotchCapsuleLayout.symbolWidth)
            Text("\(shelf.itemCount)")
                .font(Font(NotchCapsuleLayout.titleFont as CTFont))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(countdown)
                .font(Font(NotchCapsuleLayout.smallFont as CTFont))
                .monospacedDigit()
                .foregroundStyle(.cyan.opacity(0.9))
                .contentTransition(.numericText(countsDown: true))
        }
        .padding(.horizontal, side + NotchCapsuleLayout.endPadding)
        .frame(width: size.width, height: geometry.stripHeight)
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(FeatureStrings.notch(l10n.language).files), \(shelf.itemCount)")
        .accessibilityValue(countdown)
    }
}
