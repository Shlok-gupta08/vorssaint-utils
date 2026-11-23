// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Recording content. The island's native host owns its contour and backdrop;
/// fixed frequency bars respond in place to microphone audio.
struct NotchDictationView: View {
    let topInset: CGFloat
    @ObservedObject var speech = DictationService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    private var text: DictationStrings { .localized(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
                .frame(height: 28)

            Spacer(minLength: 6)

            centerContent

            if speech.phase == .recording {
                Spacer(minLength: 4)
                recordingFooter
            }
        }
        .padding(.horizontal, NotchLayout.horizontalInset)
        .padding(.top, topInset + 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("notch.dictation")
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: speech.phase)
        .onAppear { startPulseIfNeeded() }
        .onChange(of: speech.phase) { _, _ in startPulseIfNeeded() }
    }

    private var topRow: some View {
        HStack(spacing: 9) {
            statusBadge
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 8)

            if speech.phase == .recording {
                HStack(spacing: 6) {
                    Text(Duration.seconds(speech.elapsed).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.72))
                        .contentTransition(.numericText())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.075), in: Capsule(style: .continuous))
                        .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
                        .accessibilityLabel("Elapsed time")

                    Button(action: speech.finish) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color.white)
                                .frame(width: 7.5, height: 7.5)
                        }
                        .frame(width: 26, height: 26)
                        .background(
                            Color(red: 0.94, green: 0.30, blue: 0.28).opacity(0.88),
                            in: Circle()
                        )
                        .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                        .contentShape(Circle())
                    }
                    .buttonStyle(NotchButtonStyle(cornerRadius: 13))
                    .help(text.stop)
                    .accessibilityLabel(text.stop)
                }
            } else if speech.phase == .processing || speech.phase == .requestingPermission {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.75)
                    .tint(.white.opacity(0.75))
            } else {
                HStack(spacing: 5) {
                    if speech.phase == .completed, !speech.result.isEmpty {
                        circleAction("doc.on.doc", title: text.copied, action: speech.copyResult)
                    }
                    circleAction("clock.arrow.circlepath", title: text.history, action: openHistory)
                }
            }

            circleAction("xmark", title: text.cancel) {
                if speech.phase.isBusy { speech.cancel() } else { speech.dismiss() }
            }
        }
    }

    @ViewBuilder private var statusBadge: some View {
        switch speech.phase {
        case .recording:
            ZStack {
                Circle()
                    .fill(Color(red: 0.96, green: 0.32, blue: 0.30).opacity(pulse ? 0.28 : 0.12))
                    .frame(width: 22, height: 22)
                    .scaleEffect(pulse ? 1.12 : 0.92)
                Circle()
                    .fill(Color(red: 0.98, green: 0.34, blue: 0.31))
                    .frame(width: 8, height: 8)
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
        case .processing:
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 22, height: 22)
                .background(.white.opacity(0.10), in: Circle())
                .accessibilityHidden(true)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(red: 0.32, green: 0.86, blue: 0.52))
                .frame(width: 22, height: 22)
                .background(Color(red: 0.32, green: 0.86, blue: 0.52).opacity(0.16), in: Circle())
                .accessibilityHidden(true)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.orange)
                .frame(width: 22, height: 22)
                .background(Color.orange.opacity(0.16), in: Circle())
                .accessibilityHidden(true)
        case .idle, .requestingPermission:
            Image(systemName: "mic.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 22, height: 22)
                .background(.white.opacity(0.10), in: Circle())
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var centerContent: some View {
        switch speech.phase {
        case .recording:
            DictationWaveform(bars: speech.waveform)
                .frame(height: 34)
        case .failed:
            HStack(alignment: .center, spacing: 10) {
                Text(speech.error ?? text.failed)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !speech.result.isEmpty {
                    circleAction("doc.on.doc", title: text.copied, action: speech.copyResult)
                }
                circleAction("gearshape", title: text.title, action: showSettings)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        case .completed:
            Button(action: openHistory) {
                HStack(alignment: .center, spacing: 8) {
                    Text(speech.result)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.32))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 11, lifts: false))
            .help(text.history)
        case .processing, .requestingPermission, .idle:
            HStack(spacing: 8) {
                Text(speech.phase == .requestingPermission ? "Waiting for microphone permission…" : "Transcribing on this Mac…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }

    private var recordingFooter: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Text("esc")
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                Text("Cancel")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }

            Spacer()

            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.38))
                Text("On-Device")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func circleAction(_ symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.68))
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.075), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 13))
        .help(title)
        .accessibilityLabel(title)
    }

    private func startPulseIfNeeded() {
        guard !reduceMotion, speech.phase == .recording else {
            pulse = false
            return
        }
        pulse = false
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            pulse = true
        }
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

    private func openHistory() {
        guard !speech.phase.isBusy else { return }
        speech.dismiss()
        NotchService.shared.open(.dictation)
    }

    private func showSettings() {
        speech.dismiss()
        SettingsRouter.shared.request(FeatureSettingsDestination(.dictation))
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }
}

struct DictationWaveform: View {
    let bars: [Double]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(bars.indices, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(0.28 + bars[index] * 0.58))
                    .frame(width: 3, height: 3 + bars[index] * 27)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .interpolatingSpring(stiffness: 260, damping: 25), value: bars)
        .accessibilityHidden(true)
    }
}
