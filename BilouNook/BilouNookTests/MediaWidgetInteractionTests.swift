import XCTest

final class MediaWidgetInteractionTests: XCTestCase {
    func testScrubberOnlyShowsWhileHoveringASeekableTrack() {
        XCTAssertTrue(MediaWidgetInteraction.showsScrubber(isHovering: true, isSeekable: true))
        XCTAssertFalse(MediaWidgetInteraction.showsScrubber(isHovering: false, isSeekable: true))
        XCTAssertFalse(MediaWidgetInteraction.showsScrubber(isHovering: true, isSeekable: false))
        XCTAssertFalse(MediaWidgetInteraction.showsScrubber(isHovering: false, isSeekable: false))
    }

    func testUnknownDurationKeepsTheScrubberHidden() {
        let unknown = NowPlayingSnapshot(title: "Live Radio", duration: 0)
        guard case .track(let presentation) = MediaViewState(snapshot: unknown) else {
            return XCTFail("expected a track")
        }
        XCTAssertFalse(presentation.isSeekable)
        XCTAssertFalse(MediaWidgetInteraction.showsScrubber(isHovering: true, isSeekable: presentation.isSeekable))
    }

    func testWidgetMatchesTheMetricsWidth() {
        XCTAssertEqual(MediaWidget().preferredWidth, MediaWidgetMetrics.width)
    }

    func testTransportLabelsTrackPlaybackState() {
        XCTAssertEqual(MediaWidgetLabels.playPause(isPlaying: true), "Pause")
        XCTAssertEqual(MediaWidgetLabels.playPause(isPlaying: false), "Play")
        XCTAssertEqual(MediaWidgetLabels.previous, "Previous track")
        XCTAssertEqual(MediaWidgetLabels.next, "Next track")
        XCTAssertEqual(MediaWidgetLabels.playbackPosition, "Playback position")
    }

    func testControlLabelsAreDistinctAndNonEmpty() {
        let labels = [
            MediaWidgetLabels.previous,
            MediaWidgetLabels.playPause(isPlaying: true),
            MediaWidgetLabels.playPause(isPlaying: false),
            MediaWidgetLabels.next,
            MediaWidgetLabels.playbackPosition,
        ]
        XCTAssertEqual(Set(labels).count, labels.count)
        XCTAssertFalse(labels.contains(where: \.isEmpty))
    }

    func testPreviousRestartsAfterThreeSeconds() {
        XCTAssertEqual(MediaTransport.previousAction(elapsed: 3.01), .restartTrack)
        XCTAssertEqual(MediaTransport.previousAction(elapsed: 3), .previousTrack)
    }

    func testEmptyStateUsesTheDocumentedCopy() {
        XCTAssertEqual(MediaViewState(snapshot: nil), .empty)
        XCTAssertEqual(MediaWidgetMetrics.emptyTitle, "Not Playing")
        XCTAssertEqual(MediaWidgetMetrics.emptyMessage, "Play something to see it here")
    }
}
