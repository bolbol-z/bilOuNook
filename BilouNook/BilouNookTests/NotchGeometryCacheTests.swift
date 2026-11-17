import AppKit
import XCTest

private final class CountingScreenProvider: ScreenProviding {
    var screen: NotchScreen
    private(set) var calls = 0

    init(_ screen: NotchScreen) {
        self.screen = screen
    }

    func targetScreen() -> NotchScreen {
        calls += 1
        return screen
    }
}

@MainActor
final class NotchGeometryCacheTests: XCTestCase {
    private let screenA = NotchScreen(
        frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
        backingScaleFactor: 2,
        auxLeft: CGRect(x: 0, y: 924, width: 646, height: 32),
        auxRight: CGRect(x: 825, y: 924, width: 645, height: 32),
        safeAreaTop: 32
    )

    private let screenB = NotchScreen(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        backingScaleFactor: 1,
        auxLeft: nil,
        auxRight: nil,
        safeAreaTop: 0
    )

    private func makeCache(
        provider: CountingScreenProvider,
        appCenter: NotificationCenter = NotificationCenter(),
        workspaceCenter: NotificationCenter = NotificationCenter()
    ) -> NotchGeometryCache {
        NotchGeometryCache(
            screenProvider: provider,
            settings: { SettingsStore() },
            menuBarHeight: { 24 },
            notificationCenter: appCenter,
            workspaceCenter: workspaceCenter
        )
    }

    func testCurrentIsStableUntilInvalidated() {
        let provider = CountingScreenProvider(screenA)
        let cache = makeCache(provider: provider)

        let first = cache.current
        let second = cache.current

        XCTAssertEqual(first.geometry, second.geometry)
        XCTAssertEqual(first.screen.safeAreaTop, second.screen.safeAreaTop, accuracy: 0.0001)
        XCTAssertEqual(first.menuBarHeight, second.menuBarHeight, accuracy: 0.0001)
        XCTAssertEqual(first.backingScale, second.backingScale, accuracy: 0.0001)
        XCTAssertEqual(provider.calls, 1)
    }

    func testInvalidateRecomputesFromTheScreenProvider() {
        let provider = CountingScreenProvider(screenA)
        let cache = makeCache(provider: provider)
        let first = cache.current.geometry

        provider.screen = screenB
        XCTAssertEqual(cache.current.geometry, first)

        cache.invalidate()
        let second = cache.current.geometry

        XCTAssertNotEqual(second, first)
        XCTAssertEqual(second.screenFrame, screenB.frame)
        XCTAssertEqual(provider.calls, 2)
    }

    func testEachScreenNotificationInvalidatesTheCache() {
        let cases: [(Bool, Notification.Name)] = [
            (true, NSApplication.didChangeScreenParametersNotification),
            (false, NSWorkspace.screensDidWakeNotification),
            (false, NSWorkspace.didWakeNotification),
            (false, NSWorkspace.activeSpaceDidChangeNotification)
        ]

        for (usesAppCenter, name) in cases {
            let provider = CountingScreenProvider(screenA)
            let appCenter = NotificationCenter()
            let workspaceCenter = NotificationCenter()
            let cache = makeCache(
                provider: provider,
                appCenter: appCenter,
                workspaceCenter: workspaceCenter
            )
            let first = cache.current.geometry

            provider.screen = screenB
            XCTAssertEqual(cache.current.geometry, first)

            (usesAppCenter ? appCenter : workspaceCenter).post(name: name, object: nil)
            XCTAssertNotEqual(cache.current.geometry, first, "\(name.rawValue) should invalidate")
        }
    }
}
