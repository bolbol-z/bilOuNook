import AppKit
import Observation
import SwiftUI

enum LiveActivityLayout {
    static let horizontalWing: CGFloat = 36

    static func hardwareNotchWidth(auxLeft: NSRect?, auxRight: NSRect?) -> CGFloat? {
        guard let auxLeft, let auxRight else { return nil }
        let width = auxRight.minX - auxLeft.maxX
        return width > 0 ? width : nil
    }

    static func targetWidth(
        baseWidth: CGFloat,
        notchWidth: CGFloat,
        isLiveActivityActive: Bool
    ) -> CGFloat {
        guard isLiveActivityActive else { return baseWidth }
        return max(baseWidth, notchWidth + horizontalWing * 2)
    }

    static func physicalNotchWidth(
        auxLeft: NSRect?,
        auxRight: NSRect?,
        safeAreaTop: CGFloat,
        closedWidth: CGFloat
    ) -> CGFloat? {
        if let width = hardwareNotchWidth(auxLeft: auxLeft, auxRight: auxRight) {
            return width
        }
        if safeAreaTop > 0 { return closedWidth }
        return nil
    }

    static func closedMetrics(
        base: NotchMetrics,
        physicalNotchWidth: CGFloat?,
        isLiveActivityActive: Bool
    ) -> NotchMetrics {
        let target = targetWidth(
            baseWidth: base.w,
            notchWidth: physicalNotchWidth ?? base.w,
            isLiveActivityActive: isLiveActivityActive
        )
        return NotchMetrics(w: target, h: base.h, t: base.t, b: base.b)
    }
}

enum IslandMode: Equatable { case none, media, timer, split, airdrop, storage }

enum IslandLayout {
    static func wing(for mode: IslandMode) -> CGFloat { mode == .none ? 0 : 36 }
    static func mode(mediaPlaying: Bool, timerActive: Bool, airdropVisible: Bool, trayCount: Int) -> IslandMode {
        if airdropVisible { return .airdrop }
        if timerActive && mediaPlaying { return .split }
        if timerActive { return .timer }
        if mediaPlaying { return .media }
        if trayCount > 0 { return .storage }
        return .none
    }
}

@MainActor
@Observable
final class IslandModel {
    static let shared = IslandModel()
    var mode: IslandMode {
        let snap: NowPlayingSnapshot? = NowPlayingService.shared.snapshot
        let playing = SettingsStore.shared.mediaCompactEnabled && (snap?.isPlaying ?? false) && (snap?.hasContent ?? false)
        return IslandLayout.mode(mediaPlaying: playing,
                                 timerActive: TimerService.shared.isActive,
                                 airdropVisible: AirDropTransfer.shared.isVisibleOnIsland,
                                 trayCount: TrayStore.shared.items.count)
    }
    var isActive: Bool { mode != .none }
    var currentWing: CGFloat { IslandLayout.wing(for: mode) }
}
