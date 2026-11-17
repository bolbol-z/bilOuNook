import CoreGraphics

enum NookLayout {
    static let minimumPageWidth: CGFloat = 300
    static let contentTopOffset: CGFloat = 2
    static let rowHeight: CGFloat = 75
    static let bottomPadding: CGFloat = 9
    static let dividerWidth: CGFloat = 1

    static func pageWidth(widgets: [any NookWidget]) -> CGFloat {
        pageWidth(widths: widgets.filter(\.isEnabled).map(\.preferredWidth))
    }

    static func pageWidth(widths: [CGFloat]) -> CGFloat {
        let dividers = CGFloat(max(0, widths.count - 1)) * dividerWidth
        return max(minimumPageWidth, widths.reduce(0, +) + dividers)
    }

    static func preferredHeight(notchHeight: CGFloat) -> CGFloat {
        notchHeight + contentTopOffset + rowHeight + bottomPadding
    }

    static func preferredSize(widgets: [any NookWidget], notchHeight: CGFloat) -> CGSize {
        CGSize(
            width: pageWidth(widgets: widgets),
            height: preferredHeight(notchHeight: notchHeight)
        )
    }

    static func rowTop(notchHeight: CGFloat) -> CGFloat {
        notchHeight + contentTopOffset
    }

    static func contentFrame(pageWidth: CGFloat, notchHeight: CGFloat) -> CGRect {
        CGRect(
            x: 0,
            y: rowTop(notchHeight: notchHeight),
            width: pageWidth,
            height: rowHeight
        )
    }

    static func widgetFrames(widths: [CGFloat]) -> [CGRect] {
        var x: CGFloat = 0
        return widths.map { width in
            defer { x += width + dividerWidth }
            return CGRect(x: x, y: 0, width: width, height: rowHeight)
        }
    }

    static func dividerFrames(widths: [CGFloat]) -> [CGRect] {
        guard widths.count > 1 else { return [] }
        var x: CGFloat = 0
        var frames: [CGRect] = []
        for index in widths.indices {
            x += widths[index]
            if index < widths.count - 1 {
                frames.append(CGRect(x: x, y: 0, width: dividerWidth, height: rowHeight))
                x += dividerWidth
            }
        }
        return frames
    }
}

extension NookLayout {
    /// Width of the docked two-widget Nook canvas (media + divider + calendar).
    /// The Files tab must match it so switching tabs never resizes the panel.
    static let nookCanvasWidth: CGFloat = 420
}
