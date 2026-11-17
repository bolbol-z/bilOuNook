import Foundation
import SwiftUI

enum SettingsDefaults {
    static let fineTuneWidth = 0.0
    static let fineTuneHeight = 0.0
    static let topFlareRadius = 0.0
    static let bottomRadius = 0.0
    static let openOnHover = true
    static let hoverIntentDelay = 0.0
    static let closeDelay = 0.0
    static let minStateDwell = 0.0
    static let verticalGesturesEnabled = true
    static let hapticsEnabled = true
    static let mediaCompactEnabled = true
    static let mediaWidgetEnabled = true
    static let calendarWidgetEnabled = true
    static let hotPaddingX = 6.0
    static let hotPaddingBelow = 4.0
    static let flyByGuardEnabled = false
    static let flyBySpeedThreshold = 2.5
    static let hapticPattern = "generic"
    static let showDynamicIslandStyle = true
}

extension Notification.Name {
    static let bilouNookSettingsDidReset = Notification.Name("BilouNookSettingsDidReset")
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    
    @Published var fineTuneWidth: Double {
        didSet { UserDefaults.standard.set(fineTuneWidth, forKey: "fineTuneWidth") }
    }
    @Published var fineTuneHeight: Double {
        didSet { UserDefaults.standard.set(fineTuneHeight, forKey: "fineTuneHeight") }
    }
    @Published var topFlareRadius: Double {
        didSet { UserDefaults.standard.set(topFlareRadius, forKey: "topFlareRadius") }
    }
    @Published var bottomRadius: Double {
        didSet { UserDefaults.standard.set(bottomRadius, forKey: "bottomRadius") }
    }
    @Published var openOnHover: Bool {
        didSet { UserDefaults.standard.set(openOnHover, forKey: "openOnHover") }
    }
    @Published var hoverIntentDelay: Double {
        didSet { UserDefaults.standard.set(hoverIntentDelay, forKey: "hoverIntentDelay") }
    }
    @Published var closeDelay: Double {
        didSet { UserDefaults.standard.set(closeDelay, forKey: "closeDelay") }
    }
    @Published var minStateDwell: Double {
        didSet { UserDefaults.standard.set(minStateDwell, forKey: "minStateDwell") }
    }
    @Published var verticalGesturesEnabled: Bool {
        didSet { UserDefaults.standard.set(verticalGesturesEnabled, forKey: "verticalGesturesEnabled") }
    }
    @Published var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: "hapticsEnabled") }
    }
    @Published var mediaCompactEnabled: Bool {
        didSet { UserDefaults.standard.set(mediaCompactEnabled, forKey: "mediaCompactEnabled") }
    }
    @Published var mediaWidgetEnabled: Bool {
        didSet { UserDefaults.standard.set(mediaWidgetEnabled, forKey: "mediaWidgetEnabled") }
    }
    @Published var calendarWidgetEnabled: Bool {
        didSet { UserDefaults.standard.set(calendarWidgetEnabled, forKey: "calendarWidgetEnabled") }
    }
    @Published var hotPaddingX: Double {
        didSet { UserDefaults.standard.set(hotPaddingX, forKey: "hotPaddingX") }
    }
    @Published var hotPaddingBelow: Double {
        didSet { UserDefaults.standard.set(hotPaddingBelow, forKey: "hotPaddingBelow") }
    }
    @Published var flyByGuardEnabled: Bool {
        didSet { UserDefaults.standard.set(flyByGuardEnabled, forKey: "flyByGuardEnabled") }
    }
    @Published var flyBySpeedThreshold: Double {
        didSet { UserDefaults.standard.set(flyBySpeedThreshold, forKey: "flyBySpeedThreshold") }
    }
    @Published var hapticPattern: String {
        didSet { UserDefaults.standard.set(hapticPattern, forKey: "hapticPattern") }
    }
    @Published var showDynamicIslandStyle: Bool {
        didSet {
            UserDefaults.standard.set(showDynamicIslandStyle, forKey: "showDynamicIslandStyle")
            SettingsStore.invalidateGeometry()
        }
    }

    private static func invalidateGeometry() {
        if Thread.isMainThread {
            MainActor.assumeIsolated { NotchGeometryCache.shared.invalidate() }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { NotchGeometryCache.shared.invalidate() } }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.fineTuneWidth = defaults.object(forKey: "fineTuneWidth") as? Double ?? SettingsDefaults.fineTuneWidth
        self.fineTuneHeight = defaults.object(forKey: "fineTuneHeight") as? Double ?? SettingsDefaults.fineTuneHeight
        self.topFlareRadius = defaults.object(forKey: "topFlareRadius") as? Double ?? SettingsDefaults.topFlareRadius
        self.bottomRadius = defaults.object(forKey: "bottomRadius") as? Double ?? SettingsDefaults.bottomRadius
        self.openOnHover = defaults.object(forKey: "openOnHover") as? Bool ?? SettingsDefaults.openOnHover
        self.hoverIntentDelay = defaults.object(forKey: "hoverIntentDelay") as? Double ?? SettingsDefaults.hoverIntentDelay
        self.closeDelay = defaults.object(forKey: "closeDelay") as? Double ?? SettingsDefaults.closeDelay
        self.minStateDwell = defaults.object(forKey: "minStateDwell") as? Double ?? SettingsDefaults.minStateDwell
        self.verticalGesturesEnabled = defaults.object(forKey: "verticalGesturesEnabled") as? Bool ?? SettingsDefaults.verticalGesturesEnabled
        self.hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? SettingsDefaults.hapticsEnabled
        self.mediaCompactEnabled = defaults.object(forKey: "mediaCompactEnabled") as? Bool ?? SettingsDefaults.mediaCompactEnabled
        self.mediaWidgetEnabled = defaults.object(forKey: "mediaWidgetEnabled") as? Bool ?? SettingsDefaults.mediaWidgetEnabled
        self.calendarWidgetEnabled = defaults.object(forKey: "calendarWidgetEnabled") as? Bool ?? SettingsDefaults.calendarWidgetEnabled
        self.hotPaddingX = defaults.object(forKey: "hotPaddingX") as? Double ?? SettingsDefaults.hotPaddingX
        self.hotPaddingBelow = defaults.object(forKey: "hotPaddingBelow") as? Double ?? SettingsDefaults.hotPaddingBelow
        self.flyByGuardEnabled = defaults.object(forKey: "flyByGuardEnabled") as? Bool ?? SettingsDefaults.flyByGuardEnabled
        self.flyBySpeedThreshold = defaults.object(forKey: "flyBySpeedThreshold") as? Double ?? SettingsDefaults.flyBySpeedThreshold
        self.hapticPattern = defaults.string(forKey: "hapticPattern") ?? SettingsDefaults.hapticPattern
        self.showDynamicIslandStyle = defaults.object(forKey: "showDynamicIslandStyle") as? Bool ?? SettingsDefaults.showDynamicIslandStyle
    }

    func resetToDefaults() {
        fineTuneWidth = SettingsDefaults.fineTuneWidth
        fineTuneHeight = SettingsDefaults.fineTuneHeight
        topFlareRadius = SettingsDefaults.topFlareRadius
        bottomRadius = SettingsDefaults.bottomRadius
        openOnHover = SettingsDefaults.openOnHover
        hoverIntentDelay = SettingsDefaults.hoverIntentDelay
        closeDelay = SettingsDefaults.closeDelay
        minStateDwell = SettingsDefaults.minStateDwell
        verticalGesturesEnabled = SettingsDefaults.verticalGesturesEnabled
        hapticsEnabled = SettingsDefaults.hapticsEnabled
        mediaCompactEnabled = SettingsDefaults.mediaCompactEnabled
        mediaWidgetEnabled = SettingsDefaults.mediaWidgetEnabled
        calendarWidgetEnabled = SettingsDefaults.calendarWidgetEnabled
        hotPaddingX = SettingsDefaults.hotPaddingX
        hotPaddingBelow = SettingsDefaults.hotPaddingBelow
        flyByGuardEnabled = SettingsDefaults.flyByGuardEnabled
        flyBySpeedThreshold = SettingsDefaults.flyBySpeedThreshold
        hapticPattern = SettingsDefaults.hapticPattern
        showDynamicIslandStyle = SettingsDefaults.showDynamicIslandStyle
        NotificationCenter.default.post(name: .bilouNookSettingsDidReset, object: self)
    }
}

enum SettingsCleanup {
    static let staleSlowMotionKey = "slowMotion"
    static let staleHotPaddingKeys = ["hotPaddingX", "hotPaddingBelow"]

    @discardableResult
    static func purgeSlowMotion(defaults: UserDefaults = .standard) -> Bool? {
        let value = defaults.object(forKey: staleSlowMotionKey) as? Bool
        defaults.removeObject(forKey: staleSlowMotionKey)
        return value
    }

    @discardableResult
    static func purgeHotZonePaddings(defaults: UserDefaults = .standard) -> [String: Any]? {
        var removed: [String: Any] = [:]
        for key in staleHotPaddingKeys {
            if let value = defaults.object(forKey: key) {
                removed[key] = value
                defaults.removeObject(forKey: key)
            }
        }
        return removed.isEmpty ? nil : removed
    }
}
