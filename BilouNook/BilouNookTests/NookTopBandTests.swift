import AppKit
import XCTest

@MainActor
final class NookTopBandTests: XCTestCase {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1470, height: 956)

    private var physicalGeometry: NotchGeometry {
        NotchGeometry(
            screenFrame: screenFrame,
            backingScaleFactor: 2,
            auxLeft: CGRect(x: 0, y: 924, width: 646, height: 32),
            auxRight: CGRect(x: 825, y: 924, width: 645, height: 32),
            safeAreaTop: 32
        )
    }

    private var noNotchGeometry: NotchGeometry {
        NotchGeometry(
            screenFrame: screenFrame,
            backingScaleFactor: 2,
            auxLeft: nil,
            auxRight: nil,
            safeAreaTop: 0
        )
    }

    func testOnePillFramesMatchSpec() {
        let width = TabPillMetrics.width(title: "Nook")
        let layout = ModuleTabLayout(
            pillWidths: [width],
            shapeWidth: 420,
            geometry: physicalGeometry
        )

        XCTAssertFalse(layout.usesIconFallback)
        XCTAssertEqual(layout.pillFrames, [CGRect(x: 9, y: 6, width: width, height: 20)])
        XCTAssertEqual(layout.gearFrame, CGRect(x: 388, y: 6, width: 20, height: 20))
    }

    func testTwoPillFramesMatchSpec() {
        let nook = TabPillMetrics.width(title: "Nook")
        let tray = TabPillMetrics.width(title: "Tray")
        let layout = ModuleTabLayout(
            pillWidths: [nook, tray],
            shapeWidth: 420,
            geometry: physicalGeometry
        )

        XCTAssertFalse(layout.usesIconFallback)
        XCTAssertEqual(layout.pillFrames, [
            CGRect(x: 9, y: 6, width: nook, height: 20),
            CGRect(x: 9 + nook + 6, y: 6, width: tray, height: 20),
        ])
        XCTAssertEqual(layout.gearFrame, CGRect(x: 388, y: 6, width: 20, height: 20))
    }

    func testOverflowFallsBackToIconsWithoutEnteringForbiddenZone() {
        let nook = TabPillMetrics.width(title: "Nook")
        let tray = TabPillMetrics.width(title: "Tray")
        let layout = ModuleTabLayout(
            pillWidths: [nook, tray],
            shapeWidth: 300,
            geometry: physicalGeometry
        )
        let notch = notchRect(inShapeWidth: 300)

        XCTAssertTrue(layout.usesIconFallback)
        XCTAssertEqual(layout.pillFrames.map(\.width), [20, 20])
        XCTAssertEqual(layout.pillFrames.map(\.minX), [9, 35])
        for frame in layout.pillFrames {
            XCTAssertFalse(frame.intersects(notch))
        }
    }

    func testNoNotchUsesTheSameLeftAnchoredTopBand() {
        let width = TabPillMetrics.width(title: "Nook")
        let layout = ModuleTabLayout(
            pillWidths: [width],
            shapeWidth: 420,
            geometry: noNotchGeometry
        )

        XCTAssertEqual(layout.pillFrames, [CGRect(x: 9, y: 6, width: width, height: 20)])
        XCTAssertEqual(layout.gearFrame, CGRect(x: 388, y: 6, width: 20, height: 20))
    }

    func testTopBandNeverIntersectsForbiddenZone() {
        for shapeWidth in [300.0, 420.0] {
            let widths = [TabPillMetrics.width(title: "Nook"), TabPillMetrics.width(title: "Tray")]
            let layout = ModuleTabLayout(
                pillWidths: widths,
                shapeWidth: shapeWidth,
                geometry: physicalGeometry
            )
            let notch = notchRect(inShapeWidth: shapeWidth)
            for frame in layout.pillFrames {
                XCTAssertFalse(frame.intersects(notch), "\(shapeWidth) \(frame)")
            }
        }
    }

    func testPillLeavesRoomForItsLabel() {
        for title in ["Nook", "Tray", "Calendrier", "التقويم"] {
            let attributed = NSAttributedString(
                string: title,
                attributes: [.font: TabPillMetrics.labelFont]
            )
            let measured = attributed.size().width
            let available = TabPillMetrics.availableLabelWidth(title: title)
            XCTAssertLessThanOrEqual(
                measured,
                available,
                "\(title) needs \(measured) but the pill only reserves \(available)"
            )
            XCTAssertGreaterThanOrEqual(
                TabPillMetrics.width(title: title),
                TabPillMetrics.horizontalPadding * 2 + TabPillMetrics.iconSize + TabPillMetrics.iconGap + measured
            )
        }
        // "Nook" is the pill the owner saw truncated: it must still reserve its
        // full measured label plus the 12pt icon, the 4pt gap and both paddings.
        let nook = NSAttributedString(string: "Nook", attributes: [.font: TabPillMetrics.labelFont]).size().width
        let reserved = TabPillMetrics.horizontalPadding * 2 + TabPillMetrics.iconSize + TabPillMetrics.iconGap
        XCTAssertEqual(TabPillMetrics.width(title: "Nook"), nook + reserved, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(TabPillMetrics.width(title: "Nook"), 55)
        XCTAssertEqual(TabPillMetrics.iconSize, 12)
        XCTAssertEqual(TabPillMetrics.height, 20)
        XCTAssertEqual(TabPillMetrics.horizontalPadding, 6)
        XCTAssertEqual(TabPillMetrics.iconGap, 4)
        XCTAssertEqual(TabPillMetrics.labelSize, 10.5)
    }

    func testLabeledPillsStayLeftAlignedAt420EvenInFrench() {
        let widths = [TabPillMetrics.width(title: "Nook"), TabPillMetrics.width(title: "Tray")]
        let layout = ModuleTabLayout(pillWidths: widths, shapeWidth: 420, geometry: physicalGeometry)
        XCTAssertFalse(layout.usesIconFallback)
        XCTAssertEqual(layout.pillFrames.map(\.minX), [9, 9 + widths[0] + TabPillMetrics.spacing])
        XCTAssertEqual(layout.pillFrames.map(\.height), [TabPillMetrics.height, TabPillMetrics.height])
        let french = [TabPillMetrics.width(title: "Calendrier"), TabPillMetrics.width(title: "Tray")]
        let frenchLayout = ModuleTabLayout(pillWidths: french, shapeWidth: 420, geometry: physicalGeometry)
        XCTAssertEqual(frenchLayout.pillFrames.first?.minX, 9)
    }

    private func notchRect(inShapeWidth width: CGFloat) -> CGRect {
        let notch = physicalGeometry.notchRect
        let originX = physicalGeometry.screenFrame.midX - width / 2
        return notch.offsetBy(dx: -originX, dy: 0)
    }
}
