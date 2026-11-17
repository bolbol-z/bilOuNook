import CoreGraphics
import XCTest

final class NookLayoutTests: XCTestCase {
    func testInterimPageWidthUsesMinimum() {
        XCTAssertEqual(NookLayout.pageWidth(widths: [195]), 300)
    }

    func testFullPageWidthMatchesSpec() {
        XCTAssertEqual(NookLayout.pageWidth(widths: [195, 224]), 420)
    }

    func testPreferredHeightMatchesSpec() {
        XCTAssertEqual(NookLayout.preferredHeight(notchHeight: 32), 118)
        XCTAssertEqual(NookLayout.preferredHeight(notchHeight: 24), 110)
    }

    func testContentRowStartsTwoPointsBelowNotch() {
        XCTAssertEqual(NookLayout.rowTop(notchHeight: 32), 34)
        XCTAssertEqual(NookLayout.contentFrame(pageWidth: 420, notchHeight: 32), CGRect(x: 0, y: 34, width: 420, height: 75))
    }

    func testWidgetAndDividerFrames() {
        XCTAssertEqual(NookLayout.widgetFrames(widths: [195, 224]), [
            CGRect(x: 0, y: 0, width: 195, height: 75),
            CGRect(x: 196, y: 0, width: 224, height: 75),
        ])
        XCTAssertEqual(NookLayout.dividerFrames(widths: [195, 224]), [
            CGRect(x: 195, y: 0, width: 1, height: 75),
        ])
        XCTAssertTrue(NookLayout.dividerFrames(widths: [195]).isEmpty)
    }

    func testMediaWidgetMatchesSpec() {
        let widget = MediaWidget()
        XCTAssertEqual(widget.id, "media")
        XCTAssertEqual(widget.preferredWidth, 195)
    }

    func testCalendarWidgetFollowsMediaInTheNookRow() {
        let widgets = NookModule().widgets
        XCTAssertEqual(widgets.map(\.id), ["media", "calendar"])
        XCTAssertEqual(widgets.map(\.preferredWidth), [195, 224])
    }

    func testRegisteredPageSizeIs420ByNotchPlus86() {
        let width = NookLayout.pageWidth(widths: NookModule().widgets.map(\.preferredWidth))
        XCTAssertEqual(width, 420)
        XCTAssertEqual(NookLayout.preferredHeight(notchHeight: 32), 118)
        XCTAssertEqual(NookLayout.preferredHeight(notchHeight: 32), 32 + 86)
    }

    func testSharedRegistryContainsOnlyNook() {
        XCTAssertEqual(ModuleRegistry.shared.modules.map(\.id), ["nook", "files", "timer"])
        XCTAssertEqual(ModuleRegistry.shared.modules.first?.title, "Nook")
        XCTAssertEqual(ModuleRegistry.shared.modules.first?.icon, "lamp.desk.fill")
        XCTAssertEqual(ModuleRegistry.shared.modules.last?.title, "Timer")
        XCTAssertEqual(ModuleRegistry.shared.modules.last?.icon, "timer")
    }
}
