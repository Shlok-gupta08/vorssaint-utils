// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct NotchCallStrip: View {
    let geometry: NotchGeometry
    let size: CGSize
    var minimal = false
    var snapshot: NotchCallSession? = nil
    @ObservedObject private var calls = NotchCallService.shared

    var body: some View {
        if let call = snapshot ?? calls.primary {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: call.phase == .ringing ? "phone.connection.fill" : "phone.fill")
                            .font(.system(size: 12, weight: .semibold))
                        if !minimal { Text(call.appName).font(.system(size: 11, weight: .medium)).lineLimit(1) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if geometry.isNotched { Color.clear.frame(width: geometry.cameraWidth) }
                    HStack(spacing: 5) {
                        if call.muted { Image(systemName: "mic.slash.fill").font(.system(size: 10)) }
                        Text(call.elapsed(at: context.date))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .lineLimit(1).fixedSize()
                    }
                    .frame(maxWidth: geometry.isNotched ? .infinity : nil, alignment: .trailing)
                }
                .padding(.horizontal, geometry.floats ? NotchCapsuleLayout.side(geometry) + 10 : 12)
                .frame(width: size.width, height: geometry.stripHeight)
                .foregroundStyle(call.phase == .held ? Color.orange : Color.green)
                .onChange(of: call.elapsed(at: context.date).count) { _, _ in NotchService.shared.refreshPresentation() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(call.appName), \(call.phase.title)")
        }
    }
}

struct NotchCallPanel: View {
    @ObservedObject var service: NotchService
    var snapshot: NotchCallSession? = nil
    @ObservedObject private var calls = NotchCallService.shared

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label("Call", systemImage: "phone.fill").font(.system(size: 13, weight: .semibold))
                Spacer()
                NotchIconButton(symbol: "chevron.down", title: "Collapse call") { service.collapse() }
            }
            if let call = snapshot ?? calls.primary {
                Text(call.appName).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(call.elapsed(at: context.date))
                        .font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.green)
                }
                .help("Elapsed time since this call was detected as connected")
                Text(call.muted ? "Microphone muted" : call.phase.title)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    if call.canAnswer {
                        Button { calls.perform(.answer, session: call) } label: { Label("Answer", systemImage: "phone.fill") }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                    }
                    if call.canMute {
                        Button { calls.perform(.mute, session: call) } label: {
                            Label(call.muted ? "Unmute" : "Mute", systemImage: call.muted ? "mic.slash.fill" : "mic.fill")
                        }
                    }
                    if call.canEnd {
                        Button(role: .destructive) { calls.perform(.end, session: call) } label: {
                            Label(call.phase == .ringing ? "Decline" : "End", systemImage: "phone.down.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .buttonStyle(.bordered)
                Button("Return to \(call.appName)") { calls.open(call) }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(.green)
            } else {
                Image(systemName: "phone.down.fill").font(.system(size: 26)).foregroundStyle(.secondary)
                Text("Call ended").font(.system(size: 15, weight: .medium))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
    }
}
