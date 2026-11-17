import SwiftUI
import XCTest

final class NookContentProgressTests: XCTestCase {
    func testRevealThresholdsAreStaggeredAndClamped() {
        XCTAssertEqual(NookContentProgress.tabs(0), 0, accuracy: 0.0001)
        XCTAssertEqual(NookContentProgress.tabs(0.05), 0, accuracy: 0.0001)
        XCTAssertEqual(NookContentProgress.tabs(0.35), 1, accuracy: 0.0001)
        XCTAssertEqual(NookContentProgress.media(0.14), 0, accuracy: 0.0001)
        XCTAssertEqual(NookContentProgress.media(0.55), 1, accuracy: 0.0001)
        XCTAssertEqual(NookContentProgress.calendar(0.21), 0, accuracy: 0.0001)
        XCTAssertEqual(NookContentProgress.calendar(0.62), 1, accuracy: 0.0001)
    }

    func testGroupsNeverRunBackwardsAsProgressAdvances() {
        let samples = stride(from: 0.0, through: 1.0, by: 0.01)
        var previousTabs = 0.0
        var previousMedia = 0.0
        var previousCalendar = 0.0

        for progress in samples {
            let tabs = NookContentProgress.tabs(progress)
            let media = NookContentProgress.media(progress)
            let calendar = NookContentProgress.calendar(progress)

            XCTAssertGreaterThanOrEqual(tabs, previousTabs)
            XCTAssertGreaterThanOrEqual(media, previousMedia)
            XCTAssertGreaterThanOrEqual(calendar, previousCalendar)

            previousTabs = tabs
            previousMedia = media
            previousCalendar = calendar
        }
    }

    func testReversingProgressReversesTheSameTimeline() {
        let forward = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0].map(NookContentProgress.media)
        let reversed = [1.0, 0.8, 0.6, 0.4, 0.2, 0.0].map(NookContentProgress.media)

        XCTAssertEqual(reversed, forward.reversed())
    }

    func testOffsetAndArtworkScaleEndSettled() {
        XCTAssertEqual(NookContentProgress.offset(opacity: 0, reduceMotion: false), 4)
        XCTAssertEqual(NookContentProgress.offset(opacity: 1, reduceMotion: false), 0)
        XCTAssertEqual(NookContentProgress.offset(opacity: 0, reduceMotion: true), 0)

        XCTAssertEqual(NookContentProgress.artworkScale(opacity: 0, reduceMotion: false), 0.96)
        XCTAssertEqual(NookContentProgress.artworkScale(opacity: 1, reduceMotion: false), 1)
        XCTAssertEqual(NookContentProgress.artworkScale(opacity: 0, reduceMotion: true), 1)
    }

    func testInteractionConstantsArePinned() {
        XCTAssertEqual(InteractionMotion.controlPress, Animations.scaled(.spring(response: 0.18, dampingFraction: 0.8)))
        XCTAssertEqual(InteractionMotion.hoverBrighten, 0.12)
        XCTAssertEqual(InteractionMotion.scrubberFade, Animations.scaled(.easeOut(duration: 0.15)))
        XCTAssertEqual(InteractionMotion.artworkPause, Animations.scaled(.spring(response: 0.3, dampingFraction: 0.85)))
        XCTAssertEqual(InteractionMotion.trackChange, Animations.scaled(.easeInOut(duration: 0.2)))
        XCTAssertEqual(InteractionMotion.calendarDayHighlight, Animations.scaled(.spring(response: 0.3, dampingFraction: 0.75)))
        XCTAssertEqual(InteractionMotion.calendarStripScroll, Animations.scaled(.spring(response: 0.28, dampingFraction: 0.9)))
        XCTAssertEqual(InteractionMotion.calendarHeaderSwap, Animations.scaled(.easeOut(duration: 0.12)))
        XCTAssertEqual(InteractionMotion.calendarEventsReveal, Animations.scaled(.easeOut(duration: 0.18)))
        XCTAssertEqual(Animations.tabPill, Animations.scaled(.spring(response: 0.28, dampingFraction: 0.85)))
        XCTAssertEqual(
            InteractionMotion.respectingReduceMotion(.spring(response: 0.3, dampingFraction: 0.8), reduceMotion: true),
            .easeInOut(duration: 0.10)
        )
    }

    func testBlurStaysDisabledAndTimelineConstantsArePinned() {
        XCTAssertFalse(Animations.contentBlurEnabled)
        XCTAssertEqual(NookContentProgress.tabsStart, 0.05)
        XCTAssertEqual(NookContentProgress.mediaStart, 0.15)
        XCTAssertEqual(NookContentProgress.calendarStart, 0.22)
        XCTAssertEqual(NookContentProgress.revealOffset, 4)
    }
}
