import AppKit

struct NotchGeometrySnapshot {
    let screen: NotchScreen
    let geometry: NotchGeometry
    let menuBarHeight: CGFloat
    let backingScale: CGFloat
}

@MainActor
final class NotchGeometryCache {
    static let shared = NotchGeometryCache()

    private let screenProvider: ScreenProviding
    private let settingsProvider: () -> SettingsStore
    private let menuBarHeightProvider: () -> CGFloat
    private let notificationCenter: NotificationCenter
    private let workspaceCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var cached: NotchGeometrySnapshot?

    init(
        screenProvider: ScreenProviding = SystemScreenProvider(),
        settings: @escaping () -> SettingsStore = { SettingsStore.shared },
        menuBarHeight: @escaping () -> CGFloat = { NSStatusBar.system.thickness },
        notificationCenter: NotificationCenter = .default,
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.screenProvider = screenProvider
        self.settingsProvider = settings
        self.menuBarHeightProvider = menuBarHeight
        self.notificationCenter = notificationCenter
        self.workspaceCenter = workspaceCenter
        observe()
    }

    deinit {
        MainActor.assumeIsolated {
            stopObserving()
        }
    }

    nonisolated var current: NotchGeometrySnapshot {
        MainActor.assumeIsolated {
            resolveIfNeeded()
        }
    }

    func invalidate() {
        cached = nil
    }

    private func resolveIfNeeded() -> NotchGeometrySnapshot {
        if let cached { return cached }
        let screen = screenProvider.targetScreen()
        let snapshot = NotchGeometrySnapshot(
            screen: screen,
            geometry: NotchGeometry.live(for: screen, settings: settingsProvider()).withIslandStyle(settingsProvider().showDynamicIslandStyle),
            menuBarHeight: menuBarHeightProvider(),
            backingScale: screen.backingScaleFactor
        )
        Animations.presentationMode = snapshot.geometry.presentationMode
        cached = snapshot
        return snapshot
    }

    private func observe() {
        let sources: [(NotificationCenter, Notification.Name)] = [
            (notificationCenter, NSApplication.didChangeScreenParametersNotification),
            (workspaceCenter, NSWorkspace.screensDidWakeNotification),
            (workspaceCenter, NSWorkspace.didWakeNotification),
            (workspaceCenter, NSWorkspace.activeSpaceDidChangeNotification)
        ]
        for (center, name) in sources {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.invalidate()
                }
            })
        }
    }

    private func stopObserving() {
        for observer in observers {
            notificationCenter.removeObserver(observer)
            workspaceCenter.removeObserver(observer)
        }
        observers.removeAll()
    }
}
