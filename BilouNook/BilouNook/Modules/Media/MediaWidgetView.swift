import AppKit
import SwiftUI

enum MediaWidgetInteraction {
    static func showsScrubber(isHovering: Bool, isSeekable: Bool) -> Bool {
        isHovering && isSeekable
    }
}

enum MediaWidgetLabels {
    static let previous = "Previous track"
    static let next = "Next track"
    static let playbackPosition = "Playback position"

    static func playPause(isPlaying: Bool) -> String {
        isPlaying ? "Pause" : "Play"
    }
}

struct MediaWidgetView: View {
    @Environment(\.nowPlayingService) private var service
    @Environment(\.mediaSourceAppOverride) private var sourceAppOverride
    @State private var sourceApp: MediaSourceApp?
    @State private var isHovering = false
    @Environment(\.nookArtworkRevealScale) private var artworkRevealScale
    private let hoverOverride: Bool?

    init(hoverOverride: Bool? = nil) {
        self.hoverOverride = hoverOverride
    }

    private var hovering: Bool { hoverOverride ?? isHovering }

    var body: some View {
        let state = MediaViewState(snapshot: service.snapshot)

        ZStack(alignment: .topLeading) {
            switch state {
            case .empty:
                emptyState
            case .track(let presentation):
                trackView(presentation)
            }
        }
        .frame(width: MediaWidgetMetrics.width, height: MediaWidgetMetrics.height, alignment: .topLeading)
        .onHover { isHovering = $0 }
        .task(id: metadataKey(for: state)) {
            await loadMetadata(for: state)
        }
        .layoutProbe("nook.media")
    }

    private func trackView(_ presentation: MediaPresentation) -> some View {
        ZStack(alignment: .topLeading) {
            artwork(presentation).layoutProbe("nook.artwork")

            if let sourceApp = sourceAppOverride ?? sourceApp {
                MediaWidgetSourceBadge(app: sourceApp)
                    .position(
                        x: MediaWidgetMetrics.badgeFrame.midX,
                        y: MediaWidgetMetrics.badgeFrame.midY
                    )
            }

            textRows(presentation).layoutProbe("nook.title")
            controls(presentation).layoutProbe("nook.controls")

            if MediaWidgetInteraction.showsScrubber(
                isHovering: hovering,
                isSeekable: presentation.isSeekable
            ) {
                MediaWidgetScrubber(presentation: presentation, onSeek: seek)
                    .transition(.opacity)
                    .id(presentation.trackIdentity)
                    .layoutProbe("nook.scrubber")
            }
        }
        .animation(MediaMotion.respectingReduceMotion(MediaMotion.scrubberFade, reduceMotion: reduceMotion), value: hovering)
        .animation(
            MediaMotion.respectingReduceMotion(.easeOut(duration: 0.12), reduceMotion: reduceMotion),
            value: presentation.trackIdentity
        )
    }

    private var emptyState: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: MediaWidgetMetrics.artworkCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: MediaWidgetMetrics.artworkSize, height: MediaWidgetMetrics.artworkSize)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                .position(x: MediaWidgetMetrics.artworkFrame.midX, y: MediaWidgetMetrics.artworkFrame.midY)

            MarqueeText(
                text: MediaWidgetMetrics.emptyTitle,
                font: .system(size: MediaWidgetMetrics.titleFontSize, weight: .semibold),
                color: Color.white.opacity(0.55),
                height: MediaWidgetMetrics.titleHeight
            )
            .frame(width: MediaWidgetMetrics.textColumnWidth, height: MediaWidgetMetrics.titleHeight)
            .position(x: MediaWidgetMetrics.titleFrame.midX, y: MediaWidgetMetrics.titleFrame.midY)

            MarqueeText(
                text: MediaWidgetMetrics.emptyMessage,
                font: .system(size: MediaWidgetMetrics.artistFontSize, weight: .regular),
                color: Color.white.opacity(0.35),
                height: MediaWidgetMetrics.artistHeight
            )
            .frame(width: MediaWidgetMetrics.textColumnWidth, height: MediaWidgetMetrics.artistHeight)
            .position(x: MediaWidgetMetrics.albumFrame.midX, y: MediaWidgetMetrics.albumFrame.midY)
        }
    }

    private func artwork(_ presentation: MediaPresentation) -> some View {
        ArtworkCrossfade(identity: presentation.artworkIdentity) {
            ArtworkThumbnailView(
                artwork: presentation.artwork,
                identity: presentation.artworkIdentity,
                displaySize: MediaWidgetMetrics.artworkSize,
                cornerRadius: MediaWidgetMetrics.artworkCornerRadius
            )
            .scaleEffect((presentation.isPlaying ? 1 : 0.92) * artworkRevealScale)
            .animation(
                MediaMotion.respectingReduceMotion(MediaMotion.artworkSpring, reduceMotion: reduceMotion),
                value: presentation.isPlaying
            )
            .position(x: MediaWidgetMetrics.artworkFrame.midX, y: MediaWidgetMetrics.artworkFrame.midY)
        }
    }

    private func textRows(_ presentation: MediaPresentation) -> some View {
        ZStack(alignment: .topLeading) {
            MarqueeText(
                text: presentation.title.isEmpty ? "Unknown Track" : presentation.title,
                font: .system(size: MediaWidgetMetrics.titleFontSize, weight: .semibold),
                color: Color.white.opacity(MediaWidgetMetrics.titleOpacity),
                height: MediaWidgetMetrics.titleHeight
            )
            .frame(width: MediaWidgetMetrics.textColumnWidth, height: MediaWidgetMetrics.titleHeight)
            .position(x: MediaWidgetMetrics.titleFrame.midX, y: MediaWidgetMetrics.titleFrame.midY)

            if !presentation.album.isEmpty {
                MarqueeText(
                    text: presentation.album,
                    font: .system(size: MediaWidgetMetrics.albumFontSize, weight: .semibold),
                    color: Color.white.opacity(MediaWidgetMetrics.albumOpacity),
                    height: MediaWidgetMetrics.albumHeight
                )
                .frame(width: MediaWidgetMetrics.textColumnWidth, height: MediaWidgetMetrics.albumHeight)
                .position(x: MediaWidgetMetrics.albumFrame.midX, y: MediaWidgetMetrics.albumFrame.midY)
            }

            if !presentation.artist.isEmpty {
                MarqueeText(
                    text: presentation.artist,
                    font: .system(size: MediaWidgetMetrics.artistFontSize, weight: .regular),
                    color: Color.white.opacity(MediaWidgetMetrics.artistOpacity),
                    height: MediaWidgetMetrics.artistHeight
                )
                .frame(width: MediaWidgetMetrics.textColumnWidth, height: MediaWidgetMetrics.artistHeight)
                .position(x: MediaWidgetMetrics.artistFrame.midX, y: MediaWidgetMetrics.artistFrame.midY)
            }
        }
        .id(presentation.trackIdentity)
        .transition(.opacity)
    }

    private func controls(_ presentation: MediaPresentation) -> some View {
        ZStack(alignment: .topLeading) {
            MediaWidgetControlButton(
                systemName: "backward.fill",
                label: MediaWidgetLabels.previous,
                action: previous
            )
            .position(
                x: MediaWidgetMetrics.controlFrames[0].midX,
                y: MediaWidgetMetrics.controlFrames[0].midY
            )

            MediaWidgetControlButton(
                systemName: presentation.playPauseSymbol,
                label: MediaWidgetLabels.playPause(isPlaying: presentation.isPlaying),
                action: togglePlayPause
            )
            .position(
                x: MediaWidgetMetrics.controlFrames[1].midX,
                y: MediaWidgetMetrics.controlFrames[1].midY
            )

            MediaWidgetControlButton(
                systemName: "forward.fill",
                label: MediaWidgetLabels.next,
                action: next
            )
            .position(
                x: MediaWidgetMetrics.controlFrames[2].midX,
                y: MediaWidgetMetrics.controlFrames[2].midY
            )
        }
    }

    private func previous() {
        guard case .track(let presentation) = MediaViewState(snapshot: service.snapshot) else { return }
        let elapsed = MediaPlaybackAnchor(presentation: presentation, now: Date())
            .elapsed(at: Date(), duration: presentation.duration)
        switch MediaTransport.previousAction(elapsed: elapsed) {
        case .restartTrack:
            service.seek(to: 0)
        case .previousTrack:
            service.previous()
        }
    }

    private func togglePlayPause() {
        service.togglePlayPause()
    }

    private func next() {
        service.next()
    }

    private func seek(to target: TimeInterval) {
        guard case .track(let presentation) = MediaViewState(snapshot: service.snapshot) else { return }
        let current = MediaPlaybackAnchor(presentation: presentation, now: Date())
            .elapsed(at: Date(), duration: presentation.duration)
        service.seek(to: target)
        #if DEBUG
        MediaSeekDebugLog.begin(
            track: presentation.title,
            from: current,
            target: target,
            service: service
        )
        #endif
    }

    private func metadataKey(for state: MediaViewState) -> String {
        guard case .track(let presentation) = state else { return "empty" }
        return "\(presentation.bundleIdentifier)#\(presentation.parentBundleIdentifier ?? "")#\(presentation.artworkIdentity)"
    }

    @MainActor
    private func loadMetadata(for state: MediaViewState) async {
        guard case .track(let presentation) = state else {
            sourceApp = nil
            return
        }
        sourceApp = SourceAppInfoCache.shared.info(
            for: presentation.bundleIdentifier,
            parentBundleIdentifier: presentation.parentBundleIdentifier
        )
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
}

private struct MediaWidgetSourceBadge: View {
    let app: MediaSourceApp

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: MediaWidgetMetrics.badgeCornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.88))

            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: MediaWidgetMetrics.badgeCornerRadius, style: .continuous))
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .frame(width: MediaWidgetMetrics.badgeSize, height: MediaWidgetMetrics.badgeSize)
        .accessibilityLabel(app.name)
    }
}

private struct MediaWidgetControlButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: MediaWidgetMetrics.controlSymbolSize, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(Color.white.opacity(0.88 + (isHovering ? InteractionMotion.hoverBrighten : 0)))
                .frame(
                    width: MediaWidgetMetrics.controlHitSize.width,
                    height: MediaWidgetMetrics.controlHitSize.height
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(MediaWidgetPressStyle(reduceMotion: reduceMotion))
        .onHover { isHovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct MediaWidgetPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(
                MediaMotion.respectingReduceMotion(MediaMotion.controlSpring, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

private struct MediaWidgetScrubber: View {
    let presentation: MediaPresentation
    let onSeek: (TimeInterval) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var anchor: MediaPlaybackAnchor
    @State private var dragFraction: Double?

    init(presentation: MediaPresentation, onSeek: @escaping (TimeInterval) -> Void) {
        self.presentation = presentation
        self.onSeek = onSeek
        _anchor = State(initialValue: MediaPlaybackAnchor(presentation: presentation, now: Date()))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: dragFraction != nil || !presentation.isPlaying)) { context in
            let fraction = displayedFraction(at: context.date)
            let trackWidth = MediaWidgetMetrics.scrubberTrackFrame.width
            let localTrackY = MediaWidgetMetrics.scrubberTrackFrame.minY - MediaWidgetMetrics.scrubberHitFrame.minY
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: trackWidth, height: MediaWidgetMetrics.scrubberTrackHeight)
                    .offset(y: localTrackY)

                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: trackWidth * fraction, height: MediaWidgetMetrics.scrubberTrackHeight)
                    .offset(y: localTrackY)

                if dragFraction != nil {
                    Text(MediaFormatting.time(displayedElapsed(at: context.date)))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Color.black.opacity(0.84))
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(Capsule().fill(Color.white.opacity(0.94)))
                        .fixedSize()
                        .offset(
                            x: min(max(trackWidth * fraction - 18, 0), trackWidth - 36),
                            y: localTrackY - 19
                        )
                }
            }
            .frame(
                width: MediaWidgetMetrics.scrubberHitFrame.width,
                height: MediaWidgetMetrics.scrubberHitFrame.height,
                alignment: .topLeading
            )
            .contentShape(Rectangle())
            .gesture(seekGesture)
        }
        .frame(
            width: MediaWidgetMetrics.scrubberHitFrame.width,
            height: MediaWidgetMetrics.scrubberHitFrame.height
        )
        .position(x: MediaWidgetMetrics.scrubberHitFrame.midX, y: MediaWidgetMetrics.scrubberHitFrame.midY)
        .accessibilityElement()
        .accessibilityLabel(MediaWidgetLabels.playbackPosition)
        .accessibilityValue(MediaFormatting.time(displayedElapsed(at: Date())))
        .accessibilityAdjustableAction { direction in
            let step = max(1, presentation.duration * 0.02)
            let current = displayedElapsed(at: Date())
            switch direction {
            case .increment:
                onSeek(min(presentation.duration, current + step))
            case .decrement:
                onSeek(max(0, current - step))
            @unknown default:
                break
            }
        }
    }

    private var seekGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dragFraction = clampedFraction(value.location.x)
                }
            }
            .onEnded { value in
                let fraction = clampedFraction(value.location.x)
                let target = presentation.duration * fraction
                // One main-actor turn: the service seeks, publishes the
                // optimistic snapshot and re-anchors; only then do we drop
                // the drag state — no snap-back frame can render.
                onSeek(target)
                var transaction = Transaction(animation: nil)
                withTransaction(transaction) {
                    anchor = MediaPlaybackAnchor(
                        elapsedAtAnchor: target,
                        anchorDate: Date(),
                        isPlaying: presentation.isPlaying
                    )
                    dragFraction = nil
                }
            }
    }

    private func clampedFraction(_ x: CGFloat) -> Double {
        let width = MediaWidgetMetrics.scrubberHitFrame.width
        return min(max(Double(x / max(1, width)), 0), 1)
    }

    private func displayedFraction(at date: Date) -> Double {
        if let dragFraction { return dragFraction }
        return anchor.progress(duration: presentation.duration, at: date)
    }

    private func displayedElapsed(at date: Date) -> TimeInterval {
        if let dragFraction { return presentation.duration * dragFraction }
        return anchor.elapsed(at: date, duration: presentation.duration)
    }
}

struct ArtworkCrossfade<Content: View>: View {
    let identity: String
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack { content().id(identity).transition(.opacity) }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: identity)
    }
}
