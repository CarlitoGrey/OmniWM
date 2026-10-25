// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

struct ShellDesktopLaneLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = proposal.width ?? sizes.reduce(0) { $0 + $1.width + spacing }
        let frames = Self.frames(sizes: sizes, width: width, spacing: spacing)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let frames = Self.frames(
            sizes: subviews.map { $0.sizeThatFits(.unspecified) },
            width: bounds.width,
            spacing: spacing
        )
        for (view, frame) in zip(subviews, frames) {
            view.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    static func frames(sizes: [CGSize], width: CGFloat, spacing: CGFloat = 6) -> [CGRect] {
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        return sizes.map { size in
            let size = CGSize(width: min(max(0, width), size.width), height: size.height)
            if origin.x > 0, origin.x + size.width > width {
                origin = CGPoint(x: 0, y: origin.y + rowHeight + spacing)
                rowHeight = 0
            }
            let frame = CGRect(origin: origin, size: size)
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            return frame
        }
    }

    static func insertion(at point: CGPoint, frames: [CGRect]) -> Int {
        for (index, frame) in frames.enumerated() {
            if point.y < frame.minY || (point.y <= frame.maxY && point.x < frame.midX) { return index }
        }
        return frames.count
    }
}
