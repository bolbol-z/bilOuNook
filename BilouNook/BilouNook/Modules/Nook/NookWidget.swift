import SwiftUI

protocol NookWidget: Identifiable {
    var id: String { get }
    var preferredWidth: CGFloat { get }
    var isEnabled: Bool { get }
    var view: AnyView { get }
}

extension NookWidget {
    var isEnabled: Bool { true }
}

struct NookWidgetRow: View {
    @StateObject private var settings = SettingsStore.shared
    @Environment(\.nookRevealProgress) private var revealProgress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let widgets: [any NookWidget]

    var body: some View {
        let enabled = widgets.filter(\.isEnabled)
        let tabsOpacity = NookContentProgress.tabs(revealProgress)
        let mediaOpacity = NookContentProgress.media(revealProgress)
        let calendarOpacity = NookContentProgress.calendar(revealProgress)
        let _ = recordReveal(
            tabs: tabsOpacity,
            media: mediaOpacity,
            calendar: calendarOpacity
        )
        HStack(spacing: 0) {
            ForEach(Array(enabled.enumerated()), id: \.element.id) { index, widget in
                if index > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: NookLayout.dividerWidth, height: NookLayout.rowHeight)
                        .opacity(calendarOpacity)
                        .offset(y: NookContentProgress.offset(opacity: calendarOpacity, reduceMotion: reduceMotion))
                }
                widget.view
                    .frame(width: widget.preferredWidth, height: NookLayout.rowHeight)
                    .opacity(groupOpacity(for: widget.id, tabs: tabsOpacity, media: mediaOpacity, calendar: calendarOpacity))
                    .offset(y: NookContentProgress.offset(
                        opacity: groupOpacity(for: widget.id, tabs: tabsOpacity, media: mediaOpacity, calendar: calendarOpacity),
                        reduceMotion: reduceMotion
                    ))
                    .environment(\.nookArtworkRevealScale, widget.id == "media"
                        ? NookContentProgress.artworkScale(opacity: mediaOpacity, reduceMotion: reduceMotion)
                        : 1)
            }
        }
        .frame(height: NookLayout.rowHeight)
        .padding(.top, NookLayout.rowTop(notchHeight: notchHeight))
        .frame(maxHeight: .infinity, alignment: .top)
        .id(settings.mediaWidgetEnabled)
    }

    private func groupOpacity(for id: String, tabs: Double, media: Double, calendar: Double) -> Double {
        switch id {
        case "media": return media
        case "calendar": return calendar
        default: return tabs
        }
    }

    private func recordReveal(tabs: Double, media: Double, calendar: Double) {
        #if DEBUG
        MotionRecorder.shared.recordContent(
            progress: revealProgress,
            tabs: tabs,
            media: media,
            calendar: calendar
        )
        #endif
    }

    private var notchHeight: CGFloat {
        NotchGeometryCache.shared.current.geometry.notchRect.height
    }
}
