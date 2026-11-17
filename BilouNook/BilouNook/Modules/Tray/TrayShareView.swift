import AppKit
import SwiftUI

@MainActor
final class AirDropAnchorWindow {
    let window: NSWindow
    init() {
        let f = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let size = NSSize(width: 400, height: 2)
        let origin = NSPoint(x: f.midX - size.width / 2, y: f.midY + f.height * 0.05 - size.height / 2)
        window = NSWindow(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .transient]
    }
    func present() { window.orderFrontRegardless() }
    func dismiss() { window.orderOut(nil) }
}

@MainActor
@Observable
final class AirDropTransfer {
    static let shared = AirDropTransfer()
    enum Phase: Equatable { case idle, picker, sending, sent, failed }
    private(set) var phase: Phase = .idle
    @ObservationIgnored private var task: Task<Void, Never>?

    var isVisibleOnIsland: Bool { phase == .sending || phase == .sent || phase == .failed }

    func pickerOpened() { phase = .picker; schedule(120, from: .picker, to: .idle) }
    func began() { phase = .sending; schedule(120, from: .sending, to: .failed) }
    func finished(success: Bool) { phase = success ? .sent : .failed; schedule(1.0, from: phase, to: .idle) }
    func cancelled() { task?.cancel(); phase = .idle }

    private func schedule(_ seconds: Double, from expected: Phase, to next: Phase) {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self = self, !Task.isCancelled, self.phase == expected else { return }
            withAnimation(Animations.islandHide) { self.phase = next }
            if next == .failed { self.schedule(1.0, from: .failed, to: .idle) }
        }
    }
}

final class TrayAirDropPresenter: NSObject, NSSharingServiceDelegate {
    static let shared = TrayAirDropPresenter()

    var onFinish: ((Bool) -> Void)?
    private var service: NSSharingService?
    private var anchor: AirDropAnchorWindow?

    @MainActor
    func send(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty,
              let svc = NSSharingService(named: .sendViaAirDrop),
              svc.canPerform(withItems: urls) else { return false }
        svc.delegate = self
        service = svc
        let a = AirDropAnchorWindow()
        a.present()
        anchor = a
        AirDropTransfer.shared.pickerOpened()
        NotchHold.shared.hold(seconds: 120)
        NSApp.activate(ignoringOtherApps: true)
        svc.perform(withItems: urls)
        return true
    }

    func sharingService(_ sharingService: NSSharingService, willShareItems items: [Any]) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                NotchHold.shared.release()
                AirDropTransfer.shared.began()
                NotchState.shared.closeImmediately(reason: .system)
            }
        }
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        finish(success: true, cancelled: false)
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        let ns = error as NSError
        finish(success: false, cancelled: ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError)
    }

    func sharingService(_ sharingService: NSSharingService, sourceFrameOnScreenForShareItem item: Any) -> NSRect {
        let f = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        return NSRect(x: f.midX - 200, y: f.midY + f.height * 0.05 - 1, width: 400, height: 2)
    }

    func sharingService(
        _ sharingService: NSSharingService,
        sourceWindowForShareItems items: [Any],
        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>
    ) -> NSWindow? {
        MainActor.assumeIsolated { anchor?.window }
    }

    private func finish(success: Bool, cancelled: Bool) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                NotchHold.shared.release()
                anchor?.dismiss()
                anchor = nil
                service = nil
                if cancelled { AirDropTransfer.shared.cancelled() } else { AirDropTransfer.shared.finished(success: success) }
                onFinish?(success)
            }
        }
    }
}
