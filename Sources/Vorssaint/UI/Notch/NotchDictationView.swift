// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Compact, opaque working surface below the camera housing. The island's
/// existing window host animates both width and height around this content.
struct NotchDictationView: View {
    let topInset: CGFloat
    @ObservedObject var speech = DictationService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: DictationStrings { .localized(l10n.language) }
    private var accent: Color { speech.phase == .failed ? .orange : .mint }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(speech.phase == .recording ? "fn · esc" : text.title)
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 8)
                if speech.phase == .recording {
                    Text(Duration.seconds(speech.elapsed).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.85))
                    NotchIconButton(symbol: "stop.fill", title: text.stop, action: speech.finish)
                } else if speech.phase == .processing || speech.phase == .requestingPermission {
                    ProgressView().controlSize(.small).tint(.mint)
                }
                NotchIconButton(symbol: "xmark", title: text.cancel) {
                    if speech.phase.isBusy { speech.cancel() } else { speech.dismiss() }
                }
            }
            if speech.phase == .recording {
                DictationWaveform(levels: speech.levels, tint: accent)
                    .frame(height: 28)
                    .accessibilityLabel(text.recording)
            } else if speech.phase == .failed {
                HStack(alignment: .top, spacing: 10) {
                    Text(speech.error ?? text.failed)
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                        .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                    if !speech.result.isEmpty {
                        NotchIconButton(symbol: "doc.on.doc", title: text.copied, action: speech.copyResult)
                    }
                    Button { showSettings() } label: { Image(systemName: "gearshape") }
                        .buttonStyle(.plain).help(text.title)
                }
            } else if speech.phase == .completed {
                Button {
                    speech.dismiss()
                    NotchService.shared.open(.dictation)
                } label: {
                    HStack {
                        Text(speech.result).lineLimit(2).multilineTextAlignment(.leading)
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                        Spacer(minLength: 8)
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(.mint)
                    }
                }.buttonStyle(.plain).help(text.history)
            } else {
                Text(speech.phase == .requestingPermission ? "Waiting for microphone permission…" : "Speech stays on your Mac")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 24).padding(.top, topInset + 8).padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .accessibilityIdentifier("notch.dictation")
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: speech.phase)
    }

    private var title: String {
        switch speech.phase {
        case .recording: return text.recording
        case .processing: return text.processing
        case .completed: return speech.status
        case .failed: return text.failed
        case .idle, .requestingPermission: return text.title
        }
    }
    private var symbol: String {
        switch speech.phase {
        case .completed: return "checkmark"
        case .failed: return "exclamationmark"
        case .processing: return "waveform"
        default: return "mic.fill"
        }
    }
    private func showSettings() {
        speech.dismiss()
        SettingsRouter.shared.request(FeatureSettingsDestination(.dictation))
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }
}

struct DictationWaveform: View {
    let levels: [Double]
    var tint = Color.mint
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule().fill(tint.opacity(0.45 + level * 0.55))
                        .frame(height: max(3, geometry.size.height * CGFloat(min(1, level * 2))))
                }
            }.frame(height: geometry.size.height)
        }
        .accessibilityHidden(true)
    }
}
