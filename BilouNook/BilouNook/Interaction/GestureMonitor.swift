import AppKit
import Combine
import SwiftUI
import Observation

struct NotchGestureEvent {
    let deltaY: CGFloat
    let deltaX: CGFloat
    let phase: String
}

final class GestureMonitor {
    static let shared = GestureMonitor()
    var gestureStream = PassthroughSubject<NotchGestureEvent, Never>()
    var onHorizontalSwipe: ((Int) -> Void)?
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var accumulated: CGFloat = 0
    private var accumulatedX: CGFloat = 0
    private var horizontalConsumed = false
    private var inGesture = false
    private(set) var gestureOwner: String?

    func acquireGestureOwner(_ owner: String) {
        gestureOwner = owner
    }

    func releaseGestureOwner(_ owner: String) {
        guard gestureOwner == owner else { return }
        gestureOwner = nil
    }
    
    func start() {
        guard globalMonitor == nil && localMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            if MainActor.assumeIsolated({ TabSwipeController.shared.handle(event) }) { return }
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            if MainActor.assumeIsolated({ TabSwipeController.shared.handle(event) }) { return nil }
            self?.handle(event)
            return event
        }
    }
    
    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        accumulated = 0
        accumulatedX = 0
        horizontalConsumed = false
        inGesture = false
        gestureOwner = nil
    }

    private func handle(_ event: NSEvent) {
        // Closed + gestures disabled: nothing to do, return before any work.
        if !SettingsStore.shared.verticalGesturesEnabled { return }
        if MainActor.assumeIsolated({ GestureOwnerRegistry.shared.isOwned("timer.columns") }) { return }
        guard gestureOwner == nil else { return }
        let mouse = NSEvent.mouseLocation
        let snapshot = MainActor.assumeIsolated { NotchGeometryCache.shared.current }
        let state = NotchState.shared
        let interactiveRect = InteractionRegion.interactiveRect(
            for: state.phase,
            screenFrame: snapshot.screen.frame,
            notchGeom: snapshot.geometry
        )
        let hotRect = InteractionRegion.hotZone(
            screenFrame: snapshot.screen.frame,
            notchGeom: snapshot.geometry
        )
        if !ZoneMath.contains(interactiveRect, mouse) && !ZoneMath.contains(hotRect, mouse) { return }
        let deltaY = event.scrollingDeltaY
        let deltaX = event.scrollingDeltaX
        gestureStream.send(NotchGestureEvent(deltaY: deltaY, deltaX: deltaX, phase: event.phase == .ended ? "ended" : event.phase == .cancelled ? "cancelled" : "changed"))
        if event.phase == .ended || event.phase == .cancelled {
            accumulated = 0
            accumulatedX = 0
            horizontalConsumed = false
            inGesture = false
            return
        }
        if abs(deltaX) > abs(deltaY) {
            guard state.phase == .open, !horizontalConsumed else { return }
            accumulatedX += deltaX
            if abs(accumulatedX) >= 24 {
                onHorizontalSwipe?(accumulatedX < 0 ? 1 : -1)
                accumulatedX = 0
                horizontalConsumed = true
            }
            return
        }
        accumulated += deltaY
        if abs(accumulated) >= 12 {
            if accumulated < 0 {
                state.requestOpen(trigger: .gesture)
            } else if accumulated > 0 {
                state.requestClose(reason: .gesture)
            }
            accumulated = 0
        }
    }
}

struct TabSwipeSession {
    enum Axis { case undecided, horizontal, vertical }
    enum Output: Equatable {
        case pass
        case swallow
        case track(CGFloat)
        case commit(Int)      // +1 next, -1 previous
        case snapBack
    }
    struct Input {
        var dx: CGFloat
        var dy: CGFloat
        var phase: NSEvent.Phase
        var momentum: NSEvent.Phase
        var time: TimeInterval
        var precise: Bool
        var shift: Bool
    }
    static let lockDistance: CGFloat = 6
    static let ratio: CGFloat = 1.5
    static let commitDistance: CGFloat = 24
    static let forceCommitDistance: CGFloat = 48
    static let maxOffset: CGFloat = 60
    static let rubberStart: CGFloat = 40
    static let rubberFactor: CGFloat = 0.3
    static let edgeFactor: CGFloat = 0.35
    static let edgeMax: CGFloat = 28
    static let debounce: TimeInterval = 0.30
    static let idleGap: TimeInterval = 0.30

    private(set) var axis: Axis = .undecided
    private var active = false
    private var finished = false
    private var accumX: CGFloat = 0
    private var absX: CGFloat = 0
    private var absY: CGFloat = 0
    private var lastEvent: TimeInterval = 0
    private var lastSwitch: TimeInterval = -10

    mutating func feed(_ i: Input, canGo: (Int) -> Bool) -> Output {
        if !i.precise { return feedWheel(i, canGo: canGo) }
        if i.momentum != [] {
            guard active, axis == .horizontal else {
                if i.momentum == .ended { reset() }
                return .pass
            }
            if i.momentum == .ended { reset() }
            return .swallow
        }
        let beginning = i.phase == .began || i.phase == .mayBegin
        if beginning || !active || (i.time - lastEvent) > Self.idleGap { reset(); active = true }
        lastEvent = i.time
        if i.phase == .mayBegin { return .pass }
        if finished { return axis == .horizontal ? .swallow : .pass }
        absX += abs(i.dx)
        absY += abs(i.dy)
        if axis == .undecided, absX + absY >= Self.lockDistance {
            axis = absX > absY * Self.ratio ? .horizontal : .vertical
        }
        guard axis == .horizontal else { return .pass }
        accumX += i.dx
        let dir = accumX > 0 ? -1 : 1
        let allowed = canGo(dir)
        let canSwitch = allowed && (i.time - lastSwitch) >= Self.debounce
        if i.phase == .ended || i.phase == .cancelled {
            finished = true
            if i.phase == .ended, abs(accumX) >= Self.commitDistance, canSwitch {
                lastSwitch = i.time
                return .commit(dir)
            }
            return .snapBack
        }
        if abs(accumX) >= Self.forceCommitDistance, canSwitch {
            finished = true
            lastSwitch = i.time
            return .commit(dir)
        }
        return .track(Self.offset(for: accumX, allowed: allowed))
    }

    private mutating func feedWheel(_ i: Input, canGo: (Int) -> Bool) -> Output {
        let d: CGFloat = i.dx != 0 ? i.dx : (i.shift ? i.dy : 0)
        guard d != 0 else { return .pass }
        guard i.time - lastSwitch >= Self.debounce else { return .swallow }
        let dir = d > 0 ? -1 : 1
        guard canGo(dir) else { return .swallow }
        lastSwitch = i.time
        return .commit(dir)
    }

    static func offset(for x: CGFloat, allowed: Bool) -> CGFloat {
        let a = abs(x)
        let s: CGFloat = x < 0 ? -1 : 1
        if !allowed { return s * min(a * edgeFactor, edgeMax) }
        if a <= rubberStart { return s * a }
        return s * min(rubberStart + (a - rubberStart) * rubberFactor, maxOffset)
    }

    private mutating func reset() {
        axis = .undecided; active = false; finished = false
        accumX = 0; absX = 0; absY = 0
    }
}

@MainActor
@Observable
final class TabSwipeController {
    static let shared = TabSwipeController()
    private(set) var liveOffset: CGFloat = 0
    @ObservationIgnored private var session = TabSwipeSession()
    @ObservationIgnored private var bypass = false
    @ObservationIgnored var isEnabled: () -> Bool = { false }
    @ObservationIgnored var pointerInside: () -> Bool = { false }
    @ObservationIgnored var ownedByChild: () -> Bool = { false }
    @ObservationIgnored var canGo: (Int) -> Bool = { _ in false }
    @ObservationIgnored var commit: (Int) -> Void = { _ in }

    func settle() { setOffset(0) }

    private func setOffset(_ x: CGFloat) {
        let raw: CGFloat = x.isFinite ? max(-80, min(80, x)) : 0
        let v = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : raw
        guard v != liveOffset else { return }
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { liveOffset = v }
    }

    /// Returns true when the event was consumed by a horizontal tab swipe.
    func handle(_ e: NSEvent) -> Bool {
        guard isEnabled(), pointerInside() else {
            if liveOffset != 0 { setOffset(0) }
            return false
        }
        if e.phase == .began || e.phase == .mayBegin { bypass = ownedByChild() }
        if bypass {
            if e.phase == .ended || e.phase == .cancelled || e.momentumPhase == .ended { bypass = false }
            return false
        }
        let input = TabSwipeSession.Input(
            dx: e.scrollingDeltaX, dy: e.scrollingDeltaY, phase: e.phase, momentum: e.momentumPhase,
            time: e.timestamp, precise: e.hasPreciseScrollingDeltas, shift: e.modifierFlags.contains(.shift))
        let out = session.feed(input, canGo: canGo)
        #if DEBUG
        if GestureTrace.shouldTrace(out: out, phase: e.phase) {
            GestureTrace.log("out=\(out) phase=\(e.phase.rawValue) mom=\(e.momentumPhase.rawValue) dx=\(e.scrollingDeltaX) dy=\(e.scrollingDeltaY)")
        }
        #endif
        switch out {
        case .pass: return false
        case .swallow: return true
        case .track(let x): setOffset(x); return true
        case .commit(let dir): commit(dir); return true
        case .snapBack:
            withAnimation(Animations.tabSwitch) { liveOffset = 0 }
            return true
        }
    }
}

#if DEBUG
enum GestureTrace {
    private static let q = DispatchQueue(label: "com.bilou.gesturetrace", qos: .background)
    static func shouldTrace(out: TabSwipeSession.Output, phase: NSEvent.Phase) -> Bool {
        switch out { case .commit, .snapBack: return true; default: break }
        return phase == .began
    }
    static func log(_ s: String) {
        q.async {
            let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/BilouNook", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("gesture.log")
            let line = "\(Date().timeIntervalSince1970) \(s)\n"
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
            else { try? line.write(to: url, atomically: true, encoding: .utf8) }
        }
    }
}
#endif

class PointerProbeView: NSView {
    var token = ""
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        GestureOwnerRegistry.shared.sync(self)
    }
    var containsPointer: Bool {
        guard let w = window else { return false }
        return bounds.contains(convert(w.mouseLocationOutsideOfEventStream, from: nil))
    }
}

struct PointerProbe: NSViewRepresentable {
    let token: String
    func makeNSView(context: Context) -> PointerProbeView { let v = PointerProbeView(); v.token = token; return v }
    func updateNSView(_ nsView: PointerProbeView, context: Context) { nsView.token = token }
}

@MainActor
final class GestureOwnerRegistry {
    static let shared = GestureOwnerRegistry()
    private let views = NSHashTable<PointerProbeView>.weakObjects()
    func sync(_ v: PointerProbeView) { if v.window != nil { views.add(v) } else { views.remove(v) } }
    func isOwned(_ token: String) -> Bool {
        views.allObjects.contains { $0.token == token && $0.window != nil && $0.containsPointer }
    }
}

extension CGFloat { var finiteOrZero: CGFloat { isFinite ? self : 0 } }
extension Double { var finiteOrZero: Double { isFinite ? self : 0 } }
