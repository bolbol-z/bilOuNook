import AppKit
import XCTest

@MainActor
final class SettingsWindowTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func testSettingsWindowIsCreatedOnceRetainedAndNormal() throws {
        let settingsWindow = SettingsWindow()
        let phaseBefore = NotchState.shared.phase

        settingsWindow.show()
        let window = try XCTUnwrap(settingsWindow.window)
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertEqual(window.title, "Settings")
        XCTAssertEqual(window.contentLayoutRect.width, 480, accuracy: 1)
        XCTAssertGreaterThanOrEqual(window.contentLayoutRect.height, 420)
        XCTAssertEqual(NotchState.shared.phase, phaseBefore)

        settingsWindow.show()
        XCTAssertTrue(settingsWindow.window === window)

        window.orderOut(nil)
    }

    func testNotchPanelCanNeverBecomeKeyOrMain() {
        let panel = NotchPanel()
        panel.isReleasedWhenClosed = false

        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
    }
}
