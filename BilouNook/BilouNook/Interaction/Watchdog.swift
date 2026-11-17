import AppKit

final class Watchdog {
    static let shared = Watchdog()
    private var watchdogToken: LifecycleManager.Token?

    func start() {
        stop()
        let state = NotchState.shared
        let token = MainActor.assumeIsolated {
            LifecycleManager.shared.timer(
                "notch.watchdog",
                interval: 0.25,
                tolerance: 0.05,
                tier: .whileOpen
            ) { [weak state] in
                guard let state else { return }
                let mouse = NSEvent.mouseLocation
                let snapshot = MainActor.assumeIsolated { NotchGeometryCache.shared.current }
                let rect = InteractionRegion.interactiveRect(
                    for: state.phase,
                    screenFrame: snapshot.screen.frame,
                    notchGeom: snapshot.geometry
                )
                state.watchdogTick(isOutside: !ZoneMath.contains(rect, mouse))
            }
        }
        watchdogToken = token
    }

    func stop() {
        MainActor.assumeIsolated {
            watchdogToken?.cancel()
            watchdogToken = nil
        }
    }
}
