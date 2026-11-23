// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Dynamic Island Teleprompter positioned directly under the MacBook camera lens.
/// Supports word-by-word Voice Tracking, Voice Pace auto-pause, Steady Scroll,
/// horizontal mirror mode, countdown, and inline script editing.
struct NotchTeleprompterView: View {
    let size: CGSize
    @ObservedObject private var prompter = NotchTeleprompterService.shared
    @State private var editing = false
    @State private var draftTitle = ""
    @State private var draftBody = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            if editing {
                editorBody
                toolbar
            } else {
                prompterBody
                VStack(spacing: 5) {
                    transportBar
                    toolbar
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .onKeyPress(.space) {
            guard !editing else { return .ignored }
            prompter.togglePlayPause()
            return .handled
        }
    }

    // MARK: - Top Bar

    private var toolbar: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(prompter.scripts) { script in
                    Button {
                        prompter.selectedScriptID = script.id
                    } label: {
                        if script.id == prompter.selectedScriptID {
                            Label(script.title, systemImage: "checkmark")
                        } else {
                            Text(script.title)
                        }
                    }
                }
                Divider()
                Button {
                    let created = prompter.createScript(title: "New Script", body: "")
                    draftTitle = created.title
                    draftBody = created.body
                    editing = true
                } label: {
                    Label("New Script", systemImage: "plus")
                }
                Button {
                    prompter.importFromClipboard()
                } label: {
                    Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                    Text(prompter.selectedScript.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(.white.opacity(0.08), in: Capsule(style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                ForEach(TeleprompterTrackingMode.allCases) { mode in
                    Button {
                        prompter.settings.trackingMode = mode
                    } label: {
                        if prompter.settings.trackingMode == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Label(mode.title, systemImage: mode.symbol)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: prompter.settings.trackingMode.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(prompter.isPlaying && !prompter.isPaused ? Color.cyan : Color.white.opacity(0.75))
                    Text(prompter.settings.trackingMode.title)
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(
                    (prompter.isPlaying && !prompter.isPaused ? Color.cyan.opacity(0.16) : Color.white.opacity(0.07)),
                    in: Capsule(style: .continuous)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer(minLength: 4)

            if !editing {
                // Quick mirror toggle
                Button {
                    prompter.settings.mirrorHorizontally.toggle()
                } label: {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(prompter.settings.mirrorHorizontally ? Color.cyan : Color.white.opacity(0.58))
                        .frame(width: 24, height: 24)
                        .background(prompter.settings.mirrorHorizontally ? Color.cyan.opacity(0.16) : Color.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Mirror text horizontally")

                // Font size steppers
                HStack(spacing: 2) {
                    Button {
                        prompter.settings.fontSize = max(TeleprompterSettings.fontSizeRange.lowerBound, prompter.settings.fontSize - 1.5)
                    } label: {
                        Text("A-").font(.system(size: 9.5, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    Button {
                        prompter.settings.fontSize = min(TeleprompterSettings.fontSizeRange.upperBound, prompter.settings.fontSize + 1.5)
                    } label: {
                        Text("A+").font(.system(size: 10.5, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.72))
                .background(.white.opacity(0.06), in: Capsule())
            }

            Button {
                if editing {
                    prompter.updateSelectedScript(title: draftTitle, body: draftBody)
                    editing = false
                } else {
                    if prompter.isPlaying { prompter.pause() }
                    draftTitle = prompter.selectedScript.title
                    draftBody = prompter.selectedScript.body
                    editing = true
                }
            } label: {
                Text(editing ? "Done" : "Edit")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(editing ? Color.black : Color.white.opacity(0.82))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(editing ? Color.white : Color.white.opacity(0.09), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                SettingsRouter.shared.request(FeatureSettingsDestination(.teleprompter))
                (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Teleprompter Settings")
        }
        .frame(height: 26)
    }

    // MARK: - Prompter Reading Viewport

    private var prompterBody: some View {
        ZStack {
            if prompter.words.isEmpty {
                VStack(spacing: 8) {
                    Text("Your script is empty.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Button("Paste from Clipboard") {
                        prompter.importFromClipboard()
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: prompter.settings.lineSpacing + 6) {
                            Color.clear.frame(height: 4)
                            ForEach(prompter.paragraphs) { paragraph in
                                TeleprompterWordFlow(spacing: 4, lineSpacing: prompter.settings.lineSpacing) {
                                    ForEach(paragraph.words) { word in
                                        wordView(word)
                                            .id(word.id)
                                    }
                                }
                            }
                            Color.clear.frame(height: max(40, size.height * 0.45))
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scaleEffect(x: prompter.settings.mirrorHorizontally ? -1 : 1, y: 1)
                    .onChange(of: prompter.currentWordIndex) { _, target in
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                            proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: 0.12))
                        }
                    }
                    .onAppear {
                        proxy.scrollTo(prompter.currentWordIndex, anchor: UnitPoint(x: 0.5, y: 0.12))
                    }
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .white, location: 0.04),
                            .init(color: .white, location: 0.84),
                            .init(color: .clear, location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .top) {
                    if prompter.settings.showReadingGuide {
                        HStack(spacing: 4) {
                            Image(systemName: "arrowtriangle.right.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(Color.cyan.opacity(0.75))
                            Rectangle()
                                .fill(Color.cyan.opacity(0.14))
                                .frame(height: 1)
                        }
                        .padding(.horizontal, 2)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                    }
                }
            }

            // 3-2-1 Countdown Overlay
            if prompter.countdownRemaining > 0 {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.76))
                    VStack(spacing: 4) {
                        Text("\(prompter.countdownRemaining)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(countsDown: true))
                        Text("Look at the camera")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.07), lineWidth: 0.5))
    }

    private func wordView(_ word: TeleprompterWord) -> some View {
        let isCurrent = word.id == prompter.currentWordIndex
        let isSpoken = word.id < prompter.currentWordIndex
        return Text(word.text)
            .font(.system(size: prompter.settings.fontSize, weight: isCurrent ? .semibold : .medium, design: .rounded))
            .foregroundStyle(
                isCurrent ? Color.white
                    : isSpoken ? Color.white.opacity(0.30)
                    : Color.white.opacity(0.90)
            )
            // Keep padding constant so lines never reflow or jitter when the active word advances.
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.cyan.opacity(0.28))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { prompter.jumpTo(wordIndex: word.id) }
    }

    // MARK: - Bottom Transport Bar

    private var transportBar: some View {
        HStack(spacing: 8) {
            Button(action: prompter.togglePlayPause) {
                HStack(spacing: 5) {
                    Image(systemName: prompter.isPlaying && !prompter.isPaused ? "pause.fill" : "play.fill")
                        .font(.system(size: 10.5, weight: .bold))
                    Text(prompter.isPlaying && !prompter.isPaused ? "Pause" : prompter.isPaused ? "Resume" : "Start")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(
                    prompter.isPlaying && !prompter.isPaused ? Color.cyan : Color.white,
                    in: Capsule(style: .continuous)
                )
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 13))

            Button(action: prompter.restart) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 13))
            .help("Restart from beginning")

            if prompter.isPlaying {
                Button(action: prompter.stop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.9))
                        .frame(width: 26, height: 26)
                        .background(.red.opacity(0.16), in: Circle())
                }
                .buttonStyle(NotchButtonStyle(cornerRadius: 13))
                .help("Stop")
            }

            // Live Mic Voice Activity Meter (isolated ObservableObject so word flow never reflows)
            if prompter.settings.trackingMode != .steadyScroll && prompter.isPlaying && !prompter.isPaused {
                TeleprompterMicMeterView(
                    meter: prompter.audioMeter,
                    tooltip: prompter.voiceStatusMessage ?? "Listening"
                )
            }

            Spacer(minLength: 4)

            // WPM adjuster (used for Steady Scroll & Voice Pace)
            if prompter.settings.trackingMode != .voiceTrack {
                HStack(spacing: 4) {
                    Button {
                        prompter.settings.wordsPerMinute = max(TeleprompterSettings.wpmRange.lowerBound, prompter.settings.wordsPerMinute - 10)
                    } label: {
                        Image(systemName: "minus").font(.system(size: 9, weight: .bold))
                            .frame(width: 18, height: 22)
                    }
                    Text("\(Int(prompter.settings.wordsPerMinute)) wpm")
                        .font(.system(size: 10, weight: .medium)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.72))
                    Button {
                        prompter.settings.wordsPerMinute = min(TeleprompterSettings.wpmRange.upperBound, prompter.settings.wordsPerMinute + 10)
                    } label: {
                        Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                            .frame(width: 18, height: 22)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .background(.white.opacity(0.06), in: Capsule())
            } else if let status = prompter.voiceStatusMessage {
                Text(status)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Text("\(Int((prompter.progress * 100).rounded()))%")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.6))
                .frame(minWidth: 30, alignment: .trailing)
        }
        .frame(height: 28)
    }

    // MARK: - Inline Script Editor

    private var editorBody: some View {
        VStack(spacing: 6) {
            TextField("Script title", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            TextEditor(text: $draftBody)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Lightweight mic-level view observing only `TeleprompterAudioMeter` so audio
/// meter ticks never trigger full teleprompter word-flow layout passes.
private struct TeleprompterMicMeterView: View {
    @ObservedObject var meter: TeleprompterAudioMeter
    let tooltip: String

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(meter.isVoiceActive ? Color.green : Color.white.opacity(0.3))
                .frame(width: 5.5, height: 5.5)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(meter.isVoiceActive ? Color.cyan : Color.white.opacity(0.45))
                        .frame(width: max(3, geo.size.width * meter.micLevel))
                }
            }
            .frame(width: 36, height: 4)
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(.white.opacity(0.06), in: Capsule())
        .help(tooltip)
    }
}

/// Compact wrapping flow layout for interactive word-by-word highlighting.
private struct TeleprompterWordFlow: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 400
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let sz = subview.sizeThatFits(.unspecified)
            if x + sz.width > maxWidth && x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += sz.width + spacing
            lineHeight = max(lineHeight, sz.height)
        }
        return CGSize(width: maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let sz = subview.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            lineHeight = max(lineHeight, sz.height)
        }
    }
}

// MARK: - Live Activity Strips (when collapsed while prompting)

struct NotchTeleprompterStrip: View {
    @ObservedObject var service: NotchService
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var prompter = NotchTeleprompterService.shared

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
        let pct = "\(Int((prompter.progress * 100).rounded()))%"
        HStack(spacing: 0) {
            Group {
                if geometry.compactActivityWingWidth >= 28 {
                    Image(systemName: prompter.isPaused ? "pause.circle.fill" : prompter.settings.trackingMode.symbol)
                        .font(.system(size: iconSize * 0.9, weight: .medium))
                        .foregroundStyle(prompter.isPaused ? Color.orange : Color.cyan)
                }
            }
            .padding(.leading, iconInset)
            .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight, alignment: .leading)

            Color.clear.frame(width: geometry.compactActivityCameraGap)

            Group {
                if geometry.compactActivityWingWidth >= 42 {
                    Text(pct)
                        .font(.system(size: textSize, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Color.cyan)
                        .lineLimit(1)
                }
            }
            .padding(.trailing, textInset)
            .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight, alignment: .trailing)
        }
        .frame(height: geometry.compactActivityContentHeight)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
    }
}

struct NotchCapsuleTeleprompterStrip: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var prompter = NotchTeleprompterService.shared

    var body: some View {
        let geometry = displayGeometry ?? service.geometry
        let side = NotchCapsuleLayout.side(geometry)
        let pct = "\(Int((prompter.progress * 100).rounded()))%"
        HStack(spacing: NotchCapsuleLayout.spacing) {
            Image(systemName: prompter.isPaused ? "pause.circle.fill" : prompter.settings.trackingMode.symbol)
                .font(.system(size: NotchCapsuleLayout.symbolSize, weight: .medium))
                .foregroundStyle(prompter.isPaused ? .orange : .cyan)
                .frame(width: NotchCapsuleLayout.symbolWidth)
            Text(pct)
                .font(Font(NotchCapsuleLayout.readingFont as CTFont))
                .monospacedDigit()
                .foregroundStyle(.cyan)
        }
        .padding(.horizontal, side + NotchCapsuleLayout.endPadding)
        .frame(width: size.width, height: geometry.stripHeight)
        .foregroundStyle(.white)
    }
}
