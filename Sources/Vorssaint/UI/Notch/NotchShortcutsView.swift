// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchShortcutsGlyph: View {
    var side: CGFloat = 18
    @ObservedObject private var shortcuts = NotchShortcutsService.shared

    var body: some View {
        Group {
            if let icon = shortcuts.currentIcon {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .resizable().aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side, alignment: .center)
        .help(shortcuts.currentIcon == nil ? "Shortcut artwork is unavailable" : (shortcuts.currentShortcutName ?? "Running shortcut"))
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
                    HStack(spacing: 6) {
                        NotchShortcutsGlyph()
                        if !geometry.isNotched, let name = shortcuts.currentShortcutName, !name.isEmpty {
                            Text(name).font(.system(size: 11, weight: .medium))
                                .lineLimit(1).fixedSize()
                        }
                    }
                    .frame(width: geometry.isNotched ? wing : nil, alignment: .center)
                    if geometry.isNotched { Color.clear.frame(width: geometry.cameraWidth) }
                    else { Spacer(minLength: 8) }
                    Text(session.elapsed(at: context.date))
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .lineLimit(1).fixedSize()
                        .frame(width: geometry.isNotched ? wing : nil, alignment: .center)
                }
                .padding(.horizontal, geometry.isNotched ? 0 : NotchCapsuleLayout.side(geometry) + 8)
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
        VStack(spacing: 12) {
            if let session = shortcuts.primary {
                HStack(spacing: 10) {
                    NotchShortcutsGlyph(side: 26)
                    Text(shortcuts.currentShortcutName ?? "Running shortcut")
                        .font(.system(size: 13, weight: .medium)).lineLimit(1)
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
