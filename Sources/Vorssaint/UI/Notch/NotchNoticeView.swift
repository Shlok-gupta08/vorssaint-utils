// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Level keys unfold beneath a physical camera; other notices keep their
/// compact wings. Floating capsules use their own existing notice view.
struct NotchNoticeView: View {
    let notice: NotchNotice
    let geometry: NotchGeometry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var wingWidth: CGFloat { geometry.noticeWingWidth(preferred: notice.preferredWingWidth) }
    private var inset: CGFloat { min(16, wingWidth / 6) + notice.additionalOuterPadding }
    private var tint: Color {
        switch notice.event {
        // A warning reads as one in any agent's color; other AI notices wear it.
        case .agents: return notice.symbol.hasPrefix("exclamationmark") ? .orange : notice.agent?.tint ?? .white
        default: return .white
        }
    }

    var body: some View {
        if geometry.isNotched, notice.isLevelFeedback {
            NotchUnderCameraLevelView(notice: notice, geometry: geometry)
        } else {
            wings
        }
    }

    private var wings: some View {
        HStack(spacing: 0) {
            leading
                .padding(.leading, inset)
                .padding(.trailing, notice.cameraGap)
                .frame(width: wingWidth, height: geometry.stripHeight)
                .clipped()
            Color.clear.frame(width: geometry.noticeCameraGap)
            trailing
                .padding(.trailing, inset)
                .padding(.leading, notice.cameraGap)
                .frame(width: wingWidth, height: geometry.stripHeight)
                .clipped()
        }
        .foregroundStyle(.white)
        .frame(height: geometry.stripHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.accessibilityText)
    }

    @ViewBuilder private var leading: some View {
        if let content = notice.notification {
            HStack(spacing: NotchNotificationBannerLayout.spacing) {
                NotchNotificationAppIcon(app: content.app, size: min(NotchNotificationBannerLayout.iconSize, geometry.stripHeight - 4))
                Text(content.compactTitle)
                    .font(Font(NotchNotificationBannerLayout.titleFont as CTFont))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(spacing: 8) {
                Group {
                    // A notice about the agent itself wears its mark; warnings
                    // and renewals keep a symbol that says what happened.
                    if notice.event == .agents, let agent = notice.agent, notice.symbol == agent.symbol {
                        NotchAgentMark(provider: agent, size: 13)
                    } else if notice.event == .track {
                        NotchTrackArtwork(size: min(18, geometry.stripHeight - 6))
                    } else {
                        Image(systemName: notice.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(tint)
                    }
                }
                .frame(width: 18)
                Text(notice.level == nil ? notice.title : notice.detail)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(notice.event == .track ? .tail : .middle)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: notice.readsFromEnds ? .leading : .trailing)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: notice.detail)
            .transaction { $0.disablesAnimations = false }
        }
    }

    @ViewBuilder private var trailing: some View {
        if let content = notice.notification {
            Text(content.compactDetail)
                .font(Font(NotchNotificationBannerLayout.messageFont as CTFont))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(geometry.stripHeight >= 30 ? 2 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let level = notice.level {
            NotchMeter(value: level, height: 5, tint: tint)
        } else {
            Text(notice.detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(notice.event == .accessory ? .middle : .tail)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// A quiet extension of the black island, rather than a separate HUD. The
/// native window host morphs the silhouette down and wide from the camera;
/// the logo occupies the left wing, the percentage occupies the right wing,
/// and the slider glides directly beneath the camera.
private struct NotchUnderCameraLevelView: View {
    let notice: NotchNotice
    let geometry: NotchGeometry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var wingWidth: CGFloat {
        max(0, (geometry.underNotchLevelSize.width - geometry.cameraWidth) / 2)
    }

    private var shoulderInset: CGFloat {
        NotchLayout.shoulder(height: geometry.stripHeight)
    }

    private var sliderWidth: CGFloat {
        max(120, min(geometry.cameraWidth - 16, geometry.underNotchLevelSize.width - 64))
    }

    private var iconSize: CGFloat {
        min(18, max(15, geometry.stripHeight * 0.5))
    }

    private var fontSize: CGFloat {
        min(14, max(12.5, geometry.stripHeight * 0.42))
    }

    var body: some View {
        VStack(spacing: 0) {
            wingsRow
            sliderRow
        }
        .frame(width: geometry.underNotchLevelSize.width, height: geometry.underNotchLevelSize.height, alignment: .top)
        .foregroundStyle(.white)
        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: notice.level)
        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: notice.symbol)
        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: notice.detail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.accessibilityText)
        .accessibilityIdentifier("notch.level.belowCamera")
    }

    private var wingsRow: some View {
        HStack(spacing: 0) {
            // Left wing: prominent audio/display glyph starting from the top bezel
            Image(systemName: notice.symbol)
                .font(.system(size: iconSize, weight: .semibold))
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .foregroundStyle(.white.opacity(0.95))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.leading, max(6, shoulderInset * 0.6))
                .padding(.trailing, 4)
                .frame(width: wingWidth, height: geometry.stripHeight)
                .clipped()
                .accessibilityHidden(true)

            // Gap covering the physical camera cutout
            Color.clear
                .frame(width: geometry.cameraWidth, height: geometry.stripHeight)

            // Right wing: prominent level percentage starting from the top bezel
            Text(notice.detail)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.trailing, max(6, shoulderInset * 0.6))
                .padding(.leading, 4)
                .frame(width: wingWidth, height: geometry.stripHeight)
                .clipped()
        }
        .frame(height: geometry.stripHeight)
        .transaction { $0.disablesAnimations = false }
    }

    private var sliderRow: some View {
        HStack {
            NotchMeter(value: notice.level ?? 0, height: 5, tint: .white.opacity(0.95))
                .frame(width: sliderWidth)
        }
        .frame(height: 22)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(width: geometry.underNotchLevelSize.width,
               height: geometry.underNotchLevelSize.height - geometry.stripHeight)
    }
}

/// The new song's cover, read as it arrives: it often lands after the title.
private struct NotchTrackArtwork: View {
    @ObservedObject private var music = NotchMusicService.shared
    let size: CGFloat

    var body: some View { NotchArtwork(image: music.artwork, size: size) }
}

/// Level feedback occupies the header while the current page stays usable.
struct NotchExpandedLevelView: View {
    let notice: NotchNotice

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notice.symbol)
                .frame(width: 18)
            NotchMeter(value: notice.level ?? 0, height: 5, tint: .white)
                .frame(maxWidth: 96)
            Text(notice.detail)
                .monospacedDigit()
                .fixedSize()
        }
        .font(.system(size: 11, weight: .medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.accessibilityText)
    }
}
