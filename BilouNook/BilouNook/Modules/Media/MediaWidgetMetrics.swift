import CoreGraphics

enum MediaWidgetMetrics {
    static let width: CGFloat = 195
    static let height: CGFloat = 75
    static let size = CGSize(width: width, height: height)

    static let leftPadding: CGFloat = 9
    static let rightPadding: CGFloat = 8
    static let artworkSize: CGFloat = 75
    static let artworkCornerRadius: CGFloat = 11
    static let artworkFrame = CGRect(x: leftPadding, y: 0, width: artworkSize, height: artworkSize)

    static let badgeSize: CGFloat = 20
    static let badgeCornerRadius: CGFloat = 5
    static let badgeOverhang: CGFloat = 2.5
    static let badgeFrame = CGRect(
        x: artworkFrame.maxX + badgeOverhang - badgeSize,
        y: artworkFrame.maxY + badgeOverhang - badgeSize,
        width: badgeSize,
        height: badgeSize
    )

    static let textColumnX: CGFloat = 93
    static let textColumnMaxWidth: CGFloat = 102
    static let textColumnWidth: CGFloat = min(textColumnMaxWidth, width - textColumnX - rightPadding)
    static let textColumnFrame = CGRect(
        x: textColumnX,
        y: 0,
        width: textColumnWidth,
        height: height
    )

    static let titleCenterY: CGFloat = 15
    static let albumCenterY: CGFloat = 28
    static let artistCenterY: CGFloat = 40.5
    static let controlsCenterY: CGFloat = 57
    static let titleHeight: CGFloat = 14
    static let albumHeight: CGFloat = 12
    static let artistHeight: CGFloat = 12
    static let controlsHeight: CGFloat = 18

    static let titleFrame = rowFrame(centerY: titleCenterY, height: titleHeight)
    static let albumFrame = rowFrame(centerY: albumCenterY, height: albumHeight)
    static let artistFrame = rowFrame(centerY: artistCenterY, height: artistHeight)
    static let controlsFrame = rowFrame(centerY: controlsCenterY, height: controlsHeight)

    static let titleFontSize: CGFloat = 11
    static let albumFontSize: CGFloat = 10
    static let artistFontSize: CGFloat = 9
    static let titleOpacity: Double = 1
    static let albumOpacity: Double = 0.62
    static let artistOpacity: Double = 0.45

    static let controlSymbolSize: CGFloat = 9
    static let controlHitSize = CGSize(width: 20, height: 18)
    static let controlSpacing: CGFloat = 20
    static let firstControlCenterX: CGFloat = textColumnX + 10
    static let controlFrames: [CGRect] = (0..<3).map { index in
        CGRect(
            x: firstControlCenterX + CGFloat(index) * controlSpacing - controlHitSize.width / 2,
            y: controlsCenterY - controlHitSize.height / 2,
            width: controlHitSize.width,
            height: controlHitSize.height
        )
    }

    static let scrubberTrackFrame = CGRect(x: textColumnX, y: 69, width: textColumnWidth, height: 3)
    static let scrubberHitFrame = CGRect(x: textColumnX, y: 63, width: textColumnWidth, height: 12)
    static let scrubberHitHeight: CGFloat = 12
    static let scrubberTrackHeight: CGFloat = 3

    static let emptyTitle = "Not Playing"
    static let emptyMessage = "Play something to see it here"

    private static func rowFrame(centerY: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: textColumnX,
            y: centerY - height / 2,
            width: textColumnWidth,
            height: height
        )
    }
}
