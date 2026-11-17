import CoreGraphics

enum CalendarWidgetMetrics {
    static let width: CGFloat = 224
    static let height: CGFloat = 75
    static let size = CGSize(width: width, height: height)

    static let leftPadding: CGFloat = 8
    static let columnWidth: CGFloat = 24
    static let columnSpacing: CGFloat = 0
    static let stripX: CGFloat = 44
    static let stripY: CGFloat = 0
    static let stripHeight: CGFloat = 30

    /// The strip container spans the whole widget so that the two partial
    /// neighbours (x = 20 and x = 212) are drawn without any container offset.
    /// Placement is always expressed in widget coordinates; nothing subtracts
    /// or adds a container origin.
    static let stripFrame = CGRect(x: 0, y: stripY, width: width, height: stripHeight)

    static let monthFontSize: CGFloat = 20
    static let monthLabelCenterY: CGFloat = 13.5
    static let monthLabelFrame = CGRect(x: leftPadding, y: 0, width: 36, height: 27)

    static let headerFontSize: CGFloat = 8
    static let numberFontSize: CGFloat = 11
    static let selectedNumberFontSize: CGFloat = 17
    static let headerCenterY: CGFloat = 5
    static let numberCenterY: CGFloat = 16
    static let selectedNumberCenterY: CGFloat = 18.5
    static let headerHeight: CGFloat = 8
    static let numberHeight: CGFloat = 12
    static let selectedNumberHeight: CGFloat = 18

    static let columnFrames: [CGRect] = (0..<7).map { index in
        CGRect(
            x: stripX + CGFloat(index) * (columnWidth + columnSpacing),
            y: stripY,
            width: columnWidth,
            height: stripHeight
        )
    }

    static let headerFrame = CGRect(x: 0, y: headerCenterY - headerHeight / 2, width: columnWidth, height: headerHeight)
    static let numberFrame = CGRect(x: 0, y: numberCenterY - numberHeight / 2, width: columnWidth, height: numberHeight)
    static let selectedNumberFrame = CGRect(
        x: 0,
        y: selectedNumberCenterY - selectedNumberHeight / 2,
        width: columnWidth,
        height: selectedNumberHeight
    )

    static let previousPartialFrame = CGRect(x: 20, y: stripY, width: columnWidth, height: stripHeight)

    /// The next partial neighbour is a full column centred exactly on the right
    /// edge of the widget (centre x = 224), so only its left half is visible.
    /// The widget clips the part that falls outside.
    static let nextPartialColumnFrame = CGRect(
        x: stripX + 7 * columnWidth,
        y: stripY,
        width: columnWidth,
        height: stripHeight
    )

    /// The visible part of the next partial neighbour (x 212...224).
    static let nextPartialFrame = CGRect(
        x: nextPartialColumnFrame.minX,
        y: stripY,
        width: max(0, width - nextPartialColumnFrame.minX),
        height: stripHeight
    )

    /// Every drawn strip column, in drawing order: partial, 7 main columns, partial.
    static let stripColumnFrames: [CGRect] = [previousPartialFrame] + columnFrames + [nextPartialColumnFrame]

    /// Edge fade of the strip, in widget coordinates. 0 outside the partially
    /// visible neighbours, 1 across all seven main columns, so main columns are
    /// never dimmed.
    static func fadeAlpha(atX x: CGFloat) -> Double {
        let leftOuter = previousPartialFrame.minX
        let leftInner = columnFrames[0].minX
        let rightInner = nextPartialFrame.minX
        let rightOuter = width
        if x <= leftOuter || x >= rightOuter { return 0 }
        if x < leftInner {
            return Double((x - leftOuter) / (leftInner - leftOuter))
        }
        if x > rightInner {
            return Double((rightOuter - x) / (rightOuter - rightInner))
        }
        return 1
    }

    /// One scroll step moves the selection by one day, so the strip slides by
    /// exactly one column width and then re-centres on the selection.
    static func stripSlideOffset(steps: Int) -> CGFloat {
        -CGFloat(steps) * columnWidth
    }


    static let eventsArea = CGRect(x: leftPadding, y: 36, width: width - 2 * leftPadding, height: 36)
    static let eventRowHeight: CGFloat = 12
    static let eventRowFrames = [
        CGRect(x: eventsArea.minX, y: eventsArea.minY, width: eventsArea.width, height: eventRowHeight),
        CGRect(x: eventsArea.minX, y: eventsArea.minY + eventRowHeight, width: eventsArea.width, height: eventRowHeight),
    ]
    static let moreFrame = CGRect(x: eventsArea.minX + 7, y: 60, width: eventsArea.width - 7, height: 9)
    static let colorBarWidth: CGFloat = 3
    static let colorBarHeight: CGFloat = 10
    static let eventTitleX: CGFloat = eventsArea.minX + 7
    static let eventTitleWidth: CGFloat = 134
    static let eventTimeX: CGFloat = 151
    static let eventTimeWidth: CGFloat = 65

    static let eventTitleFontSize: CGFloat = 10
    static let eventTimeFontSize: CGFloat = 9
    static let moreFontSize: CGFloat = 9

    static let emptyIconCenter = CGPoint(x: width / 2, y: 47.5)
    static let emptyTextCenterY: CGFloat = 60
    static let emptyTextFontSize: CGFloat = 9.5

    static let deniedTextCenterY: CGFloat = 44
    static let deniedTextFontSize: CGFloat = 9.5
    static let settingsButtonFrame = CGRect(x: (width - 78) / 2, y: 51, width: 78, height: 18)
    static let settingsButtonFontSize: CGFloat = 9
    static let settingsURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"

    static let headerOpacity: Double = 0.4
    static let numberOpacity: Double = 0.55
    static let weekendRed = CGColor(red: 0.84, green: 0.38, blue: 0.38, alpha: 1)
    static let weekendOpacity: Double = 0.75
    static let selectedHeaderOpacity: Double = 0.9
    static let eventTitleOpacity: Double = 0.9
    static let eventTimeOpacity: Double = 0.5
    static let moreOpacity: Double = 0.45
    static let emptyIconOpacity: Double = 0.45
    static let emptyTextOpacity: Double = 0.55

    static let eventRowCount = 2
    static let scrollStepPoints: CGFloat = 12
}
