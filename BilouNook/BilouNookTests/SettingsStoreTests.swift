import XCTest

final class SettingsStoreTests: XCTestCase {
    private static let keys = [
        "fineTuneWidth", "fineTuneHeight", "topFlareRadius", "bottomRadius",
        "openOnHover", "hoverIntentDelay", "closeDelay", "minStateDwell",
        "verticalGesturesEnabled", "hapticsEnabled", "mediaCompactEnabled",
        "mediaWidgetEnabled", "calendarWidgetEnabled", "hotPaddingX",
        "hotPaddingBelow", "flyByGuardEnabled", "flyBySpeedThreshold", "hapticPattern",
    ]
    private var savedDefaults: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        for key in Self.keys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
        }
    }

    override func tearDown() {
        for key in Self.keys {
            if let value = savedDefaults[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    func testDeadSettingsAreRemoved() {
        let labels = Set(Mirror(reflecting: SettingsStore.shared).children.compactMap(\.label))
        XCTAssertTrue(labels.contains("_fineTuneWidth"))

        let removed = [
            "_handlerEnabled",
            "_handlerWidth",
            "_handlerHeight",
            "_displayMode",
            "_contentInDelay",
            "_contentStagger",
            "_scrubPause",
            "_scrubProgress",
            "_openHapticPattern",
            "_closeHapticPattern",
            "_contentScale_ASSUMPTION",
            "_contentBlur_ASSUMPTION",
            "_contentAnchorY_ASSUMPTION"
        ]
        for label in removed {
            XCTAssertFalse(labels.contains(label), "\(label) should no longer be persisted")
        }
    }

    func testWidgetsDefaultToEnabled() throws {
        let suiteName = "BilouNookTests.widgetDefaults"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.mediaWidgetEnabled)
        XCTAssertTrue(store.calendarWidgetEnabled)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaultsMatchTheApprovedRanges() throws {
        let suiteName = "BilouNookTests.defaults"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.hoverIntentDelay, 0)
        XCTAssertEqual(store.closeDelay, 0)
        XCTAssertEqual(store.minStateDwell, 0)
        XCTAssertTrue(store.openOnHover)
        XCTAssertTrue(store.verticalGesturesEnabled)
        XCTAssertTrue(store.hapticsEnabled)
        XCTAssertEqual(store.hapticPattern, "generic")
        XCTAssertTrue(store.mediaWidgetEnabled)
        XCTAssertTrue(store.calendarWidgetEnabled)
        XCTAssertTrue(store.mediaCompactEnabled)
        XCTAssertEqual(store.hotPaddingX, 6)
        XCTAssertEqual(store.hotPaddingBelow, 4)
        XCTAssertFalse(store.flyByGuardEnabled)
        XCTAssertEqual(store.flyBySpeedThreshold, 2.5)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testResetRestoresEveryKeyAndPostsOneNotification() {
        let store = SettingsStore.shared
        store.fineTuneWidth = 9
        store.fineTuneHeight = 9
        store.topFlareRadius = 9
        store.bottomRadius = 9
        store.openOnHover = false
        store.hoverIntentDelay = 0.2
        store.closeDelay = 0.3
        store.minStateDwell = 0.4
        store.verticalGesturesEnabled = false
        store.hapticsEnabled = false
        store.mediaCompactEnabled = false
        store.mediaWidgetEnabled = false
        store.calendarWidgetEnabled = false
        store.hotPaddingX = 9
        store.hotPaddingBelow = 9
        store.flyByGuardEnabled = true
        store.flyBySpeedThreshold = 9
        store.hapticPattern = "levelChange"

        var notifications = 0
        let token = NotificationCenter.default.addObserver(
            forName: .bilouNookSettingsDidReset,
            object: store,
            queue: nil
        ) { _ in
            notifications += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }

        store.resetToDefaults()

        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(store.fineTuneWidth, SettingsDefaults.fineTuneWidth)
        XCTAssertEqual(store.fineTuneHeight, SettingsDefaults.fineTuneHeight)
        XCTAssertEqual(store.topFlareRadius, SettingsDefaults.topFlareRadius)
        XCTAssertEqual(store.bottomRadius, SettingsDefaults.bottomRadius)
        XCTAssertTrue(store.openOnHover)
        XCTAssertEqual(store.hoverIntentDelay, 0)
        XCTAssertEqual(store.closeDelay, 0)
        XCTAssertEqual(store.minStateDwell, 0)
        XCTAssertTrue(store.verticalGesturesEnabled)
        XCTAssertTrue(store.hapticsEnabled)
        XCTAssertTrue(store.mediaCompactEnabled)
        XCTAssertTrue(store.mediaWidgetEnabled)
        XCTAssertTrue(store.calendarWidgetEnabled)
        XCTAssertEqual(store.hotPaddingX, 6)
        XCTAssertEqual(store.hotPaddingBelow, 4)
        XCTAssertFalse(store.flyByGuardEnabled)
        XCTAssertEqual(store.flyBySpeedThreshold, 2.5)
        XCTAssertEqual(store.hapticPattern, "generic")
    }

    func testPurgeHotZonePaddingsRemovesStoredKeys() {
        let suiteName = "bilou.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(4.0, forKey: "hotPaddingX")
        defaults.set(2.0, forKey: "hotPaddingBelow")

        let removed = SettingsCleanup.purgeHotZonePaddings(defaults: defaults)

        XCTAssertEqual(removed?["hotPaddingX"] as? Double, 4.0)
        XCTAssertEqual(removed?["hotPaddingBelow"] as? Double, 2.0)
        XCTAssertNil(defaults.object(forKey: "hotPaddingX"))
        XCTAssertNil(defaults.object(forKey: "hotPaddingBelow"))
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testSlowMotionIsNotAPersistedSetting() {
        let labels = Set(Mirror(reflecting: SettingsStore.shared).children.compactMap(\.label))
        XCTAssertFalse(labels.contains("_slowMotion"))
    }

    func testPurgeSlowMotionRemovesTheStaleDefaultOnce() throws {
        let suiteName = "BilouNookTests.slowMotionPurge"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: SettingsCleanup.staleSlowMotionKey)

        XCTAssertEqual(SettingsCleanup.purgeSlowMotion(defaults: defaults), true)
        XCTAssertNil(defaults.object(forKey: SettingsCleanup.staleSlowMotionKey))
        XCTAssertNil(SettingsCleanup.purgeSlowMotion(defaults: defaults))

        defaults.removePersistentDomain(forName: suiteName)
    }
}
