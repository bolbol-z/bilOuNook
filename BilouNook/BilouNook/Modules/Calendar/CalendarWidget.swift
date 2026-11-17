import SwiftUI

struct CalendarWidget: NookWidget {
    let id = "calendar"
    let preferredWidth: CGFloat = 224

    var isEnabled: Bool {
        SettingsStore.shared.calendarWidgetEnabled
    }

    var view: AnyView {
        AnyView(CalendarWidgetView())
    }
}
