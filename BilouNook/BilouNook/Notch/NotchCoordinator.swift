import AppKit
import Combine
import SwiftUI

struct NotchScreen {
    let frame: CGRect
    let backingScaleFactor: CGFloat
    let auxLeft: CGRect?
    let auxRight: CGRect?
    let safeAreaTop: CGFloat
}

protocol ScreenProviding {
    func targetScreen() -> NotchScreen
}

struct SystemScreenProvider: ScreenProviding {
    func targetScreen() -> NotchScreen {
        let screen = ScreenResolver.shared.targetScreen()
        return NotchScreen(
            frame: screen.frame,
            backingScaleFactor: screen.backingScaleFactor,
            auxLeft: screen.auxiliaryTopLeftArea,
            auxRight: screen.auxiliaryTopRightArea,
            safeAreaTop: screen.safeAreaInsets.top
        )
    }
}

protocol MouseMonitoring: AnyObject {
    var onEnterHotZone: (() -> Void)? { get set }
    var onLeaveOpenArea: (() -> Void)? { get set }
    var onMouseMove: ((NSPoint) -> Void)? { get set }
    func start()
    func stop()
    func resetHoverState()
}

extension MouseMonitor: MouseMonitoring {}

protocol WatchdogControlling: AnyObject {
    func start()
    func stop()
}

extension Watchdog: WatchdogControlling {}

protocol GestureMonitoring: AnyObject {
    func start()
    func stop()
}

extension GestureMonitor: GestureMonitoring {}

protocol SleepObserving: AnyObject {
    func start(onSleep: @escaping () -> Void)
    func stop()
}

final class WorkspaceSleepObserver: SleepObserving {
    private var token: NSObjectProtocol?

    func start(onSleep: @escaping () -> Void) {
        guard token == nil else { return }
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in onSleep() }
    }

    func stop() {
        if let token {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            self.token = nil
        }
    }

    deinit {
        stop()
    }
}

final class WeakPanelReference {
    weak var value: NSPanel?

    init(_ value: NSPanel?) {
        self.value = value
    }
}

extension NotchGeometry {
    static func live(for screen: NotchScreen, settings: SettingsStore = .shared) -> NotchGeometry {
        NotchGeometry(
            screenFrame: screen.frame,
            backingScaleFactor: screen.backingScaleFactor,
            auxLeft: screen.auxLeft,
            auxRight: screen.auxRight,
            safeAreaTop: screen.safeAreaTop,
            widthDelta: CGFloat(settings.fineTuneWidth),
            heightDelta: CGFloat(settings.fineTuneHeight),
            topFlareRadiusOverride: CGFloat(settings.topFlareRadius),
            bottomRadiusOverride: CGFloat(settings.bottomRadius)
        )
    }
}

@MainActor
@Observable
final class NotchCoordinator {
    let state: NotchState
    let settings: SettingsStore
    let modules: ModuleRegistry

    private(set) var metrics = NotchMetrics(w: 200, h: 32, t: 6, b: 14)
    private(set) var contentSize = CGSize(width: NotchPresets.open.w, height: NotchPresets.open.h)
    private(set) var showContent = false
    private(set) var isContentMounted = false
    private(set) var isStarted = false
    private(set) var isReduceMotionEnabled = false

    var panel: NSPanel? { panelReference.value }

    private let panelReference: WeakPanelReference
    private let screenProvider: ScreenProviding
    private let mouseMonitor: MouseMonitoring
    private let watchdog: WatchdogControlling
    private let gestureMonitor: GestureMonitoring
    private let sleepObserver: SleepObserving
    private let scheduler: NotchScheduler
    private let reduceMotionProvider: () -> Bool
    private let ignoresMouseEventsSetter: (Bool) -> Void

    private var settingsCancellable: AnyCancellable?
    private var settingsResetObserver: NSObjectProtocol?
    private var contentHandle: NotchScheduled?
    private var clickThroughHandle: NotchScheduled?
    private var unmountHandle: NotchScheduled?
    private var cachedInteractiveRect: NSRect?
    private var cachedPhase: NotchPhase?
    private var cachedScreenFrame: CGRect?
    private var lastIgnoresMouseEvents: Bool?

    init(
        panel: NSPanel?,
        state: NotchState = .shared,
        settings: SettingsStore = .shared,
        modules: ModuleRegistry = .shared,
        screenProvider: ScreenProviding = SystemScreenProvider(),
        mouseMonitor: MouseMonitoring = MouseMonitor.shared,
        watchdog: WatchdogControlling = Watchdog.shared,
        gestureMonitor: GestureMonitoring = GestureMonitor.shared,
        sleepObserver: SleepObserving = WorkspaceSleepObserver(),
        scheduler: NotchScheduler = SystemNotchScheduler(),
        isReduceMotionEnabled: @escaping () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        },
        ignoresMouseEventsSetter: ((Bool) -> Void)? = nil
    ) {
        let panel = panel
        self.panelReference = WeakPanelReference(panel)
        self.state = state
        self.settings = settings
        self.modules = modules
        self.screenProvider = screenProvider
        self.mouseMonitor = mouseMonitor
        self.watchdog = watchdog
        self.gestureMonitor = gestureMonitor
        self.sleepObserver = sleepObserver
        self.scheduler = scheduler
        self.reduceMotionProvider = isReduceMotionEnabled
        self.ignoresMouseEventsSetter = ignoresMouseEventsSetter ?? { [weak panel] ignores in
            panel?.ignoresMouseEvents = ignores
        }
    }

    static func preview(panel: NSPanel?, metrics: NotchMetrics, showContent: Bool) -> NotchCoordinator {
        let coordinator = NotchCoordinator(panel: panel)
        coordinator.metrics = metrics
        coordinator.contentSize = CGSize(width: metrics.w, height: metrics.h)
        coordinator.showContent = showContent
        return coordinator
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        isReduceMotionEnabled = reduceMotionProvider()
        applySettings()
        let screen = screenProvider.targetScreen()
        switch state.phase {
        case .open, .opening:
            contentSize = activeContentSize()
            metrics = activeOpenMetrics(for: screen)
            showContent = true
            isContentMounted = true
            watchdog.start()
        case .closed, .closing:
            metrics = closedMetrics(for: screen)
            showContent = false
        }
        applyIgnoresMouseEvents(true)
        subscribeToSettings()
        sleepObserver.start { [weak self] in
            self?.state.closeImmediately(reason: .system)
        }
        mouseMonitor.onEnterHotZone = { [weak self] in
            self?.state.enterIntent()
        }
        mouseMonitor.onLeaveOpenArea = { [weak self] in
            guard let self else { return }
            if self.state.phase == .open {
                self.state.cancelIntent()
                self.state.requestClose(reason: .mouseLeft)
            } else if self.state.phase == .closed || self.state.phase == .open {
                self.state.cancelIntent()
            }
        }
        mouseMonitor.onMouseMove = { [weak self] _ in
            self?.updateMouseInteraction()
        }
        mouseMonitor.start()
        updateMouseInteraction()
        gestureMonitor.start()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        mouseMonitor.onEnterHotZone = nil
        mouseMonitor.onLeaveOpenArea = nil
        mouseMonitor.onMouseMove = nil
        mouseMonitor.stop()
        watchdog.stop()
        gestureMonitor.stop()
        sleepObserver.stop()
        settingsCancellable?.cancel()
        settingsCancellable = nil
        if let settingsResetObserver {
            NotificationCenter.default.removeObserver(settingsResetObserver)
        }
        settingsResetObserver = nil
        contentHandle?.cancel()
        contentHandle = nil
        unmountHandle?.cancel()
        unmountHandle = nil
        clickThroughHandle?.cancel()
        clickThroughHandle = nil
    }

    func applySettings() {
        state.openOnHover = settings.openOnHover
        state.intentDelay = settings.hoverIntentDelay
        state.closeDelay = settings.closeDelay
        state.minStateDwell = settings.minStateDwell
        if state.phase == .closed {
            metrics = closedMetrics(for: screenProvider.targetScreen())
        }
        invalidateInteractiveRect()
    }

    func phaseDidChange(from oldPhase: NotchPhase, to newPhase: NotchPhase) {
        LifecycleManager.shared.setNotchOpen(newPhase != .closed)
        guard oldPhase != newPhase else { return }
        if newPhase == .open || newPhase == .opening {
            unmountHandle?.cancel()
            unmountHandle = nil
            isContentMounted = true
            watchdog.start()
            contentHandle?.cancel()
            clickThroughHandle?.cancel()
            let screen = screenProvider.targetScreen()
            contentSize = activeContentSize()
            if oldPhase == .closed, state.lastOpenTrigger != .drag {
                ModuleRegistry.shared.resetToHome()
            }
            showContent = true
            withAnimation(animation(for: .openMetrics)) {
                metrics = activeOpenMetrics(for: screen)
            }
        } else if newPhase == .closed {
            mouseMonitor.resetHoverState()
            contentHandle?.cancel()
            contentHandle = nil
            withAnimation(animation(for: .contentHide)) {
                showContent = false
            }
            let screen = screenProvider.targetScreen()
            withAnimation(animation(for: .closeMetrics)) {
                metrics = closedMetrics(for: screen)
            }
            clickThroughHandle?.cancel()
            clickThroughHandle = scheduler.schedule(after: Animations.clickThroughDelay) { [weak self] in
                guard let self, self.state.phase == .closed else { return }
                self.applyIgnoresMouseEvents(true)
            }
            unmountHandle?.cancel()
            unmountHandle = scheduler.schedule(
                after: Animations.contentUnmountDelay
            ) { [weak self] in
                guard let self, self.state.phase == .closed else { return }
                self.isContentMounted = false
            }
            watchdog.stop()
        }
        invalidateInteractiveRect()
        updateMouseInteraction()
    }

    func activeModuleDidChange() {
        guard state.phase == .open else { return }
        let screen = screenProvider.targetScreen()
        contentSize = activeContentSize()
        withAnimation(animation(for: .moduleChange)) {
            metrics = activeOpenMetrics(for: screen)
        }
        invalidateInteractiveRect()
        updateMouseInteraction()
    }

    func liveActivityDidChange() {
        guard state.phase == .closed else { return }
        let screen = screenProvider.targetScreen()
        let transition: NotchMotionTransition = modules.activeLiveActivity == nil ? .closeMetrics : .openMetrics
        withAnimation(animation(for: transition)) {
            metrics = closedMetrics(for: screen)
        }
        invalidateInteractiveRect()
    }

    func updateMouseInteraction() {
        let rect = interactiveRect()
        let mouse = NSEvent.mouseLocation
        let shouldIgnore = !ZoneMath.contains(rect, mouse)
        if shouldIgnore != lastIgnoresMouseEvents {
            applyIgnoresMouseEvents(shouldIgnore)
        }
    }

    func motionPlan(for transition: NotchMotionTransition) -> NotchMotionPlan {
        Animations.plan(for: transition, reduceMotion: isReduceMotionEnabled)
    }

    var contentShowAnimation: Animation {
        animation(for: .contentShow)
    }

    var contentHideAnimation: Animation {
        animation(for: .contentHide)
    }

    var liveActivityAnimation: Animation {
        animation(for: .liveActivity)
    }

    private func animation(for transition: NotchMotionTransition) -> Animation {
        Animations.animation(for: motionPlan(for: transition))
    }

    private func activeContentSize() -> CGSize {
        NotchContentLayout.contentSize(preferred: modules.activeModule?.preferredSize)
    }

    private func activeOpenMetrics(for screen: NotchScreen) -> NotchMetrics {
        NotchGeometry.live(for: screen, settings: settings).openMetrics(for: activeContentSize())
    }

    private func closedMetrics(for screen: NotchScreen) -> NotchMetrics {
        NotchGeometry.live(for: screen, settings: settings)
            .closedMetrics(isLiveActivityActive: modules.activeLiveActivity != nil)
    }

    private func interactiveRect() -> NSRect {
        let screen = screenProvider.targetScreen()
        if cachedInteractiveRect == nil
            || cachedPhase != state.phase
            || cachedScreenFrame != screen.frame {
            cachedInteractiveRect = InteractionRegion.interactiveRect(
                for: state.phase,
                screenFrame: screen.frame,
                notchGeom: NotchGeometry.live(for: screen, settings: settings)
            )
            cachedPhase = state.phase
            cachedScreenFrame = screen.frame
        }
        return cachedInteractiveRect ?? .zero
    }

    private func invalidateInteractiveRect() {
        cachedInteractiveRect = nil
        cachedPhase = nil
        cachedScreenFrame = nil
    }

    private func applyIgnoresMouseEvents(_ ignores: Bool) {
        lastIgnoresMouseEvents = ignores
        ignoresMouseEventsSetter(ignores)
    }

    private func subscribeToSettings() {
        settingsCancellable = settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.isStarted else { return }
                self.applySettings()
            }
        }
        settingsResetObserver = NotificationCenter.default.addObserver(
            forName: .bilouNookSettingsDidReset,
            object: settings,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isStarted else { return }
            self.applySettings()
        }
    }
}

@MainActor
final class LifecycleManager {
    static let shared = LifecycleManager()
    enum Tier { case essential, whileOpen }
    final class Token {
        fileprivate let id: UUID
        fileprivate weak var owner: LifecycleManager?
        fileprivate init(id: UUID, owner: LifecycleManager) { self.id = id; self.owner = owner }
        @MainActor func cancel() { owner?.remove(id) }
    }
    private struct Entry { let name: String; let tier: Tier; let start: () -> Void; let stop: () -> Void }
    private var entries: [UUID: Entry] = [:]
    private var running: Set<UUID> = []
    private var notchOpen = false
    private var systemAwake = true
    private var panelVisible = true
    private var observers: [NSObjectProtocol] = []
    private init() {}

    func install() {
        guard observers.isEmpty else { return }
        let ws = NSWorkspace.shared.notificationCenter
        let pairs: [(Notification.Name, Bool)] = [
            (NSWorkspace.willSleepNotification, false), (NSWorkspace.screensDidSleepNotification, false),
            (NSWorkspace.sessionDidResignActiveNotification, false), (NSWorkspace.didWakeNotification, true),
            (NSWorkspace.screensDidWakeNotification, true), (NSWorkspace.sessionDidBecomeActiveNotification, true)]
        for (name, awake) in pairs {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setSystemAwake(awake) }
            })
        }
    }

    func observeOcclusion(of window: NSWindow) {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setPanelVisible(window.occlusionState.contains(.visible)) }
        })
    }

    @discardableResult
    func register(_ name: String, tier: Tier, start: @escaping () -> Void, stop: @escaping () -> Void) -> Token {
        let id = UUID()
        entries[id] = Entry(name: name, tier: tier, start: start, stop: stop)
        evaluate(id)
        return Token(id: id, owner: self)
    }

    @discardableResult
    func timer(_ name: String, interval: TimeInterval, tolerance: TimeInterval, tier: Tier,
               fire: @escaping @MainActor () -> Void) -> Token {
        var current: Timer?
        return register(name, tier: tier, start: {
            current?.invalidate()
            let t = Timer(timeInterval: interval, repeats: true) { _ in
                MainActor.assumeIsolated { fire() }
            }
            t.tolerance = tolerance
            RunLoop.main.add(t, forMode: .common)
            current = t
        }, stop: { current?.invalidate(); current = nil })
    }

    func setNotchOpen(_ v: Bool) { guard v != notchOpen else { return }; notchOpen = v; evaluateAll() }
    func setSystemAwake(_ v: Bool) { guard v != systemAwake else { return }; systemAwake = v; evaluateAll() }
    func setPanelVisible(_ v: Bool) { guard v != panelVisible else { return }; panelVisible = v; evaluateAll() }
    var runningNames: [String] { running.compactMap { entries[$0]?.name }.sorted() }

    private func shouldRun(_ e: Entry) -> Bool { systemAwake && (e.tier == .essential || (notchOpen && panelVisible)) }
    private func evaluateAll() { for id in entries.keys { evaluate(id) } }
    private func evaluate(_ id: UUID) {
        guard let e = entries[id] else { return }
        let want = shouldRun(e)
        if want && !running.contains(id) { running.insert(id); e.start() }
        else if !want && running.contains(id) { running.remove(id); e.stop() }
    }
    private func remove(_ id: UUID) {
        if running.remove(id) != nil { entries[id]?.stop() }
        entries[id] = nil
    }
}

struct EventGate {
    var minInterval: TimeInterval
    private var last: TimeInterval = 0
    init(minInterval: TimeInterval) { self.minInterval = minInterval }
    mutating func allow(_ t: TimeInterval) -> Bool {
        if t - last >= minInterval { last = t; return true }
        return false
    }
}
