import SwiftUI

struct NookModule: NotchModule {
    let id = "nook"
    let title = "Nook"
    let icon = "lamp.desk.fill"
    let liveActivityPriority = 10

    var widgets: [any NookWidget] {
        [MediaWidget(), CalendarWidget()]
    }

    var preferredSize: CGSize {
        NookLayout.preferredSize(
            widgets: widgets,
            notchHeight: NotchGeometryCache.shared.current.geometry.notchRect.height
        )
    }

    var isLiveActivityActive: Bool {
        MainActor.assumeIsolated { IslandModel.shared.isActive }
    }

    var liveActivity: AnyView? {
        AnyView(IslandView())
    }

    var expandedView: AnyView {
        AnyView(NookWidgetRow(widgets: widgets))
    }
}
