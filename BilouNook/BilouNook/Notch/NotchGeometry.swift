import AppKit
import SwiftUI
import Observation

struct NotchGeometry: Equatable {
    static let overlap: CGFloat = 0.5
    static let virtualWidth: CGFloat = 200
    static let virtualHeight: CGFloat = 32
    static let forbiddenZoneExpansion: CGFloat = 6

    let screenFrame: CGRect
    let backingScaleFactor: CGFloat
    let hardwareNotchRect: CGRect?
    let safeAreaTop: CGFloat
    let widthDelta: CGFloat
    let heightDelta: CGFloat
    let topFlareRadiusOverride: CGFloat
    let bottomRadiusOverride: CGFloat
    let showIslandStyle: Bool

    init(
        screenFrame: CGRect,
        backingScaleFactor: CGFloat,
        auxLeft: CGRect?,
        auxRight: CGRect?,
        safeAreaTop: CGFloat,
        widthDelta: CGFloat = 0,
        heightDelta: CGFloat = 0,
        topFlareRadiusOverride: CGFloat = 0,
        bottomRadiusOverride: CGFloat = 0,
        showIslandStyle: Bool = true
    ) {
        self.screenFrame = screenFrame
        self.backingScaleFactor = backingScaleFactor
        self.hardwareNotchRect = Self.resolveHardwareNotchRect(
            screenFrame: screenFrame,
            auxLeft: auxLeft,
            auxRight: auxRight,
            safeAreaTop: safeAreaTop
        )
        self.safeAreaTop = safeAreaTop
        self.widthDelta = widthDelta
        self.heightDelta = heightDelta
        self.topFlareRadiusOverride = topFlareRadiusOverride
        self.bottomRadiusOverride = bottomRadiusOverride
        self.showIslandStyle = showIslandStyle
    }

    private init(copying g: NotchGeometry, showIslandStyle: Bool) {
        self.screenFrame = g.screenFrame
        self.backingScaleFactor = g.backingScaleFactor
        self.hardwareNotchRect = g.hardwareNotchRect
        self.safeAreaTop = g.safeAreaTop
        self.widthDelta = g.widthDelta
        self.heightDelta = g.heightDelta
        self.topFlareRadiusOverride = g.topFlareRadiusOverride
        self.bottomRadiusOverride = g.bottomRadiusOverride
        self.showIslandStyle = showIslandStyle
    }

    func withIslandStyle(_ show: Bool) -> NotchGeometry {
        NotchGeometry(copying: self, showIslandStyle: show)
    }

    var presentationMode: NotchPresentationMode {
        NotchPresentationMode.resolve(hasHardwareNotch: hardwareNotchRect != nil, showIslandStyle: showIslandStyle)
    }

    static func live(
        for screen: NSScreen = ScreenResolver.shared.targetScreen(),
        settings: SettingsStore = .shared
    ) -> NotchGeometry {
        NotchGeometry(
            screenFrame: screen.frame,
            backingScaleFactor: screen.backingScaleFactor,
            auxLeft: screen.auxiliaryTopLeftArea,
            auxRight: screen.auxiliaryTopRightArea,
            safeAreaTop: screen.safeAreaInsets.top,
            widthDelta: CGFloat(settings.fineTuneWidth),
            heightDelta: CGFloat(settings.fineTuneHeight),
            topFlareRadiusOverride: CGFloat(settings.topFlareRadius),
            bottomRadiusOverride: CGFloat(settings.bottomRadius)
        )
    }

    var isPhysicalNotch: Bool {
        hardwareNotchRect != nil
    }

    var notchRect: CGRect {
        hardwareNotchRect ?? virtualNotchRect
    }

    var virtualNotchRect: CGRect {
        let height = max(Self.virtualHeight, safeAreaTop)
        return CGRect(
            x: screenFrame.midX - Self.virtualWidth / 2,
            y: screenFrame.maxY - height,
            width: Self.virtualWidth,
            height: height
        )
    }

    var topFlareRadius: CGFloat {
        let raw = topFlareRadiusOverride > 0
            ? topFlareRadiusOverride
            : min(max(notchRect.height * 0.1875, 3), 8)
        return min(raw, max(0, min(shapeWidth, shapeHeight) / 2))
    }

    var bottomRadius: CGFloat {
        let raw = bottomRadiusOverride > 0
            ? bottomRadiusOverride
            : min(max(notchRect.height * 0.4375, 6), 16)
        return min(raw, max(0, min(shapeWidth, shapeHeight) / 2))
    }

    func closedMetrics(isLiveActivityActive: Bool) -> NotchMetrics {
        let baseWidth = max(shapeWidth, 2)
        let baseHeight = max(shapeHeight, 2)
        let overlappedWidth = baseWidth + Self.overlap * 2
        let targetWidth = LiveActivityLayout.targetWidth(
            baseWidth: overlappedWidth,
            notchWidth: baseWidth,
            isLiveActivityActive: isLiveActivityActive
        )
        let width = Self.pixelAlignedWidth(
            targetWidth,
            scale: backingScaleFactor
        )

        return NotchMetrics(
            w: width,
            h: Self.pixelCeil(baseHeight + Self.overlap, scale: backingScaleFactor),
            t: topFlareRadius,
            b: bottomRadius
        )
    }

    func openMetrics(for contentSize: CGSize) -> NotchMetrics {
        let width = Self.pixelAlignedWidth(
            max(contentSize.width, 2),
            scale: backingScaleFactor
        )
        let height = Self.pixelCeil(
            max(contentSize.height, 2),
            scale: backingScaleFactor
        )
        let limit = max(0, min(width, height) / 2)
        return NotchMetrics(
            w: width,
            h: height,
            t: min(topFlareRadius, limit),
            b: min(20, limit)
        )
    }

    static func pixelCeil(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return value }
        return ceil(value * scale) / scale
    }

    static func pixelAlignedWidth(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return value }
        let pixels = (value * scale).rounded()
        let evenPixels = pixels.truncatingRemainder(dividingBy: 2) == 0
            ? pixels
            : pixels + 1
        return evenPixels / scale
    }

    private var shapeWidth: CGFloat {
        max(notchRect.width + widthDelta, 2)
    }

    private var shapeHeight: CGFloat {
        max(notchRect.height + heightDelta, 2)
    }

    private static func resolveHardwareNotchRect(
        screenFrame: CGRect,
        auxLeft: CGRect?,
        auxRight: CGRect?,
        safeAreaTop: CGFloat
    ) -> CGRect? {
        guard safeAreaTop > 0, let auxLeft, let auxRight else { return nil }
        guard let width = LiveActivityLayout.hardwareNotchWidth(
            auxLeft: auxLeft,
            auxRight: auxRight
        ) else {
            return nil
        }
        return CGRect(
            x: auxLeft.maxX,
            y: screenFrame.maxY - safeAreaTop,
            width: width,
            height: safeAreaTop
        )
    }

    var forbiddenZone: CGRect {
        let base = notchRect
        return CGRect(
            x: base.minX - Self.forbiddenZoneExpansion,
            y: base.minY,
            width: base.width + Self.forbiddenZoneExpansion * 2,
            height: base.height
        )
    }

    func forbiddenZone(inShapeSpace shapeWidth: CGFloat? = nil) -> CGRect {
        let base = notchRect
        let screen = screenFrame
        let shapeW = shapeWidth ?? base.width
        let shapeOriginX = screen.midX - shapeW / 2
        return CGRect(
            x: base.minX - Self.forbiddenZoneExpansion - shapeOriginX,
            y: 0,
            width: base.width + Self.forbiddenZoneExpansion * 2,
            height: base.height
        )
    }

    func topBandFlanks(inShapeSpace shapeWidth: CGFloat) -> (left: CGRect, right: CGRect) {
        let width = max(0, shapeWidth)
        let forbidden = forbiddenZone(inShapeSpace: width)
        let height = notchRect.height
        let leftFlank = CGRect(
            x: 0,
            y: 0,
            width: max(0, min(width, forbidden.minX)),
            height: height
        )
        let rightFlank = CGRect(
            x: min(width, max(0, forbidden.maxX)),
            y: 0,
            width: max(0, width - forbidden.maxX),
            height: height
        )
        return (left: leftFlank, right: rightFlank)
    }

    var contentTop: CGFloat {
        notchRect.height + 6
    }
}

enum NotchPresentationMode: Equatable {
    case mergedWithPhysical
    case ownDynamicIsland
    case edgePinned

    static func resolve(hasHardwareNotch: Bool, showIslandStyle: Bool) -> NotchPresentationMode {
        if hasHardwareNotch { return .mergedWithPhysical }
        return showIslandStyle ? .ownDynamicIsland : .edgePinned
    }
}

enum NotchPresentationStyle {
    static let hairlineOpacity: Double = 0.06
    static let islandBottomRadiusClosed: CGFloat = 22
    static let islandBottomRadiusOpen: CGFloat = 24

    static func fill(for mode: NotchPresentationMode, isDark: Bool) -> Color {
        if mode == .ownDynamicIsland && !isDark {
            return Color(red: 0.1098, green: 0.1098, blue: 0.1176)
        }
        return Color.black
    }

    static func topRadius(base: CGFloat, userFlare: CGFloat) -> CGFloat {
        userFlare > 0 ? base : 0
    }

    static func bottomRadius(mode: NotchPresentationMode, base: CGFloat, isOpen: Bool) -> CGFloat {
        guard mode == .ownDynamicIsland else { return base }
        return isOpen ? islandBottomRadiusOpen : islandBottomRadiusClosed
    }
}

struct NotchSafeArea: Equatable {
    var hasHardwareNotch: Bool
    var notchWidth: CGFloat
    var notchHeight: CGFloat

    static let contentTopGap: CGFloat = 2

    var contentTop: CGFloat { notchHeight + Self.contentTopGap }

    func excludedXRange(shapeWidth: CGFloat) -> ClosedRange<CGFloat> {
        let half = notchWidth / 2
        return (shapeWidth / 2 - half)...(shapeWidth / 2 + half)
    }

    func intersectsNotch(x: CGFloat, y: CGFloat, width: CGFloat, shapeWidth: CGFloat) -> Bool {
        guard y < notchHeight else { return false }
        let r = excludedXRange(shapeWidth: shapeWidth)
        return x < r.upperBound && x + width > r.lowerBound
    }

    static func from(_ geometry: NotchGeometry) -> NotchSafeArea {
        let rect = geometry.notchRect
        return NotchSafeArea(
            hasHardwareNotch: geometry.hardwareNotchRect != nil,
            notchWidth: rect.width,
            notchHeight: rect.height
        )
    }
}

@MainActor
@Observable
final class NotchSafeAreaPublisher {
    static let shared = NotchSafeAreaPublisher()
    private(set) var safeArea: NotchSafeArea
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        safeArea = NotchSafeArea.from(NotchGeometryCache.shared.current.geometry)
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let sources: [(NotificationCenter, Notification.Name)] = [
            (center, NSApplication.didChangeScreenParametersNotification),
            (workspace, NSWorkspace.screensDidWakeNotification),
            (workspace, NSWorkspace.didWakeNotification),
            (workspace, NSWorkspace.activeSpaceDidChangeNotification)
        ]
        for (c, name) in sources {
            observers.append(c.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    func refresh() {
        NotchGeometryCache.shared.invalidate()
        let next = NotchSafeArea.from(NotchGeometryCache.shared.current.geometry)
        if next != safeArea { safeArea = next }
    }
}

struct NotchSafeContentModifier: ViewModifier {
    @State private var publisher = NotchSafeAreaPublisher.shared
    func body(content: Content) -> some View {
        content
            .padding(.top, publisher.safeArea.contentTop)
            .padding(.bottom, NookLayout.bottomPadding)
    }
}

extension View {
    func notchSafeContent() -> some View {
        modifier(NotchSafeContentModifier())
    }
}

enum TriggerRectCalculator {
    static let edgeZoneWidth: CGFloat = 200
    static let edgeZoneHeight: CGFloat = 4
    static let islandPadding: CGFloat = 6
    static let edgeDwell: TimeInterval = 0.12
    static let leaveDebounce: TimeInterval = 0.08

    static func rect(
        screenFrame: CGRect,
        geometry: NotchGeometry,
        liveActivityWing: CGFloat,
        paddingX: CGFloat,
        paddingBelow: CGFloat
    ) -> NSRect {
        let top = screenFrame.maxY
        switch geometry.presentationMode {
        case .mergedWithPhysical:
            let n = geometry.notchRect
            let w = n.width + liveActivityWing * 2 + paddingX * 2
            let h = n.height + paddingBelow
            return NSRect(x: screenFrame.midX - w / 2, y: top - h, width: w, height: h)
        case .ownDynamicIsland:
            return pillRect(screenFrame: screenFrame, geometry: geometry, wing: liveActivityWing)
        case .edgePinned:
            if liveActivityWing > 0 {
                return pillRect(screenFrame: screenFrame, geometry: geometry, wing: liveActivityWing)
            }
            return NSRect(
                x: screenFrame.midX - edgeZoneWidth / 2,
                y: top - edgeZoneHeight,
                width: edgeZoneWidth,
                height: edgeZoneHeight
            )
        }
    }

    private static func pillRect(screenFrame: CGRect, geometry: NotchGeometry, wing: CGFloat) -> NSRect {
        let m = geometry.closedMetrics(isLiveActivityActive: false)
        let w = m.w + wing * 2 + islandPadding * 2
        let h = m.h + islandPadding
        return NSRect(x: screenFrame.midX - w / 2, y: screenFrame.maxY - h, width: w, height: h)
    }

    static func dwell(mode: NotchPresentationMode, hasLiveActivity: Bool) -> TimeInterval {
        (mode == .edgePinned && !hasLiveActivity) ? edgeDwell : 0
    }
}
