import SwiftUI

struct MediaWidget: NookWidget {
    let id = "media"
    let preferredWidth: CGFloat = 195

    var isEnabled: Bool {
        SettingsStore.shared.mediaWidgetEnabled
    }

    var view: AnyView {
        AnyView(MediaWidgetView())
    }
}
