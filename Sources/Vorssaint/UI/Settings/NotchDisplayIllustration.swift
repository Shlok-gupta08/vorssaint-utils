// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A schematic screen preview reflects the saved shape and inclusion policy.
struct NotchDisplayIllustration: View {
    let physical: Bool
    let silhouette: NotchSilhouette
    let enabled: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [.indigo.opacity(0.7), .blue.opacity(0.35), .purple.opacity(0.6)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.14))
                    .frame(width: 76, height: 46).offset(x: -22, y: 32)
                if enabled {
                    if physical || silhouette == .notch {
                        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 8,
                                               bottomTrailingRadius: 8, topTrailingRadius: 0)
                            .fill(.black).frame(width: physical ? 58 : 48, height: 14)
                    } else {
                        Capsule().fill(.black).frame(width: 44, height: 12).padding(.top, 6)
                    }
                }
            }
            .frame(width: 196, height: 108)
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.3), lineWidth: 3) }
            RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.4)).frame(width: physical ? 212 : 36, height: 5)
            if !physical { Capsule().fill(.secondary.opacity(0.4)).frame(width: 68, height: 4) }
        }
        .frame(maxWidth: .infinity)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(physical ? "Display with physical notch" : silhouette == .capsule ? "Display with pill island" : "Display with simulated notch")
    }
}
