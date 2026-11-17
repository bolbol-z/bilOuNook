import AppKit
import CoreGraphics
import XCTest

final class CalendarWidgetMetricsTests: XCTestCase {
    func testWidgetMatchesSpec() {
        XCTAssertEqual(CalendarWidgetMetrics.size, CGSize(width: 224, height: 75))
        XCTAssertEqual(CalendarWidgetMetrics.leftPadding, 8)
        XCTAssertEqual(CalendarWidgetMetrics.monthLabelFrame, CGRect(x: 8, y: 0, width: 36, height: 27))
    }

    func testWeekStripColumnsMatchSpec() {
        XCTAssertEqual(CalendarWidgetMetrics.columnWidth, 24)
        XCTAssertEqual(CalendarWidgetMetrics.columnFrames.count, 7)
        XCTAssertEqual(CalendarWidgetMetrics.columnFrames.first, CGRect(x: 44, y: 0, width: 24, height: 30))
        XCTAssertEqual(CalendarWidgetMetrics.columnFrames.last, CGRect(x: 188, y: 0, width: 24, height: 30))
        XCTAssertEqual(CalendarWidgetMetrics.previousPartialFrame, CGRect(x: 20, y: 0, width: 24, height: 30))
        XCTAssertEqual(CalendarWidgetMetrics.nextPartialFrame, CGRect(x: 212, y: 0, width: 12, height: 30))
    }

    func testRowCentresAndFontsMatchSpec() {
        XCTAssertEqual(CalendarWidgetMetrics.monthFontSize, 20)
        XCTAssertEqual(CalendarWidgetMetrics.monthLabelCenterY, 13.5)
        XCTAssertEqual(CalendarWidgetMetrics.headerCenterY, 5)
        XCTAssertEqual(CalendarWidgetMetrics.headerFontSize, 8)
        XCTAssertEqual(CalendarWidgetMetrics.numberCenterY, 16)
        XCTAssertEqual(CalendarWidgetMetrics.numberFontSize, 11)
        XCTAssertEqual(CalendarWidgetMetrics.selectedNumberCenterY, 18.5)
        XCTAssertEqual(CalendarWidgetMetrics.selectedNumberFontSize, 17)
        XCTAssertEqual(CalendarWidgetMetrics.eventsArea, CGRect(x: 8, y: 36, width: 208, height: 36))
        XCTAssertEqual(CalendarWidgetMetrics.emptyIconCenter, CGPoint(x: 112, y: 47.5))
        XCTAssertEqual(CalendarWidgetMetrics.emptyTextCenterY, 60)
    }

    func testEventRowsAndMoreMatchSpec() {
        XCTAssertEqual(CalendarWidgetMetrics.eventRowFrames.count, 2)
        XCTAssertEqual(CalendarWidgetMetrics.eventRowFrames[0], CGRect(x: 8, y: 36, width: 208, height: 12))
        XCTAssertEqual(CalendarWidgetMetrics.eventRowFrames[1], CGRect(x: 8, y: 48, width: 208, height: 12))
        XCTAssertEqual(CalendarWidgetMetrics.moreFrame, CGRect(x: 15, y: 60, width: 201, height: 9))
        XCTAssertEqual(CalendarWidgetMetrics.eventTitleFontSize, 10)
        XCTAssertEqual(CalendarWidgetMetrics.eventTimeFontSize, 9)
        XCTAssertEqual(CalendarWidgetMetrics.moreFontSize, 9)
    }

    func testAllFramesStayInsideWidget() {
        let widget = CGRect(origin: .zero, size: CalendarWidgetMetrics.size)
        let frames = [
            CalendarWidgetMetrics.monthLabelFrame,
            CalendarWidgetMetrics.stripFrame,
            CalendarWidgetMetrics.previousPartialFrame,
            CalendarWidgetMetrics.nextPartialFrame,
            CalendarWidgetMetrics.eventsArea,
            CalendarWidgetMetrics.moreFrame,
            CalendarWidgetMetrics.settingsButtonFrame,
        ] + CalendarWidgetMetrics.columnFrames + CalendarWidgetMetrics.eventRowFrames
        for frame in frames {
            XCTAssertTrue(widget.contains(frame), "\(frame) escapes \(widget)")
        }
    }

    func testSettingsLinkPointsAtCalendarPrivacy() {
        XCTAssertEqual(
            CalendarWidgetMetrics.settingsURLString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        )
    }

    // MARK: - calendar-strip-fix: strip container and clipping guarantees

    func testStripContainerCoversTheWholeWidgetWidth() {
        XCTAssertEqual(
            CalendarWidgetMetrics.stripFrame,
            CGRect(x: 0, y: 0, width: CalendarWidgetMetrics.width, height: CalendarWidgetMetrics.stripHeight)
        )
    }

    func testMainColumnsAndPartialsStayInsideTheWidget() {
        let widget = CGRect(origin: .zero, size: CalendarWidgetMetrics.size)
        for frame in CalendarWidgetMetrics.columnFrames {
            XCTAssertTrue(widget.contains(frame), "\(frame) escapes \(widget)")
            XCTAssertTrue(CalendarWidgetMetrics.stripFrame.contains(frame), "\(frame) escapes the strip container")
        }
        XCTAssertTrue(widget.contains(CalendarWidgetMetrics.previousPartialFrame))
        XCTAssertTrue(widget.contains(CalendarWidgetMetrics.nextPartialFrame))
        XCTAssertEqual(CalendarWidgetMetrics.nextPartialFrame.width, 12)
        XCTAssertEqual(
            CalendarWidgetMetrics.columnFrames[0].minX,
            CalendarWidgetMetrics.previousPartialFrame.maxX,
            "the main columns must continue the previous partial without a gap"
        )
        XCTAssertEqual(
            CalendarWidgetMetrics.columnFrames[6].maxX,
            CalendarWidgetMetrics.nextPartialFrame.minX,
            "the next partial must continue the last main column without a gap"
        )
    }

    func testMainColumnsAreNeverDimmedByTheEdgeFade() {
        for (index, frame) in CalendarWidgetMetrics.columnFrames.enumerated() {
            XCTAssertEqual(CalendarWidgetMetrics.fadeAlpha(atX: frame.minX), 1, "column \(index) left edge")
            XCTAssertEqual(CalendarWidgetMetrics.fadeAlpha(atX: frame.midX), 1, "column \(index) centre")
            XCTAssertEqual(CalendarWidgetMetrics.fadeAlpha(atX: frame.maxX), 1, "column \(index) right edge")
        }
        XCTAssertLessThanOrEqual(
            CalendarWidgetMetrics.fadeAlpha(atX: CalendarWidgetMetrics.monthLabelFrame.midX),
            0.25,
            "the area under the month label stays faint"
        )
    }

    func testPartialNeighboursAreCoveredByTheirMasks() {
        // The widget edges are fully transparent.
        XCTAssertLessThanOrEqual(CalendarWidgetMetrics.fadeAlpha(atX: 0), 0.25)
        XCTAssertLessThanOrEqual(CalendarWidgetMetrics.fadeAlpha(atX: CalendarWidgetMetrics.width), 0.25)
        // The far edge of each partial column is transparent.
        XCTAssertEqual(CalendarWidgetMetrics.fadeAlpha(atX: CalendarWidgetMetrics.previousPartialFrame.minX), 0)
        XCTAssertEqual(CalendarWidgetMetrics.fadeAlpha(atX: CalendarWidgetMetrics.nextPartialFrame.maxX), 0)
        // The inner edge of each partial is fully opaque.
        XCTAssertEqual(CalendarWidgetMetrics.fadeAlpha(atX: CalendarWidgetMetrics.previousPartialFrame.maxX), 1)
        XCTAssertEqual(CalendarWidgetMetrics.fadeAlpha(atX: CalendarWidgetMetrics.nextPartialFrame.minX), 1)

        // A monotone ramp from the outer edge to the inner edge, both sides.
        var previous = 0.0
        for x in stride(from: CalendarWidgetMetrics.previousPartialFrame.minX, to: CalendarWidgetMetrics.previousPartialFrame.maxX, by: 2) {
            let alpha = CalendarWidgetMetrics.fadeAlpha(atX: x)
            XCTAssertGreaterThanOrEqual(alpha, previous, "left fade must rise towards the columns")
            XCTAssertLessThanOrEqual(alpha, 1)
            previous = alpha
        }
        previous = 1
        for x in stride(from: CalendarWidgetMetrics.nextPartialFrame.minX, to: CalendarWidgetMetrics.nextPartialFrame.maxX, by: 2) {
            let alpha = CalendarWidgetMetrics.fadeAlpha(atX: x)
            XCTAssertLessThanOrEqual(alpha, previous, "right fade must fall towards the edge")
            XCTAssertGreaterThanOrEqual(alpha, 0)
            previous = alpha
        }
    }

    func testOneScrollStepIsExactlyOneColumn() {
        XCTAssertEqual(CalendarWidgetMetrics.columnWidth, 24)
        XCTAssertEqual(CalendarWidgetMetrics.stripSlideOffset(steps: 1), -24)
        XCTAssertEqual(CalendarWidgetMetrics.stripSlideOffset(steps: -1), 24)
        XCTAssertEqual(CalendarWidgetMetrics.stripSlideOffset(steps: 0), 0)
        XCTAssertEqual(CalendarWidgetMetrics.stripSlideOffset(steps: 3), -72)
    }

    func testMonthLabelNeverIntersectsAMainColumn() {        for frame in CalendarWidgetMetrics.columnFrames {
            XCTAssertFalse(
                CalendarWidgetMetrics.monthLabelFrame.intersects(frame),
                "month label \(CalendarWidgetMetrics.monthLabelFrame) overlaps \(frame)"
            )
        }
        XCTAssertLessThanOrEqual(
            CalendarWidgetMetrics.monthLabelFrame.maxX,
            CalendarWidgetMetrics.columnFrames[0].minX
        )
    }

    func testEveryColumnTextBoundsLieInsideItsColumnAndTheWidget() {
        let widget = CGRect(origin: .zero, size: CalendarWidgetMetrics.size)
        let headerFont = NSFont.systemFont(ofSize: CalendarWidgetMetrics.headerFontSize, weight: .semibold)
        let numberFont = NSFont.systemFont(ofSize: CalendarWidgetMetrics.numberFontSize, weight: .medium)
        let selectedNumberFont = NSFont.systemFont(ofSize: CalendarWidgetMetrics.selectedNumberFontSize, weight: .semibold)

        var headers: [String] = []
        for weekday in ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN", "LUN", "MAR", "MER", "JEU", "VEN", "SAM", "DIM"] {
            headers.append(weekday)
        }
        var numbers: [String] = []
        for day in 1...31 {
            numbers.append(String(format: "%02d", day))
        }

        for column in CalendarWidgetMetrics.columnFrames {
            for header in headers {
                let width = measure(header, font: headerFont)
                XCTAssertLessThanOrEqual(width, CalendarWidgetMetrics.columnWidth, "\(header) header is wider than a column")
                let frame = CalendarWidgetMetrics.headerFrame.offsetBy(dx: column.minX, dy: 0)
                let textBounds = CGRect(
                    x: column.midX - width / 2,
                    y: frame.minY,
                    width: width,
                    height: frame.height
                )
                XCTAssertTrue(widget.contains(textBounds), "\(header) at \(column) escapes the widget")
            }
            for number in numbers {
                let width = measure(number, font: numberFont)
                let selectedWidth = measure(number, font: selectedNumberFont)
                XCTAssertLessThanOrEqual(width, CalendarWidgetMetrics.columnWidth, "\(number) is wider than a column")
                XCTAssertLessThanOrEqual(selectedWidth, CalendarWidgetMetrics.columnWidth, "selected \(number) is wider than a column")
                let height = max(CalendarWidgetMetrics.numberHeight, CalendarWidgetMetrics.selectedNumberHeight)
                let textBounds = CGRect(
                    x: column.midX - selectedWidth / 2,
                    y: CalendarWidgetMetrics.selectedNumberCenterY - height / 2,
                    width: selectedWidth,
                    height: height
                )
                XCTAssertTrue(widget.contains(textBounds), "\(number) at \(column) escapes the widget")
            }
        }
    }

    private func measure(_ string: String, font: NSFont) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }
}
