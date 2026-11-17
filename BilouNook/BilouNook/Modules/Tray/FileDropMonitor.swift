import AppKit

/// Detects native file drags anywhere on screen and asks the notch to open
/// when the pointer is over the notch interaction area.
///
/// A closed notch is mouse-transparent, so a file dragged over it is
/// invisible to the panel itself. This monitor watches left-mouse drags and
/// asks the system what the drag actually carries, then expands the notch so
/// a visible drop zone is served by the panel.
///
/// One expansion per drag session: `isActive` flips back to false on
/// `.leftMouseUp`, which terminates the drag session.
final class FileDropMonitor {
    static let shared = FileDropMonitor()

    /// True while the pointer is dragging files and we expanded the notch.
    private(set) var isActive = false

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var cachedDragChangeCount: Int = -1
    private var cachedDragHasFileURL = false

    func start() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        isActive = false
    }

    /// Clears the "drag session active" flag. Called when the drop completes
    /// or the drag ends; the notch stays open so the user can see the tray.
    func reset() {
        isActive = false
        updateClickThrough()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseUp:
            isActive = false
            updateClickThrough()
        case .leftMouseDragged:
            guard !isActive else { return }
            let snapshot = MainActor.assumeIsolated { NotchGeometryCache.shared.current }
            let hot = InteractionRegion.hotZone(
                screenFrame: snapshot.screen.frame,
                notchGeom: snapshot.geometry
            )
            guard ZoneMath.contains(hot, NSEvent.mouseLocation) else { return }
            guard carriesFileURLsCached() else { return }

            isActive = true
            MainActor.assumeIsolated {
                NotchState.shared.requestOpen(trigger: .drag)
                ModuleRegistry.shared.select(id: "files")
            }
            setPanelClickThrough(false)
        default:
            break
        }
    }

    /// After the drag ends, re-derive the click-through state the same way
    /// the coordinator does on regular mouse moves: clicks pass only inside
    /// the phase-correct interaction rectangle.
    private func updateClickThrough() {
        let snapshot = MainActor.assumeIsolated { NotchGeometryCache.shared.current }
        let phase = MainActor.assumeIsolated { NotchState.shared.phase }
        let rect = InteractionRegion.interactiveRect(
            for: phase,
            screenFrame: snapshot.screen.frame,
            notchGeom: snapshot.geometry
        )
        setPanelClickThrough(!ZoneMath.contains(rect, NSEvent.mouseLocation))
    }

    private func setPanelClickThrough(_ ignores: Bool) {
        if let panel = NSApplication.shared.windows.lazy.compactMap({ $0 as? NotchPanel }).first {
            panel.ignoresMouseEvents = ignores
        }
    }

    /// Answers true when the current drag session carries file URLs. The
    /// clipboard is checked before the notch expands so an unrelated draggable
    /// never opens the notch. The result is cached per pasteboard changeCount
    /// so the types are not re-read on every drag event.
    static func carriesFileURLs() -> Bool {
        let types = NSPasteboard(name: .drag).types ?? []
        guard !types.isEmpty else { return false }
        return types.contains(.fileURL) || types.contains(.fileContents)
    }

    private func carriesFileURLsCached() -> Bool {
        let pasteboard = NSPasteboard(name: .drag)
        let changeCount = pasteboard.changeCount
        if changeCount == cachedDragChangeCount { return cachedDragHasFileURL }
        let types = pasteboard.types ?? []
        cachedDragHasFileURL = !types.isEmpty
            && (types.contains(.fileURL) || types.contains(.fileContents))
        cachedDragChangeCount = changeCount
        return cachedDragHasFileURL
    }
}
