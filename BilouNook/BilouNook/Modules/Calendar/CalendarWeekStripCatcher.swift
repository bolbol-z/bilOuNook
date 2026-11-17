import AppKit
import SwiftUI

struct CalendarWeekStripCatcher: NSViewRepresentable {
    let onSelect: (CGFloat) -> Void
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> CalendarWeekStripNSView {
        let view = CalendarWeekStripNSView()
        view.onSelect = onSelect
        view.onScroll = onScroll
        view.onHover = { hovering in
            if hovering {
                GestureMonitor.shared.acquireGestureOwner(CalendarWeekStripNSView.owner)
            } else {
                GestureMonitor.shared.releaseGestureOwner(CalendarWeekStripNSView.owner)
            }
        }
        return view
    }

    func updateNSView(_ nsView: CalendarWeekStripNSView, context: Context) {
        nsView.onSelect = onSelect
        nsView.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: CalendarWeekStripNSView, coordinator: ()) {
        GestureMonitor.shared.releaseGestureOwner(CalendarWeekStripNSView.owner)
    }
}

final class CalendarWeekStripNSView: NSView {
    static let owner = "calendar.weekStrip"

    var onSelect: ((CGFloat) -> Void)?
    var onScroll: ((CGFloat) -> Void)?
    var onHover: ((Bool) -> Void)?
    private var trackingAreaReference: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(convert(event.locationInWindow, from: nil).x)
    }

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }
        onScroll?(event.scrollingDeltaX)
    }
}
