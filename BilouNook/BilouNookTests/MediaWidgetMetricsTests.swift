import CoreGraphics
import XCTest

final class MediaWidgetMetricsTests: XCTestCase {
    func testWidgetAndArtworkFramesMatchSpec() {
        XCTAssertEqual(MediaWidgetMetrics.size, CGSize(width: 195, height: 75))
        XCTAssertEqual(MediaWidgetMetrics.artworkFrame, CGRect(x: 9, y: 0, width: 75, height: 75))
        XCTAssertEqual(MediaWidgetMetrics.artworkCornerRadius, 11)
    }

    func testBadgeOverhangsTheArtworkCornerByTwoAndAHalfPoints() {
        XCTAssertEqual(MediaWidgetMetrics.badgeFrame, CGRect(x: 66.5, y: 57.5, width: 20, height: 20))
        XCTAssertEqual(MediaWidgetMetrics.badgeCornerRadius, 5)
        XCTAssertEqual(MediaWidgetMetrics.badgeFrame.maxX, MediaWidgetMetrics.artworkFrame.maxX + 2.5, accuracy: 0.0001)
        XCTAssertEqual(MediaWidgetMetrics.badgeFrame.maxY, MediaWidgetMetrics.artworkFrame.maxY + 2.5, accuracy: 0.0001)
    }

    func testTextColumnAndRowCentersMatchSpec() {
        XCTAssertEqual(MediaWidgetMetrics.textColumnFrame, CGRect(x: 93, y: 0, width: 94, height: 75))
        XCTAssertEqual(MediaWidgetMetrics.titleFrame, CGRect(x: 93, y: 8, width: 94, height: 14))
        XCTAssertEqual(MediaWidgetMetrics.albumFrame, CGRect(x: 93, y: 22, width: 94, height: 12))
        XCTAssertEqual(MediaWidgetMetrics.artistFrame, CGRect(x: 93, y: 34.5, width: 94, height: 12))
        XCTAssertEqual(MediaWidgetMetrics.controlsFrame, CGRect(x: 93, y: 48, width: 94, height: 18))
    }

    func testRowCentersAndFontsMatchSpec() {
        XCTAssertEqual(MediaWidgetMetrics.titleCenterY, 15)
        XCTAssertEqual(MediaWidgetMetrics.albumCenterY, 28)
        XCTAssertEqual(MediaWidgetMetrics.artistCenterY, 40.5)
        XCTAssertEqual(MediaWidgetMetrics.controlsCenterY, 57)
        XCTAssertEqual(MediaWidgetMetrics.titleFontSize, 11)
        XCTAssertEqual(MediaWidgetMetrics.albumFontSize, 10)
        XCTAssertEqual(MediaWidgetMetrics.artistFontSize, 9)
        XCTAssertEqual(MediaWidgetMetrics.albumOpacity, 0.62)
        XCTAssertEqual(MediaWidgetMetrics.artistOpacity, 0.45)
    }

    func testControlFramesMatchSpec() {
        XCTAssertEqual(MediaWidgetMetrics.controlFrames, [
            CGRect(x: 93, y: 48, width: 20, height: 18),
            CGRect(x: 113, y: 48, width: 20, height: 18),
            CGRect(x: 133, y: 48, width: 20, height: 18),
        ])
        XCTAssertEqual(MediaWidgetMetrics.controlSymbolSize, 9)
    }

    func testScrubberFramesMatchSpec() {
        XCTAssertEqual(MediaWidgetMetrics.scrubberTrackFrame, CGRect(x: 93, y: 69, width: 94, height: 3))
        XCTAssertEqual(MediaWidgetMetrics.scrubberHitFrame, CGRect(x: 93, y: 63, width: 94, height: 12))
    }

    func testContentFramesStayInsideTheWidget() {
        let frames = [
            MediaWidgetMetrics.artworkFrame,
            MediaWidgetMetrics.textColumnFrame,
            MediaWidgetMetrics.titleFrame,
            MediaWidgetMetrics.albumFrame,
            MediaWidgetMetrics.artistFrame,
            MediaWidgetMetrics.controlsFrame,
            MediaWidgetMetrics.scrubberTrackFrame,
            MediaWidgetMetrics.scrubberHitFrame,
        ] + MediaWidgetMetrics.controlFrames
        let widget = CGRect(origin: .zero, size: MediaWidgetMetrics.size)
        for frame in frames {
            XCTAssertTrue(widget.contains(frame), "\(frame) escapes \(widget)")
        }
    }

    func testTextColumnDoesNotOverlapArtworkOrBadge() {
        XCTAssertFalse(MediaWidgetMetrics.textColumnFrame.intersects(MediaWidgetMetrics.artworkFrame))
        XCTAssertFalse(MediaWidgetMetrics.textColumnFrame.intersects(MediaWidgetMetrics.badgeFrame))
    }
}
