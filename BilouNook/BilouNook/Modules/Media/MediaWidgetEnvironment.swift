import SwiftUI

private struct NowPlayingServiceEnvironmentKey: EnvironmentKey {
    static let defaultValue = NowPlayingService.shared
}

private struct MediaSourceAppOverrideKey: EnvironmentKey {
    static let defaultValue: MediaSourceApp? = nil
}

extension EnvironmentValues {
    var nowPlayingService: NowPlayingService {
        get { self[NowPlayingServiceEnvironmentKey.self] }
        set { self[NowPlayingServiceEnvironmentKey.self] = newValue }
    }

    var mediaSourceAppOverride: MediaSourceApp? {
        get { self[MediaSourceAppOverrideKey.self] }
        set { self[MediaSourceAppOverrideKey.self] = newValue }
    }
}
