import AppKit
#if DEBUG
import QuartzCore
#endif

final class MouseMonitor {
    static let shared = MouseMonitor()
    var onEnterHotZone: (() -> Void)?
    var onLeaveOpenArea: (() -> Void)?
    var onMouseMove: ((NSPoint) -> Void)?
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastPoint: NSPoint = .zero
    private var lastTime: Date = .distantPast
    private var wasInHotZone = false
    private var gate = EventGate(minInterval: 1.0/60.0)
    private var dwellStart: Date?
    private var dwellItem: DispatchWorkItem?
    /// Injectable hot-zone lookup (production: screen-derived). Tests override.
    var hotZoneProvider: () -> NSRect = {
        let snapshot = MainActor.assumeIsolated { NotchGeometryCache.shared.current }
        return InteractionRegion.hotZone(
            screenFrame: snapshot.screen.frame,
            notchGeom: snapshot.geometry
        )
    }
    
    func start() {
        guard globalMonitor == nil && localMonitor == nil else { return }
        #if DEBUG
        ZoneMath.debugSelfCheck()
        #endif
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }
    
    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        wasInHotZone = false
        cancelDwell()
    }

    func resetHoverState() {
        wasInHotZone = false
        cancelDwell()
    }

    /// Re-runs the leave/enter check at the current cursor position without waiting for a mouse event.
    /// Call it whenever something that suppressed the check (NotchHold) ends.
    func reevaluate() {
        handle(mouse: NSEvent.mouseLocation, now: Date(), timestamp: ProcessInfo.processInfo.systemUptime)
    }

    private func fireOrDwell(now: Date) {
        if NSEvent.pressedMouseButtons != 0 {
            cancelDwell()
            return
        }
        let snapshot = MainActor.assumeIsolated { NotchGeometryCache.shared.current }
        let active = MainActor.assumeIsolated { IslandModel.shared.isActive }
        let dwell = TriggerRectCalculator.dwell(mode: snapshot.geometry.presentationMode, hasLiveActivity: active)
        if dwell <= 0 {
            cancelDwell()
            onEnterHotZone?()
            return
        }
        if dwellStart == nil {
            dwellStart = now
            scheduleDwellRecheck(after: dwell)
        }
        if let start = dwellStart, now.timeIntervalSince(start) >= dwell {
            cancelDwell()
            onEnterHotZone?()
        }
    }

    private func scheduleDwellRecheck(after delay: TimeInterval) {
        dwellItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.dwellItem = nil
            guard self.dwellStart != nil, NotchState.shared.phase == .closed else {
                self.dwellStart = nil
                return
            }
            let mouse = NSEvent.mouseLocation
            self.dwellStart = nil
            if NSEvent.pressedMouseButtons == 0, ZoneMath.contains(self.hotZoneProvider(), mouse) {
                self.onEnterHotZone?()
            }
        }
        dwellItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.005, execute: item)
    }

    private func cancelDwell() {
        dwellStart = nil
        dwellItem?.cancel()
        dwellItem = nil
    }
    
    private func handle(
        _ event: NSEvent? = nil,
        mouse: NSPoint = NSEvent.mouseLocation,
        now: Date = Date(),
        timestamp: TimeInterval? = nil
    ) {
        if NotchHold.shared.isActive {
            // The hold suppresses enter/leave decisions only. Click-through tracking must keep running,
            // otherwise a panel opened programmatically while the pointer is away stays
            // ignoresMouseEvents == true and the first click lands on the desktop.
            onMouseMove?(mouse)
            return
        }
        // Leave check runs first: nothing below may skip it.
        let phase = NotchState.shared.phase
        if phase == .opening || phase == .open {
            let snapshot = MainActor.assumeIsolated { NotchGeometryCache.shared.current }
            let leaveRect = InteractionRegion.interactiveRect(
                for: phase,
                screenFrame: snapshot.screen.frame,
                notchGeom: snapshot.geometry
            )
            if !ZoneMath.contains(leaveRect, mouse) {
                onLeaveOpenArea?()
            }
        }
        #if DEBUG
        MotionRecorder.shared.recordPointer(at: CACurrentMediaTime())
        #endif
        onMouseMove?(mouse)
        let hotRect = hotZoneProvider()
        let inHotZone = ZoneMath.contains(hotRect, mouse)
        // Drop near-duplicate events unless hot-zone membership would change.
        let ts = timestamp ?? event?.timestamp ?? now.timeIntervalSince1970
        gate.minInterval = (NotchState.shared.phase == .closed) ? 1.0/60.0 : 1.0/30.0
        guard gate.allow(ts) else { return }
        if SettingsStore.shared.flyByGuardEnabled && lastTime != .distantPast {
            let dx = mouse.x - lastPoint.x
            let dy = mouse.y - lastPoint.y
            let dist = sqrt(dx*dx + dy*dy)
            let dt = now.timeIntervalSince(lastTime)
            if dt > 0 && dist / dt > SettingsStore.shared.flyBySpeedThreshold {
                lastPoint = mouse
                lastTime = now
                return
            }
        }
        lastPoint = mouse
        lastTime = now
        if inHotZone && !wasInHotZone {
            wasInHotZone = true
            #if DEBUG
            MouseLog.write(String(format: "HOT ENTER mouse=(%.1f,%.1f) hotZone={{%.1f,%.1f},{%.1f,%.1f}}", mouse.x, mouse.y, hotRect.minX, hotRect.minY, hotRect.width, hotRect.height))
            #endif
        } else if !inHotZone && wasInHotZone {
            wasInHotZone = false
            #if DEBUG
            MouseLog.write(String(format: "HOT LEAVE mouse=(%.1f,%.1f)", mouse.x, mouse.y))
            #endif
        }
        // Level-triggered: fire on EVERY move while closed + in zone.
        // NotchState.enterIntent() is idempotent, so this is safe.
        if inHotZone && NotchState.shared.phase == .closed {
            fireOrDwell(now: now)
        } else {
            cancelDwell()
        }
    }

    #if DEBUG
    func simulateMove(to point: NSPoint, now: Date = Date()) {
        handle(mouse: point, now: now)
    }
    #endif
}
