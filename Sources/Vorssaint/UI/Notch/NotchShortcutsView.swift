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
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        NotchShortcutsGlyph()
                        Text("Shortcuts").font(.system(size: 11, weight: .medium)).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if geometry.isNotched { Color.clear.frame(width: geometry.cameraWidth) }
                    HStack(spacing: 5) {
                        if shortcuts.executionCount > 1 {
                            Text("×\(shortcuts.executionCount)").font(.system(size: 10))
                        }
                        Text(session.elapsed(at: context.date))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced)).fixedSize()
                    }.frame(maxWidth: geometry.isNotched ? .infinity : nil, alignment: .trailing)
                }
                .padding(.horizontal, geometry.floats ? NotchCapsuleLayout.side(geometry) + 10 : 12)
                .frame(width: size.width, height: geometry.stripHeight)
                .foregroundStyle(.white)
                .onChange(of: session.elapsed(at: context.date).count) { _, _ in
                    NotchService.shared.refreshPresentation()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(shortcuts.executionCount) running shortcuts")
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
                Text(shortcuts.executionCount == 1 ? "Running shortcut" : "\(shortcuts.executionCount) running shortcuts")
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
