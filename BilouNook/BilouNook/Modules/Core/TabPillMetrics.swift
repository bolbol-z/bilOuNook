import AppKit

/// Single source of truth for the top-band pills. The renderer
/// (`ModuleShellView.tabButton`) and the measured pill width both read these
/// values, so a pill can never be narrower than its own content.
enum TabPillMetrics {
    static let height: CGFloat = 20
    static let horizontalPadding: CGFloat = 6
    /// The rendered icon box is exactly this size, width and height.
    static let iconSize: CGFloat = 12
    static let iconGap: CGFloat = 4
    static let labelSize: CGFloat = 10.5
    static let spacing: CGFloat = 6

    /// The font the label is rendered with and measured with.
    static let labelFont = NSFont.systemFont(ofSize: labelSize, weight: .semibold)

    static func labelWidth(forTitle title: String) -> CGFloat {
        (title as NSString).size(withAttributes: [.font: labelFont]).width
    }

    /// Total pill width: padding + icon + gap + label + padding.
    ///
    /// The label is not rounded up: at 420 points the two labeled pills have
    /// 112 points of clear flank before the notch (`121 - 9`), and "Nook" +
    /// "Tray" measure 111.98. Rounding either label up pushes the group past
    /// the flank and drops the layout into the icon fallback.
    static func width(title: String) -> CGFloat {
        labelWidth(forTitle: title) + horizontalPadding * 2 + iconSize + iconGap
    }

    /// The width left for the label text inside the pill.
    static func availableLabelWidth(title: String) -> CGFloat {
        width(title: title) - horizontalPadding * 2 - iconSize - iconGap
    }
}
