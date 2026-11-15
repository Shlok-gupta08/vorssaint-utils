// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchShortcutsGlyph: View {
    var side: CGFloat = 18
    var body: some View {
        Image(nsImage: NotchShortcutsService.shared.icon)
            .resizable().aspectRatio(contentMode: .fit).frame(width: side, height: side)
    }
}

struct NotchShortcutsStrip: View {
    let geometry: NotchGeometry
    let size: CGSize
    @ObservedObject private var shortcuts = NotchShortcutsService.shared

    var body: some View {
        if let session = shortcuts.primary {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let wing = max(0, (size.width - geometry.cameraWidth) / 2)
                HStack(spacing: 0) {
                    // Left side: icon only. On physical notch the wing is narrow so
                    // the name is omitted; on virtual notch / floating pill it shows.
                    HStack(spacing: 6) {
                        NotchShortcutsGlyph()
                        if !geometry.isNotched {
                            Text("Shortcuts").font(.system(size: 11, weight: .medium))
                                .lineLimit(1).fixedSize()
                        }
                    }
                    .padding(.leading, geometry.isNotched ? 12 : 0)
                    .frame(width: geometry.isNotched ? wing : nil, alignment: .leading)
                    if geometry.isNotched { Color.clear.frame(width: geometry.cameraWidth) }
                    else { Spacer(minLength: 12) }
                    Text(session.elapsed(at: context.date))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .lineLimit(1).fixedSize()
                        .padding(.trailing, geometry.isNotched ? 12 : 0)
                        .frame(width: geometry.isNotched ? wing : nil, alignment: .trailing)
                }
                .padding(.horizontal, geometry.isNotched ? 0 : NotchCapsuleLayout.side(geometry) + 10)
                .frame(width: size.width, height: geometry.stripHeight)
                .foregroundStyle(.white)
                .onChange(of: session.elapsed(at: context.date).count) { _, _ in
                    NotchService.shared.refreshPresentation()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Shortcuts running")
        }
    }
}

struct NotchShortcutsPanel: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var shortcuts = NotchShortcutsService.shared
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                NotchShortcutsGlyph(side: 22)
                Text("Shortcuts").font(.system(size: 13, weight: .semibold))
                Spacer()
                NotchIconButton(symbol: "chevron.down", title: "Collapse Shortcuts") { service.collapse() }
            }
            if let session = shortcuts.primary {
                Text("Shortcuts running")
                    .font(.system(size: 17, weight: .semibold))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(session.elapsed(at: context.date))
                        .font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
                }.help("Elapsed time since the earliest running shortcut started")
            } else {
                Text("Shortcut finished").font(.system(size: 17, weight: .semibold))
            }
            Button("Open Shortcuts") { shortcuts.openApp() }.buttonStyle(.bordered)
        }
        .padding(.horizontal, 18)
        .padding(.top, service.geometry.safeContentTop + 12)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
    }
}
