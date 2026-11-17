import SwiftUI

struct ModuleShellView: View {
    @State private var registry: ModuleRegistry
    @Environment(\.nookRevealProgress) private var revealProgress
    @Namespace private var tabPillNamespace

    init(registry: ModuleRegistry = .shared) {
        _registry = State(initialValue: registry)
    }

    var body: some View {
        shell
            .overlay(alignment: .topTrailing) { TimerBandBadge(activeModuleID: registry.activeModuleID).padding(.trailing, 40).padding(.top, 6) }
    }

    private var shell: some View {
        ZStack(alignment: .top) {
            tabContent
            moduleTabBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            GestureMonitor.shared.onHorizontalSwipe = { direction in
                switchModules(direction)
            }
        }
        .onDisappear {
            GestureMonitor.shared.onHorizontalSwipe = nil
        }
    }

    private var tabContent: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var geometry: NotchGeometry {
        NotchGeometryCache.shared.current.geometry
    }

    private var moduleTabLayout: ModuleTabLayout {
        let shapeWidth = registry.activeModule?.preferredSize.width ?? NotchPresets.open.w
        return ModuleTabLayout(
            pillWidths: registry.enabledModules.map { TabPillMetrics.width(title: $0.title) },
            shapeWidth: shapeWidth,
            geometry: geometry
        )
    }

    private var moduleTabBar: some View {
        let modules = registry.enabledModules
        let layout = moduleTabLayout
        return ZStack(alignment: .topLeading) {
            ForEach(Array(modules.enumerated()), id: \.element.id) { index, module in
                if layout.pillFrames.indices.contains(index) {
                    let frame = layout.pillFrames[index]
                    tabButton(
                        module: module,
                        size: frame.size,
                        iconOnly: layout.usesIconFallback
                    )
                    .position(x: frame.midX, y: frame.midY)
                }
            }
            if layout.gearFrame != .zero {
                gearButton
                    .position(x: layout.gearFrame.midX, y: layout.gearFrame.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(NookContentProgress.tabs(revealProgress))
        .allowsHitTesting(true)
        .onDisappear {
            #if DEBUG
            MotionRecorder.shared.recordContent(progress: 0, tabs: 0, media: 0, calendar: 0)
            #endif
        }
    }

    private var gearButton: some View {
        Button {
            SettingsWindow.shared.show()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.7))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Settings")
        .layoutProbe("band.gear")
    }

    private func tabButton(module: any NotchModule, size: CGSize, iconOnly: Bool) -> some View {
        let selected = module.id == registry.activeModuleID
        return Button {
            select(module)
        } label: {
            HStack(spacing: TabPillMetrics.iconGap) {
                Image(systemName: module.icon)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.semibold)
                    .frame(width: TabPillMetrics.iconSize, height: TabPillMetrics.iconSize)
                if !iconOnly {
                    Text(module.title)
                        .font(.system(size: TabPillMetrics.labelSize, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(Color.white.opacity(selected ? 1 : 0.85))
            .padding(.horizontal, TabPillMetrics.horizontalPadding)
            .frame(width: size.width, height: size.height)
            .background {
                if selected {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .matchedGeometryEffect(id: "module-tab-pill", in: tabPillNamespace)
                }
            }
        }
        .buttonStyle(.plain)
        .help(module.title)
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .animation(Animations.tabPill, value: selected)
        .layoutProbe("band.pill.\(module.id)")
    }

    private var content: some View {
        ZStack {
            if let module = registry.activeModule {
                module.expandedView
                    .id(module.id)
                    .transition(moduleTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .offset(x: TabSwipeController.shared.liveOffset)
        .opacity(1.0 - min(abs(TabSwipeController.shared.liveOffset) / 120.0, 0.5))
        .layoutProbe("open.content")
    }

    private var moduleTransition: AnyTransition {
        let offset = CGFloat(registry.transitionDirection) * 18
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: offset)),
            removal: .opacity.combined(with: .offset(x: -offset))
        )
    }

    private func select(_ module: any NotchModule) {
        guard module.id != registry.activeModuleID else { return }
        withAnimation(Animations.animation(for: .moduleContent)) {
            registry.select(id: module.id)
        }
    }

    private func switchModules(_ direction: Int) {
        withAnimation(Animations.animation(for: .moduleContent)) {
            if direction > 0 {
                registry.selectNext()
            } else {
                registry.selectPrevious()
            }
        }
    }
}
