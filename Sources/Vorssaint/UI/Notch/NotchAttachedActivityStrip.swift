// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The hardware notch owns only the middle. Readable wings remain outside
/// the real camera; secondary activities never borrow either wing.
struct NotchAttachedActivityStrip: View {
    let activity: NotchCompactActivity
    let geometry: NotchGeometry
    let size: CGSize
    var fixtureTitle: String? = nil
    var fixtureReading: String? = nil
    var fixtureAgents: [AgentProvider]? = nil
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var agents = AgentUsageService.shared
    @ObservedObject private var timer = NotchTimerService.shared
    @ObservedObject private var downloads = NotchDownloadService.shared
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var watch = NotchWatchService.shared
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var calls = NotchCallService.shared

    private var tint: Color {
        switch activity {
        case .agents: return providers.first?.tint ?? .cyan
        case .timer: return .orange
        case .calendar: return .mint
        case .keepAwake: return .yellow
        case .call: return .green
        default: return .white
        }
    }
    private var providers: [AgentProvider] {
        fixtureAgents ?? AgentProvider.allCases.filter { provider in agents.snapshot.live.contains { $0.provider == provider } }
    }
    private var title: String {
        if let fixtureTitle { return fixtureTitle }
        switch activity {
        case .music: return music.playback?.track.title ?? "Now playing"
        case .calendar: return calendar.countdown?.event.title ?? "Calendar"
        case .downloads: return downloads.items.first { $0.active && !$0.completed }?.name ?? "Download"
        case .call: return calls.primary?.appName ?? "Call"
        default: return activity.title(L10n.shared.language)
        }
    }

    @ViewBuilder var body: some View {
        if size.width <= geometry.cameraWidth + 1 {
            VStack(spacing: 0) {
                Color.clear.frame(height: geometry.stripHeight)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 5) {
                        if activity == .agents && !providers.isEmpty {
                            ForEach(providers) { NotchAgentGlyph(provider: $0, size: 10) }
                        } else {
                            Image(systemName: activity.symbol).font(.system(size: 11, weight: .semibold))
                            Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        if activity == .music {
                            NotchLiveEqualizerBars(isPlaying: music.playback?.isPlaying == true, bars: 3, barWidth: 2,
                                                   height: 10, tint: .white)
                        } else {
                            Text(fixtureReading ?? reading(at: context.date))
                                .font(.system(size: 10, weight: .medium, design: .monospaced)).lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 24).frame(height: 32).foregroundStyle(tint)
                }
            }
            .frame(width: size.width, height: size.height)
        } else { wings }
    }

    private var wings: some View {
        let wing = max(0, (size.width - geometry.cameraWidth) / 2)
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                if activity == .music {
                    let side = min(24, max(12, geometry.stripHeight - 10))
                    NotchMusicCover(artwork: music.artwork, side: side, radius: side * 0.18)
                } else if activity == .agents && !providers.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(providers) { NotchAgentGlyph(provider: $0, size: min(11, (geometry.stripHeight - 10) / 1.45)) }
                    }.fixedSize()
                } else {
                    Image(systemName: activity.symbol).font(.system(size: 12, weight: .semibold))
                }
                if activity != .agents {
                    Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.tail)
                }
            }
            .padding(.leading, 12).padding(.trailing, 6)
            .frame(width: wing, alignment: .leading).clipped()
            Color.clear.frame(width: geometry.cameraWidth)
            Group {
                if activity == .music && fixtureReading == nil {
                    NotchLiveEqualizerBars(isPlaying: music.playback?.isPlaying == true, bars: 4,
                                           barWidth: 2, height: min(16, geometry.stripHeight - 10),
                                           tint: music.artworkTint?.color ?? .white)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let text = fixtureReading ?? reading(at: context.date)
                        Text(text).font(.system(size: 12, weight: .medium, design: .monospaced))
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            }
            .padding(.leading, 6).padding(.trailing, 12)
            .frame(width: wing, alignment: .trailing).clipped()
        }
        .frame(width: size.width, height: geometry.stripHeight)
        .foregroundStyle(tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(reading(at: Date()))")
    }

    private func reading(at now: Date) -> String {
        switch activity {
        case .timer: return NotchTimerSupport.compactText(for: timer.session, at: timer.now, locale: .current)
        case .agents:
            return NotchAgentSupport.stripReading(agents.snapshot, readout: NotchAgentSupport.readout(),
                                                  display: NotchAgentSupport.limitDisplay(), now: now)
        case .calendar:
            return calendar.countdown.map { NotchCalendarSupport.countdownText(until: $0.target, now: now) } ?? ""
        case .downloads:
            return downloads.items.first { $0.active && !$0.completed }?.fraction.map { "\(Int($0 * 100))%" } ?? "…"
        case .watch: return watch.headline
        case .keepAwake:
            return awake.endDate.map { NotchKeepAwakeSupport.compactText(until: $0, now: now, locale: .current) } ?? "∞"
        case .call: return calls.primary?.elapsed(at: now) ?? ""
        case .music: return music.playback?.track.title ?? ""
        }
    }
}
