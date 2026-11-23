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
            if let notice = mirror.notice {
                if mirror.noticeExpanded, let content = notice.notification {
                    NotchNotificationPreviewView(notice: notice, content: content, service: service)
                        .padding(.horizontal, NotchLayout.horizontalInset)
                        .padding(.top, mirror.geometry.safeContentTop)
                        .padding(.bottom, NotchLayout.bottomInset)
                } else if mirror.geometry.floats {
                    NotchCapsuleNoticeView(notice: notice, geometry: mirror.geometry, size: mirror.size)
                } else {
                    NotchNoticeView(notice: notice, geometry: mirror.geometry, size: mirror.size)
                }
            } else if let deck = mirror.deck {
                ZStack(alignment: .top) {
                    ForEach(deck.items) { item in
                        let primary = item.activity == mirror.activity
                        let geometry = primary ? mirror.geometry : (mirror.geometry.floats
                            ? mirror.geometry : NotchAttachedActivityLayout.satelliteGeometry(mirror.geometry))
                        Group {
                            if primary || service.widenedPillActivities.contains(item.activity) {
                                content(geometry: geometry, strip: primary ? mirror.strip : geometry,
                                        size: item.size, activity: item.activity)
                            } else {
                                NotchPillCompactMark(activity: item.activity, geometry: geometry,
                                                     physicalSide: mirror.geometry.isNotched,
                                                     onReadingShapeChange: { service.refreshPresentation() })
                            }
                        }
                            .modifier(NotchActivityViewport(size: item.size, x: item.x,
                                geometry: geometry, focused: primary, cameraLevel: false))
                    }
                }
            } else {
                content(geometry: mirror.geometry, strip: mirror.strip, size: mirror.size, activity: mirror.activity)
            }
        }
            .frame(width: mirror.size.width, height: mirror.size.height, alignment: .top)
            .foregroundStyle(.white)
            .allowsHitTesting(mirror.noticeExpanded)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
            .environment(\.notchPresentation, true)
            .tint(.white)
            .accessibilityHidden(!mirror.noticeExpanded)
    }

    @ViewBuilder private func content(geometry: NotchGeometry, strip: NotchGeometry, size: CGSize,
                                      activity: NotchCompactActivity?) -> some View {
        let mirrorDisplayID = NSScreen.screens.first(where: { $0.frame == mirror.geometry.screen })?.notchDisplayID
        let effectiveActivity: NotchCompactActivity? = (activity == .recording && !NotchSystemRecordingService.shared.isActive(on: mirrorDisplayID))
            ? nil : activity
        if let activity = effectiveActivity {
            if geometry.floats {
                switch activity {
                case .shortcuts: NotchShortcutsStrip(geometry: geometry, size: size)
                case .call: NotchCallStrip(geometry: geometry, size: size)
                case .timer: NotchCapsuleTimerStrip(service: service, size: size, displayGeometry: geometry)
                case .recording: NotchCapsuleRecordingStrip(service: service, size: size, displayGeometry: geometry)
                case .shelf: NotchCapsuleShelfStrip(service: service, size: size, displayGeometry: geometry)
                case .teleprompter: NotchCapsuleTeleprompterStrip(service: service, size: size, displayGeometry: geometry)
                case .watch: NotchCapsuleWatchStrip(service: service, size: size, displayGeometry: geometry)
                case .downloads: NotchCapsuleDownloadStrip(service: service, size: size, displayGeometry: geometry)
                case .agents: NotchCapsuleAgentStrip(service: service, size: size, displayGeometry: geometry)
                case .calendar: NotchCapsuleCalendarStrip(service: service, size: size, displayGeometry: geometry)
                case .music: NotchCapsuleMusicStrip(service: service, size: size, displayGeometry: geometry)
                case .keepAwake: NotchCapsuleKeepAwakeStrip(service: service, size: size, displayGeometry: geometry)
                }
            } else {
                switch activity {
                case .shortcuts: NotchShortcutsStrip(geometry: strip, size: size)
                case .call: NotchCallStrip(geometry: strip, size: size)
                case .timer: NotchTimerStrip(service: service, displayGeometry: strip)
                case .recording: NotchRecordingStrip(service: service, displayGeometry: strip)
                case .shelf: NotchShelfStrip(service: service, displayGeometry: strip)
                case .teleprompter: NotchTeleprompterStrip(service: service, displayGeometry: strip)
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
