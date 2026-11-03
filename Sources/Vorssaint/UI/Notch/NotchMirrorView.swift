// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// What the island shows closed, drawn for another display. It takes no
/// clicks itself: a click on its window brings the island there, open.
struct NotchMirrorView: View {
    @ObservedObject var service: NotchService
    @ObservedObject var mirror: NotchMirrorModel

    var body: some View {
        Group {
            if let deck = mirror.deck {
                ZStack(alignment: .top) {
                    ForEach(deck.items) { item in
                        let primary = item.activity == mirror.activity
                        let geometry = primary ? mirror.geometry : (mirror.geometry.floats
                            ? mirror.geometry : NotchAttachedActivityLayout.satelliteGeometry(mirror.geometry))
                        content(geometry: geometry, strip: primary ? mirror.strip : geometry,
                                size: item.size, activity: item.activity)
                            .frame(width: item.size.width, height: item.size.height, alignment: .top)
                            .background(Color.black, in: NotchShape.island(height: item.size.height, geometry: geometry))
                            .clipShape(NotchShape.island(height: item.size.height, geometry: geometry))
                            .overlay {
                                if mirror.outline == true {
                                    NotchShape.island(height: item.size.height, geometry: geometry)
                                        .stroke(item.activity == .timer ? Color.orange : Color.white,
                                                lineWidth: NotchLayout.outlineWidth)
                                }
                            }
                            .offset(x: item.x)
                    }
                }
            } else {
                content(geometry: mirror.geometry, strip: mirror.strip, size: mirror.size, activity: mirror.activity)
            }
        }
            .frame(width: mirror.size.width, height: mirror.size.height, alignment: .top)
            .foregroundStyle(.white)
            .allowsHitTesting(false)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
            .environment(\.notchPresentation, true)
            .tint(.white)
            .accessibilityHidden(true)
    }

    @ViewBuilder private func content(geometry: NotchGeometry, strip: NotchGeometry, size: CGSize,
                                      activity: NotchCompactActivity?) -> some View {
        if let activity {
            if geometry.floats {
                switch activity {
                case .call: NotchCallStrip(geometry: geometry, size: size)
                case .timer: NotchCapsuleTimerStrip(service: service, size: size, displayGeometry: geometry)
                case .watch: NotchCapsuleWatchStrip(service: service, size: size, displayGeometry: geometry)
                case .downloads: NotchCapsuleDownloadStrip(service: service, size: size, displayGeometry: geometry)
                case .agents: NotchCapsuleAgentStrip(service: service, size: size, displayGeometry: geometry)
                case .calendar: NotchCapsuleCalendarStrip(service: service, size: size, displayGeometry: geometry)
                case .music: NotchCapsuleMusicStrip(service: service, size: size, displayGeometry: geometry)
                case .keepAwake: NotchCapsuleKeepAwakeStrip(service: service, size: size, displayGeometry: geometry)
                }
            } else {
                switch activity {
                case .call: NotchCallStrip(geometry: strip, size: size)
                case .timer: NotchTimerStrip(service: service, displayGeometry: strip)
                case .watch: NotchWatchStrip(service: service, displayGeometry: strip)
                case .downloads: NotchDownloadStrip(service: service, displayGeometry: strip)
                case .agents: NotchAgentStrip(service: service, displayGeometry: strip)
                case .calendar: NotchCalendarStrip(service: service, displayGeometry: strip)
                case .music: NotchMusicStrip(service: service, displayGeometry: strip)
                case .keepAwake: NotchKeepAwakeStrip(service: service, displayGeometry: strip)
                }
            }
        } else if geometry.floats {
            NotchCapsuleRestingView(service: service, size: size, displayGeometry: geometry)
        } else {
            NotchRestingStrip(service: service, displayGeometry: geometry)
        }
    }
}
