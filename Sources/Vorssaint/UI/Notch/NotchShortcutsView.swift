// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchShortcutsGlyph: View {
    var side: CGFloat = 18
    var identity: NotchShortcutIdentity? = nil
    @ObservedObject private var shortcuts = NotchShortcutsService.shared

    private var activeIdentity: NotchShortcutIdentity? {
        identity ?? shortcuts.primary?.identity
    }

    var body: some View {
        if let activeIdentity, let symbol = activeIdentity.symbol {
            let tint = activeIdentity.color ?? Color(red: 0.28, green: 0.56, blue: 0.98)
            ZStack {
                RoundedRectangle(cornerRadius: max(4, side * 0.28), style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.95), tint.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: symbol)
                    .font(.system(size: max(8, side * 0.54), weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: side, height: side, alignment: .center)
            .help(activeIdentity.name)
        } else {
            Image(nsImage: shortcuts.icon)
                .resizable().aspectRatio(contentMode: .fit)
                .frame(width: side, height: side, alignment: .center)
                .help("Shortcuts")
        }
    }
}

struct NotchShortcutsStrip: View {
    let geometry: NotchGeometry
    let size: CGSize
    @ObservedObject private var shortcuts = NotchShortcutsService.shared

    private var iconSize: CGFloat { NotchTimerSupport.stripIconSize(height: geometry.compactActivityContentHeight) }
    private var textSize: CGFloat { NotchTimerSupport.stripTextSize(height: geometry.compactActivityContentHeight) }
    private var iconInset: CGFloat {
        guard !geometry.compactActivityUsesFooter else { return 0 }
        return geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize * 0.28)
    }
    private var textInset: CGFloat {
        guard !geometry.compactActivityUsesFooter else { return 0 }
        return geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0)
    }

    var body: some View {
        if let session = shortcuts.primary {
            let title = session.identity?.name ?? "Shortcuts"
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if geometry.isNotched {
                    HStack(spacing: 0) {
                        Group {
                            if geometry.compactActivityWingWidth >= 28 {
                                NotchShortcutsGlyph(side: iconSize, identity: session.identity)
                            }
                        }
                        .padding(.leading, iconInset)
                        .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight, alignment: .leading)

                        Color.clear.frame(width: geometry.compactActivityCameraGap)

                        Group {
                            if geometry.compactActivityWingWidth >= 42 {
                                Text(session.elapsed(at: context.date))
                                    .font(.system(size: textSize, weight: .semibold)).monospacedDigit()
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                        .padding(.trailing, textInset)
                        .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight, alignment: .trailing)
                    }
                    .frame(height: geometry.compactActivityContentHeight)
                    .padding(.horizontal, geometry.compactActivityHorizontalPadding)
                    .padding(.top, geometry.compactActivityTopPadding)
                    .foregroundStyle(.white)
                    .onChange(of: session.elapsed(at: context.date).count) { _, _ in
                        NotchService.shared.refreshPresentation()
                    }
                } else {
                    // Equal end columns keep the label on the surface's center,
                    // even as the elapsed reading gains digits.
                    let endWidth = max(24, NotchCapsuleLayout.width(
                        session.elapsed(at: context.date), font: NotchCapsuleLayout.readingFont))
                    HStack(spacing: 8) {
                        NotchShortcutsGlyph(identity: session.identity)
                            .frame(width: endWidth, alignment: .leading)
                        Text(title)
                            .font(Font(NotchCapsuleLayout.titleFont as CTFont))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .center)
                        elapsed(session, at: context.date)
                            .frame(width: endWidth, alignment: .trailing)
                    }
                    .padding(.horizontal, NotchCapsuleLayout.side(geometry) + NotchCapsuleLayout.endPadding + 4)
                    .frame(width: size.width, height: geometry.stripHeight)
                    .foregroundStyle(.white)
                    .onChange(of: session.elapsed(at: context.date).count) { _, _ in
                        NotchService.shared.refreshPresentation()
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title) running")
        }
    }
    private func elapsed(_ session: NotchShortcutSession, at date: Date) -> some View {
        Text(session.elapsed(at: date))
            .font(Font(NotchCapsuleLayout.readingFont as CTFont))
            .monospacedDigit()
            .lineLimit(1).fixedSize()
    }
}

struct NotchShortcutsPanel: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var shortcuts = NotchShortcutsService.shared
    var body: some View {
        VStack(spacing: 12) {
            if let session = shortcuts.primary {
                HStack(spacing: 10) {
                    NotchShortcutsGlyph(side: 28, identity: session.identity)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.identity?.name ?? "Running shortcut")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        if session.identity != nil {
                            Text("Shortcut running")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    Spacer(minLength: 4)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(session.elapsed(at: context.date))
                            .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    }
                    Button { shortcuts.cancel(session) } label: {
                        Image(systemName: "stop.circle.fill").font(.system(size: 24)).foregroundStyle(.red)
                    }
                    .buttonStyle(.plain).disabled(!shortcuts.canCancel(session))
                    .help(shortcuts.canCancel(session) ? "Stop this shortcut" : "Stop this run using the native Shortcuts indicator")
                    .accessibilityLabel("Stop shortcut")
                }
            } else { Text("Shortcut finished").font(.system(size: 13)) }
        }
        .padding(.horizontal, 18)
        .padding(.top, service.geometry.safeContentTop + 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .contextMenu {
            Button("Controls") { service.select(.controls) }
            Button("Sections") { service.toggleSections() }
        }
    }
}
