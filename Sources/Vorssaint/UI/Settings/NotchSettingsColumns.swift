// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Settings groups share the available width. Each group stays intact and the
/// source order stays intact while shorter columns accept the next group.
struct NotchSettingsColumns: Layout {
    var minimumWidth: CGFloat = 460
    var maximumColumns: Int = 3
    static let gap: CGFloat = 18
    static func columnCount(width: CGFloat, items: Int, minimumWidth: CGFloat = 460, maximumColumns: Int = 3) -> Int {
        let available = width.isFinite ? max(0, width) : 640
        return min(max(1, items), max(1, min(maximumColumns, Int((available + gap) / (minimumWidth + gap)))))
    }
    private func arrangement(width proposedWidth: CGFloat, subviews: Subviews) -> (CGSize, [CGRect]) {
        let width = proposedWidth.isFinite ? max(0, proposedWidth) : 640
        let columns = Self.columnCount(width: width, items: subviews.count, minimumWidth: minimumWidth, maximumColumns: maximumColumns)
        let cellWidth = max(0, (width - CGFloat(columns - 1) * Self.gap) / CGFloat(columns))
        var frames: [CGRect] = []
        var bottoms = Array(repeating: CGFloat.zero, count: columns)
        for view in subviews {
            let column = bottoms.indices.min { bottoms[$0] < bottoms[$1] } ?? 0
            let height = view.sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height
            frames.append(CGRect(x: CGFloat(column) * (cellWidth + Self.gap), y: bottoms[column], width: cellWidth, height: height))
            bottoms[column] += height + Self.gap
        }
        return (CGSize(width: width, height: max(0, (bottoms.max() ?? 0) - Self.gap)), frames)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width ?? 640, subviews: subviews).0
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrangement(width: bounds.width, subviews: subviews).1
        for (view, frame) in zip(subviews, frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                       proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }
}
