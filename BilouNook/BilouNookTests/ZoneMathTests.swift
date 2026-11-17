import AppKit
import XCTest

final class ZoneMathTests: XCTestCase {
    private let rect = NSRect(x: 100, y: 200, width: 50, height: 30)

    func testEdgesAreInclusive() {
        XCTAssertTrue(ZoneMath.contains(rect, NSPoint(x: rect.minX, y: rect.midY)))
        XCTAssertTrue(ZoneMath.contains(rect, NSPoint(x: rect.maxX, y: rect.midY)))
        XCTAssertTrue(ZoneMath.contains(rect, NSPoint(x: rect.midX, y: rect.minY)))
        XCTAssertTrue(ZoneMath.contains(rect, NSPoint(x: rect.midX, y: rect.maxY)))
        XCTAssertTrue(ZoneMath.contains(rect, NSPoint(x: rect.midX, y: rect.midY)))
    }

    func testJustOutsideIsExcluded() {
        XCTAssertFalse(ZoneMath.contains(rect, NSPoint(x: rect.minX - 0.01, y: rect.midY)))
        XCTAssertFalse(ZoneMath.contains(rect, NSPoint(x: rect.maxX + 0.01, y: rect.midY)))
        XCTAssertFalse(ZoneMath.contains(rect, NSPoint(x: rect.midX, y: rect.minY - 0.01)))
        XCTAssertFalse(ZoneMath.contains(rect, NSPoint(x: rect.midX, y: rect.maxY + 0.01)))
    }

    func testTopExtensionIsTwentyPoints() {
        XCTAssertEqual(ZoneMath.topExtension, 20, accuracy: 0.0001)
    }
}


// MARK: - hover-reliability (level-triggered hover + hot zone)

final class HotZoneReliabilityTests: XCTestCase {
    private var savedPaddingX: Double = 0
    private var savedPaddingBelow: Double = 0

    override func setUp() {
        super.setUp()
        let state = NotchState.shared
        state.openOnHover = true
        state.intentDelay = 0
        state.phase = .closed
        savedPaddingX = SettingsStore.shared.hotPaddingX
        savedPaddingBelow = SettingsStore.shared.hotPaddingBelow
        SettingsStore.shared.hotPaddingX = SettingsDefaults.hotPaddingX
        SettingsStore.shared.hotPaddingBelow = SettingsDefaults.hotPaddingBelow
    }

    override func tearDown() {
        NotchState.shared.phase = .closed
        SettingsStore.shared.hotPaddingX = savedPaddingX
        SettingsStore.shared.hotPaddingBelow = savedPaddingBelow
        super.tearDown()
    }

    func testMovingWithinHotZoneRequestsOpenEvenWhenAlreadyInside() {
        let monitor = MouseMonitor()
        monitor.hotZoneProvider = { NSRect(x: 0, y: 900, width: 400, height: 100) }
        var enterCount = 0
        monitor.onEnterHotZone = { enterCount += 1 }
        let t0 = Date(timeIntervalSince1970: 1_000)
        monitor.simulateMove(to: NSPoint(x: 200, y: 950), now: t0)
        monitor.simulateMove(to: NSPoint(x: 200, y: 950), now: t0.addingTimeInterval(0.02)) // stale inside flag

        XCTAssertEqual(enterCount, 2)
    }

    func testLeaveOpenAreaFiresOnFirstOutsideSample() {
        let state = NotchState.shared
        state.phase = .open
        defer { state.phase = .closed }
        let monitor = MouseMonitor()
        var leaveCount = 0
        monitor.onLeaveOpenArea = { leaveCount += 1 }

        let snapshot = MainActor.assumeIsolated { NotchGeometryCache.shared.current }
        let rect = InteractionRegion.interactiveRect(
            for: .open,
            screenFrame: snapshot.screen.frame,
            notchGeom: snapshot.geometry
        )
        monitor.simulateMove(to: NSPoint(x: rect.midX, y: rect.midY), now: Date())
        XCTAssertEqual(leaveCount, 0, "inside the open rect must not request close")
        monitor.simulateMove(to: NSPoint(x: rect.minX - 100, y: rect.minY - 100), now: Date())
        XCTAssertEqual(leaveCount, 1, "first outside sample must leave immediately, no debounce")
    }

    func testLeaveOpenAreaIsNotCalledWhileClosing() {
        let state = NotchState.shared
        state.phase = .closing
        defer { state.phase = .closed }
        let monitor = MouseMonitor()
        var leaveCount = 0
        monitor.onLeaveOpenArea = { leaveCount += 1 }

        monitor.simulateMove(to: NSPoint(x: -5000, y: -5000), now: Date())
        XCTAssertEqual(leaveCount, 0, "closing is not open: leave must not fire")
    }

    func testMouseMoveStillReportedWhileHoldActive() {
        NotchHold.shared.hold(seconds: 5)
        defer { NotchHold.shared.release() }
        let state = NotchState.shared
        state.phase = .open
        defer { state.phase = .closed }
        let monitor = MouseMonitor()
        var moveCount = 0
        var leaveCount = 0
        var enterCount = 0
        monitor.onMouseMove = { _ in moveCount += 1 }
        monitor.onLeaveOpenArea = { leaveCount += 1 }
        monitor.onEnterHotZone = { enterCount += 1 }

        monitor.simulateMove(to: NSPoint(x: -5000, y: -5000), now: Date())
        XCTAssertEqual(moveCount, 1, "click-through tracking must run during a hold")
        XCTAssertEqual(leaveCount, 0, "hold suppresses the leave decision")
        XCTAssertEqual(enterCount, 0, "hold suppresses the enter decision")
    }

    func testDefaultHotZonePaddings() {
        XCTAssertEqual(SettingsDefaults.hotPaddingX, 6.0)
        XCTAssertEqual(SettingsDefaults.hotPaddingBelow, 4.0)
        XCTAssertEqual(ZoneMath.topExtension, 20)
    }

    func testHotZoneDimensionsReflectPaddings() {
        let geometry = NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            backingScaleFactor: 2,
            auxLeft: nil,
            auxRight: nil,
            safeAreaTop: 0
        )
        let zone = InteractionRegion.hotZone(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            notchGeom: geometry
        )
        let closed = geometry.closedMetrics(isLiveActivityActive: false)
        XCTAssertEqual(zone.width, closed.w + 12, accuracy: 0.01)
        XCTAssertEqual(zone.height, closed.h + 6, accuracy: 0.01)
        XCTAssertEqual(zone.maxY, 900)
    }
}
