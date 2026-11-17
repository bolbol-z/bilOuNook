import XCTest

final class FoundationsTests: XCTestCase {
    func testMotionTimeScaleIsOneUnlessDebugSlowMotionIsEnabled() {
        XCTAssertEqual(Animations.effectiveTimeScale(1.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(Animations.effectiveTimeScale(0.5), 1.0, accuracy: 0.0001)
        #if DEBUG
        XCTAssertEqual(Animations.effectiveTimeScale(4.0), 4.0, accuracy: 0.0001)
        #endif
    }

    func testEveryMotionPlanKeepsItsEffectiveValue() {
        XCTAssertEqual(Animations.plan(for: .openMetrics, reduceMotion: false), .spring(response: 0.26, dampingFraction: 0.88))
        XCTAssertEqual(Animations.plan(for: .closeMetrics, reduceMotion: false), .spring(response: 0.22, dampingFraction: 1.0))
        XCTAssertEqual(Animations.plan(for: .moduleChange, reduceMotion: false), .spring(response: 0.28, dampingFraction: 0.9))
        XCTAssertEqual(Animations.plan(for: .moduleContent, reduceMotion: false), .spring(response: 0.18, dampingFraction: 0.95))
        XCTAssertEqual(Animations.plan(for: .contentShow, reduceMotion: false), .spring(response: 0.32, dampingFraction: 0.9))
        XCTAssertEqual(Animations.plan(for: .contentHide, reduceMotion: false), .easeIn(duration: 0.12))
        XCTAssertEqual(Animations.plan(for: .liveActivity, reduceMotion: false), .spring(response: 0.30, dampingFraction: 0.86))

        let transitions: [NotchMotionTransition] = [
            .openMetrics, .closeMetrics, .moduleChange, .moduleContent,
            .contentShow, .contentHide, .liveActivity,
        ]
        for transition in transitions {
            XCTAssertEqual(Animations.plan(for: transition, reduceMotion: true), .crossfade(duration: 0.10))
        }
    }

    func testOpenContentIsLaidOutAtThePreferredSizeNotTheAnimatedMetrics() {
        let preferred = CGSize(width: 520, height: 225)

        let frame = NotchContentLayout.contentSize(preferred: preferred)

        XCTAssertEqual(frame.width, preferred.width, accuracy: 0.0001)
        XCTAssertEqual(frame.height, preferred.height, accuracy: 0.0001)
        XCTAssertNotEqual(frame.width, NotchPresets.open.w)

        let fallback = NotchContentLayout.contentSize(preferred: nil)
        XCTAssertEqual(fallback.width, NotchPresets.open.w, accuracy: 0.0001)
        XCTAssertEqual(fallback.height, NotchPresets.open.h, accuracy: 0.0001)
    }
}
