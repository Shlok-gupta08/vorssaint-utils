// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Pulsing crimson recording dot (or amber pause badge when paused).
struct NotchRecordingGlyph: View {
    var paused: Bool
    var size: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Group {
            if paused {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(.orange)
            } else {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(pulse ? 0.36 : 0.14))
                        .frame(width: size + 4, height: size + 4)
                        .scaleEffect(pulse ? 1.15 : 0.88)
                    Circle()
                        .fill(Color(red: 0.98, green: 0.27, blue: 0.25))
                        .frame(width: max(7, size * 0.66), height: max(7, size * 0.66))
                }
                .frame(width: size + 4, height: size + 4)
                .onAppear { startPulse() }
            }
        }
        .onChange(of: paused) { _, isPaused in
            if !isPaused { startPulse() } else { pulse = false }
        }
    }

    private func startPulse() {
        guard !reduceMotion, !paused else { pulse = false; return }
        pulse = false
        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}

/// Physical-notch compact strip for an active screen recording.
struct NotchRecordingStrip: View {
    @ObservedObject var service: NotchService
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var recorder = NotchSystemRecordingService.shared

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
        let label = recorder.elapsedLabel
        HStack(spacing: 0) {
            Group {
                if geometry.compactActivityWingWidth >= 28 {
                    NotchRecordingGlyph(paused: recorder.isPaused, size: iconSize)
                }
            }
            .padding(.leading, iconInset + 6)
            .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight, alignment: .leading)

            Color.clear.frame(width: geometry.compactActivityCameraGap)

            Group {
                if geometry.compactActivityWingWidth >= 42 {
                    Text(label)
                        .font(.system(size: textSize, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(recorder.isPaused ? Color.orange : Color(red: 1.0, green: 0.34, blue: 0.32))
                        .lineLimit(1).minimumScaleFactor(0.65)
                        .contentTransition(.numericText())
                        .onChange(of: NotchAgentSupport.readingShape(label)) { _, _ in
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
        .accessibilityLabel(recorder.isPaused ? "Screen recording paused" : "Screen recording")
        .accessibilityValue(label)
    }
}

/// Floating-capsule compact strip for an active screen recording.
struct NotchCapsuleRecordingStrip: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var recorder = NotchSystemRecordingService.shared

    var body: some View {
        let geometry = displayGeometry ?? service.geometry
        let side = NotchCapsuleLayout.side(geometry)
        let label = recorder.elapsedLabel
        HStack(spacing: NotchCapsuleLayout.spacing) {
            NotchRecordingGlyph(paused: recorder.isPaused, size: NotchCapsuleLayout.symbolSize)
                .frame(width: NotchCapsuleLayout.symbolWidth)
            Text(label)
                .font(Font(NotchCapsuleLayout.readingFont as CTFont))
                .monospacedDigit()
                .foregroundStyle(recorder.isPaused ? Color.orange : Color(red: 1.0, green: 0.36, blue: 0.34))
                .lineLimit(1).fixedSize()
                .contentTransition(.numericText())
                .onChange(of: NotchAgentSupport.readingShape(label)) { _, _ in
                    DispatchQueue.main.async { service.refreshPresentation() }
                }
        }
        .padding(.leading, side + NotchCapsuleLayout.endPadding + 4)
        .padding(.trailing, side + NotchCapsuleLayout.endPadding)
        .frame(width: size.width, height: geometry.stripHeight)
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recorder.isPaused ? "Screen recording paused" : "Screen recording")
        .accessibilityValue(label)
    }
}

/// Expanded screen recording live activity with live timer, audio badges, pause/resume and stop.
struct NotchRecordingPanel: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var recorder = NotchSystemRecordingService.shared
    @ObservedObject private var l10n = L10n.shared
    private var strings: RecorderFeatureStrings { FeatureStrings.recorder(l10n.language) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                NotchRecordingGlyph(paused: recorder.isPaused, size: 16)
                    .frame(width: 34, height: 34)
                    .background(
                        (recorder.isPaused ? Color.orange : Color.red).opacity(0.14),
                        in: Circle()
                    )
                    .overlay(
                        Circle().strokeBorder(
                            (recorder.isPaused ? Color.orange : Color.red).opacity(0.28),
                            lineWidth: 0.75
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(recorder.isPaused ? "Paused" : "Recording")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(recorder.displayLabel(for: service.displayID))
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.10), in: Capsule())
                        if recorder.capturesSystemAudio {
                            audioBadge("speaker.wave.2.fill", help: "System audio")
                        }
                        if recorder.capturesMicrophone {
                            audioBadge("mic.fill", help: "Microphone")
                        }
                    }
                    Text(recorder.elapsedLabel)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(recorder.isPaused ? Color.orange : Color.white.opacity(0.92))
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    if recorder.canPause {
                        Button(action: recorder.togglePause) {
                            Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.11), in: Circle())
                                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                                .contentShape(Circle())
                        }
                        .buttonStyle(NotchButtonStyle(cornerRadius: 17))
                        .help(recorder.isPaused ? strings.resumeButton : strings.pauseButton)
                        .accessibilityLabel(recorder.isPaused ? strings.resumeButton : strings.pauseButton)
                    }

                    Button {
                        recorder.stop()
                    } label: {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(Color.white)
                                .frame(width: 10, height: 10)
                            Text(strings.stopButton)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .background(Color(red: 0.92, green: 0.24, blue: 0.22), in: Capsule(style: .continuous))
                        .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(NotchButtonStyle(cornerRadius: 17))
                    .help(strings.stopButton)
                    .accessibilityLabel(strings.stopButton)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, service.geometry.safeContentTop + 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .contextMenu {
            Button("Controls") { service.select(.controls) }
            Button("Sections") { service.toggleSections() }
        }
    }

    private func audioBadge(_ symbol: String, help: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
            .frame(width: 18, height: 18)
            .background(.white.opacity(0.09), in: Circle())
            .help(help)
    }
}
