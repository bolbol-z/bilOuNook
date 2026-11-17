import SwiftUI
import AppKit

struct LayoutProbeKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

#if DEBUG
enum LayoutProbeConfig {
    /// Layout probes add a GeometryReader + preference to every probed view and update every frame while animating.
    /// Enabled only when capturing layouts: launch with --layout-autocapture or set BILOUNOOK_LAYOUT_PROBE=1.
    static let isEnabled: Bool =
        CommandLine.arguments.contains("--layout-autocapture")
        || ProcessInfo.processInfo.environment["BILOUNOOK_LAYOUT_PROBE"] == "1"
}
#endif

final class LayoutProbeStore {
    static let shared = LayoutProbeStore()
    private let lock = NSLock()
    private var frames: [String: CGRect] = [:]
    func set(_ f: [String: CGRect]) { lock.lock(); frames = f; lock.unlock() }
    func all() -> [String: CGRect] { lock.lock(); defer { lock.unlock() }; return frames }
}

extension View {
    @ViewBuilder
    func layoutProbe(_ name: String) -> some View {
        #if DEBUG
        if LayoutProbeConfig.isEnabled {
            self.background(GeometryReader { geo in
                Color.clear.preference(key: LayoutProbeKey.self, value: [name: geo.frame(in: .global)])
            })
        } else {
            self
        }
        #else
        self
        #endif
    }
    @ViewBuilder
    func layoutProbeCollector() -> some View {
        #if DEBUG
        if LayoutProbeConfig.isEnabled {
            self.onPreferenceChange(LayoutProbeKey.self) { LayoutProbeStore.shared.set($0) }
        } else {
            self
        }
        #else
        self
        #endif
    }
}

@MainActor
struct NotchRootView: View {
    @State private var coordinator: NotchCoordinator
    @State private var notchState: NotchState
    @StateObject private var settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var modules: ModuleRegistry
    #if DEBUG
    @State private var calibration = NotchCalibrationState.shared
    #endif
    private let isPreview: Bool

    init(panel: NSPanel) {
        self.init(coordinator: NotchCoordinator(panel: panel))
    }

    init(coordinator: NotchCoordinator, isPreview: Bool = false, registry: ModuleRegistry = .shared) {
        _coordinator = State(initialValue: coordinator)
        _notchState = State(initialValue: coordinator.state)
        _modules = State(initialValue: registry)
        self.isPreview = isPreview
    }

    #if DEBUG
    init(
        panel: NSPanel,
        previewMetrics: NotchMetrics,
        previewShowContent: Bool,
        registry: ModuleRegistry = .shared
    ) {
        let coordinator = NotchCoordinator.preview(
            panel: panel,
            metrics: previewMetrics,
            showContent: previewShowContent
        )
        _coordinator = State(initialValue: coordinator)
        _notchState = State(initialValue: coordinator.state)
        _modules = State(initialValue: registry)
        self.isPreview = true
    }
    #endif

    private var metrics: NotchMetrics { coordinator.metrics }

    private var contentSize: CGSize { coordinator.contentSize }

    private var canvasSize: CGSize {
        let size = coordinator.panel?.frame.size ?? .zero
        guard size.width > 0, size.height > 0 else {
            return CGSize(width: 700, height: 320)
        }
        return size
    }

    private var closedOverlays: some View {
        NotchClosedOverlays(
            settings: settings,
            modules: modules,
            phase: notchState.phase,
            metrics: metrics,
            liveActivityAnimation: coordinator.liveActivityAnimation
        )
    }

    private var presentation: NotchPresentationMode {
        NotchGeometryCache.shared.current.geometry.presentationMode
    }

    private var hardwareNotchRect: CGRect? {
        NotchGeometryCache.shared.current.geometry.hardwareNotchRect
    }

    private var isOpenish: Bool {
        notchState.phase == .open || notchState.phase == .opening
    }

    private var shapeMetrics: NotchMetrics {
        let mode = presentation
        let t = NotchPresentationStyle.topRadius(base: metrics.t, userFlare: CGFloat(settings.topFlareRadius))
        let b = NotchPresentationStyle.bottomRadius(mode: mode, base: metrics.b, isOpen: isOpenish)
        if mode == .edgePinned && isOpenish {
            return NotchMetrics(w: contentSize.width, h: contentSize.height, t: t, b: b)
        }
        return NotchMetrics(w: metrics.w, h: metrics.h, t: t, b: b)
    }

    private var restingShapeOpacity: Double {
        if presentation == .ownDynamicIsland { return 1 }
        return (notchState.phase == .closed && !IslandModel.shared.isActive) ? 0 : 1
    }

    private var edgeSlideAnimation: Animation {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        return Animations.animation(for: isOpenish ? .openMetrics : .closeMetrics, reduceMotion: reduce)
    }

    private func shapeView(_ m: NotchMetrics) -> some View {
        NotchShape(width: m.w, height: m.h, topCornerRadius: m.t, bottomCornerRadius: m.b)
            .fill(NotchPresentationStyle.fill(for: presentation, isDark: colorScheme == .dark))
            #if DEBUG
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: NotchShapeFramePreferenceKey.self,
                        value: proxy.frame(in: .named("notchRoot"))
                    )
                }
            }
            #endif
            .layoutProbe("closed.shape")
            .onTapGesture {
                notchState.click()
            }
    }

    @ViewBuilder
    private func contentLayer(_ m: NotchMetrics) -> some View {
        if isPreview || (coordinator.isContentMounted || ContentPrewarm.shared.isWarm) {
            NookContentRevealHost(isOpen: isOpenish) {
                ModuleShellView(registry: modules)
                    .frame(width: contentSize.width, height: contentSize.height)
            }
            .opacity(coordinator.showContent ? 1 : 0)
            .animation(
                coordinator.showContent ? nil : .easeOut(duration: 0.10),
                value: coordinator.showContent
            )
            .frame(width: m.w, height: m.h, alignment: .top)
            .mask(
                NotchShape(width: m.w, height: m.h, topCornerRadius: m.t, bottomCornerRadius: m.b, recordsMotion: false)
                    .layoutProbe("open.shape")
            )
            .animation(
                Animations.animation(
                    for: coordinator.showContent ? .openMetrics : .closeMetrics,
                    reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ),
                value: coordinator.showContent
            )
        }
    }

    @ViewBuilder
    private var standardLayers: some View {
        let m = shapeMetrics
        shapeView(m)
            .opacity(restingShapeOpacity)
            .animation(Animations.islandContent, value: restingShapeOpacity)
        contentLayer(m)
        if presentation == .mergedWithPhysical, let n = hardwareNotchRect, isOpenish {
            Rectangle()
                .fill(Color.white.opacity(NotchPresentationStyle.hairlineOpacity))
                .frame(width: n.width, height: 1)
                .offset(y: n.height - 0.5)
                .opacity(coordinator.showContent ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: coordinator.showContent)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var edgePinnedLayers: some View {
        let m = shapeMetrics
        if isOpenish {
            ZStack(alignment: .top) {
                shapeView(m)
                contentLayer(m)
            }
            .frame(width: m.w, height: m.h, alignment: .top)
            .transition(.move(edge: .top))
        } else {
            shapeView(m)
                .opacity(IslandModel.shared.isActive ? 1 : 0)
                .animation(Animations.islandContent, value: IslandModel.shared.isActive)
        }
    }

    private var notchContent: some View {
        ZStack(alignment: .top) {
            if presentation == .edgePinned {
                edgePinnedLayers
                    .animation(edgeSlideAnimation, value: isOpenish)
            } else {
                standardLayers
            }
            closedOverlays
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .notchContextMenu(state: notchState)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .contentShape(Rectangle())

            notchContent
            #if DEBUG
            NotchCalibrationLayer(
                isVisible: calibration.isVisible,
                coordinator: coordinator,
                settings: settings,
                canvasSize: canvasSize
            )
            #endif
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        #if DEBUG
        .coordinateSpace(name: "notchRoot")
        .onPreferenceChange(NotchShapeFramePreferenceKey.self) { frame in
            NotchShapeProbe.frameInRoot = frame
        }
        #endif
        .onAppear(perform: handleAppear)
        .onDisappear { coordinator.stop() }
        .onChange(of: notchState.phase) { oldPhase, newPhase in
            coordinator.phaseDidChange(from: oldPhase, to: newPhase)
        }
        .onChange(of: modules.activeModuleID) { _, _ in
            coordinator.activeModuleDidChange()
        }
        .onChange(of: modules.activeLiveActivity?.id) { _, _ in
            coordinator.liveActivityDidChange()
        }
        .layoutProbeCollector()
    }

    private func handleAppear() {
        guard !isPreview else { return }
        coordinator.start()
        #if DEBUG
        if let panel = coordinator.panel,
           let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            DebugTools.install(
                appDelegate: appDelegate,
                panel: panel,
                state: notchState,
                mouseMonitor: MouseMonitor.shared,
                gestureMonitor: GestureMonitor.shared,
                watchdog: Watchdog.shared
            )
        } else {
            HotKeyManager.shared.register()
            AnimationLabWindow.shared.state = notchState
        }
        #endif
    }
}

enum NotchContentLayout {
    static func contentSize(preferred: CGSize?) -> CGSize {
        preferred ?? CGSize(width: NotchPresets.open.w, height: NotchPresets.open.h)
    }
}

#if DEBUG
enum NotchShapeProbe {
    static var frameInRoot: CGRect?
}

struct NotchShapeFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
#endif
