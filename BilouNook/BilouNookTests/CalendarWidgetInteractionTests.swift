import CoreGraphics
import XCTest

final class CalendarWidgetInteractionTests: XCTestCase {
    func testGestureOwnerBlocksAndReleases() {
        let monitor = GestureMonitor()
        XCTAssertNil(monitor.gestureOwner)

        monitor.acquireGestureOwner("calendar.weekStrip")
        XCTAssertEqual(monitor.gestureOwner, "calendar.weekStrip")
        monitor.releaseGestureOwner("other.owner")
        XCTAssertEqual(monitor.gestureOwner, "calendar.weekStrip")

        monitor.releaseGestureOwner("calendar.weekStrip")
        XCTAssertNil(monitor.gestureOwner)
    }

    func testScrollMovesOneDayPerTwelvePoints() {
        XCTAssertEqual(WeekStripScroll.steps(accumulated: -11).steps, 0)
        XCTAssertEqual(WeekStripScroll.steps(accumulated: -11).remainder, -11)
        XCTAssertEqual(WeekStripScroll.steps(accumulated: -12).steps, -1)
        XCTAssertEqual(WeekStripScroll.steps(accumulated: -12).remainder, 0)
        XCTAssertEqual(WeekStripScroll.steps(accumulated: -25).steps, -2)
        XCTAssertEqual(WeekStripScroll.steps(accumulated: -25).remainder, -1)
        XCTAssertEqual(WeekStripScroll.steps(accumulated: 13).steps, 1)
        XCTAssertEqual(WeekStripScroll.steps(accumulated: 13).remainder, 1)
    }

    func testHitTestSelectsColumnsAndPartials() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let today = makeDate(day: 5, calendar: calendar)
        let model = WeekStripModel(
            selectedDay: today,
            today: today,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(WeekStripHitTest.day(atX: 30, model: model).dayNumber, "01")
        XCTAssertEqual(WeekStripHitTest.day(atX: 44, model: model).dayNumber, "02")
        XCTAssertEqual(WeekStripHitTest.day(atX: 67, model: model).dayNumber, "02")
        XCTAssertEqual(WeekStripHitTest.day(atX: 68, model: model).dayNumber, "03")
        XCTAssertEqual(WeekStripHitTest.day(atX: 116, model: model).dayNumber, "05")
        XCTAssertEqual(WeekStripHitTest.day(atX: 220, model: model).dayNumber, "09")
    }

    func testOneScrollStepMovesTheSelectionByOneDayAndOneColumn() {
        let fixture = StripMatrix.fixture(firstWeekday: 2, timeZone: "Africa/Tunis")
        var selected = fixture.date(2026, 11, 2)

        // Forward in time: the strip starts one column to the right of the
        // re-centred layout and slides left into place.
        let forward = WeekStripScroll.resolve(
            selectedDay: selected,
            calendar: fixture.calendar,
            accumulated: 0,
            deltaX: -CalendarWidgetMetrics.scrollStepPoints
        )
        XCTAssertTrue(forward.didStep)
        XCTAssertEqual(forward.slideOffset, CalendarWidgetMetrics.columnWidth)
        XCTAssertEqual(
            fixture.calendar.dateComponents([.day], from: selected, to: forward.selectedDay).day,
            1
        )

        // Backward in time: the strip starts one column to the left and slides
        // right into place.
        let backward = WeekStripScroll.resolve(
            selectedDay: forward.selectedDay,
            calendar: fixture.calendar,
            accumulated: 0,
            deltaX: CalendarWidgetMetrics.scrollStepPoints
        )
        XCTAssertTrue(backward.didStep)
        XCTAssertEqual(backward.slideOffset, -CalendarWidgetMetrics.columnWidth)
        XCTAssertTrue(fixture.calendar.isDate(backward.selectedDay, inSameDayAs: selected))

        // Sub-threshold deltas accumulate and do not step.
        let small = WeekStripScroll.resolve(
            selectedDay: selected,
            calendar: fixture.calendar,
            accumulated: 0,
            deltaX: -CalendarWidgetMetrics.scrollStepPoints / 2
        )
        XCTAssertFalse(small.didStep)
        XCTAssertEqual(small.remainder, -CalendarWidgetMetrics.scrollStepPoints / 2)
        XCTAssertTrue(fixture.calendar.isDate(small.selectedDay, inSameDayAs: selected))

        // The accumulator carries over the remainder.
        let carried = WeekStripScroll.resolve(
            selectedDay: selected,
            calendar: fixture.calendar,
            accumulated: small.remainder,
            deltaX: -CalendarWidgetMetrics.scrollStepPoints / 2
        )
        XCTAssertTrue(carried.didStep)
        XCTAssertEqual(carried.remainder, 0)

        // A fast three-step scroll slides three columns.
        let triple = WeekStripScroll.resolve(
            selectedDay: selected,
            calendar: fixture.calendar,
            accumulated: 0,
            deltaX: -3 * CalendarWidgetMetrics.scrollStepPoints
        )
        XCTAssertEqual(triple.slideOffset, 3 * CalendarWidgetMetrics.columnWidth)
        selected = triple.selectedDay
        XCTAssertEqual(
            fixture.calendar.dateComponents([.day], from: fixture.date(2026, 11, 2), to: selected).day,
            3
        )
    }

    func testHitTestUsesTheRenderedColumnFrames() {
        let fixture = StripMatrix.fixture(firstWeekday: 2, timeZone: "Africa/Tunis")
        let today = fixture.date(2026, 11, 2)
        let model = WeekStripModel(
            selectedDay: today,
            today: today,
            calendar: fixture.calendar,
            locale: Locale(identifier: "en_US")
        )

        // Clicking anywhere inside a column selects that column's day.
        for (index, frame) in CalendarWidgetMetrics.columnFrames.enumerated() {
            for x in [frame.minX + 0.5, frame.midX, frame.maxX - 0.5] {
                let day = WeekStripHitTest.day(atX: x, model: model)
                XCTAssertEqual(day.dayNumber, model.days[index].dayNumber, "x \(x) column \(index)")
            }
        }
        // The partial neighbours are selectable too.
        XCTAssertEqual(
            WeekStripHitTest.day(atX: CalendarWidgetMetrics.previousPartialFrame.minX + 1, model: model).dayNumber,
            model.previousPartial.dayNumber
        )
        XCTAssertEqual(
            WeekStripHitTest.day(atX: CalendarWidgetMetrics.nextPartialFrame.minX + 1, model: model).dayNumber,
            model.nextPartial.dayNumber
        )
    }

    func testCalendarWidgetMatchesSpec() {
        let widget = CalendarWidget()
        XCTAssertEqual(widget.id, "calendar")
        XCTAssertEqual(widget.preferredWidth, 224)
    }

    private func makeDate(day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2024, month: 8, day: day, hour: 12)) ?? Date()
    }
}

final class TabSwipeSessionTests: XCTestCase {
    private func ev(_ dx: CGFloat, _ dy: CGFloat = 0, _ phase: NSEvent.Phase, _ t: TimeInterval,
                    momentum: NSEvent.Phase = []) -> TabSwipeSession.Input {
        .init(dx: dx, dy: dy, phase: phase, momentum: momentum, time: t, precise: true, shift: false)
    }
    private func run(_ events: [TabSwipeSession.Input], canGo: @escaping (Int) -> Bool = { _ in true }) -> [TabSwipeSession.Output] {
        var s = TabSwipeSession()
        return events.map { s.feed($0, canGo: canGo) }
    }
    private func commits(_ o: [TabSwipeSession.Output]) -> Int { o.filter { if case .commit = $0 { return true }; return false }.count }

    func testSwipeCommitsOnceAtEnd() {
        let o = run([ev(8,0,.began,0), ev(8,0,.changed,0.01), ev(8,0,.changed,0.02), ev(0,0,.ended,0.03)])
        XCTAssertEqual(commits(o), 1); XCTAssertTrue(o.contains(.commit(-1)))
    }
    func testShortSwipeSnapsBack() {
        let o = run([ev(5,0,.began,0), ev(5,0,.changed,0.01), ev(0,0,.ended,0.02)])
        XCTAssertEqual(commits(o), 0); XCTAssertEqual(o.last, .snapBack)
    }
    func testForceCommitMidGestureOnlyOnce() {
        let o = run([ev(20,0,.began,0), ev(20,0,.changed,0.01), ev(10,0,.changed,0.02), ev(5,0,.changed,0.03), ev(0,0,.ended,0.04)])
        XCTAssertEqual(commits(o), 1)
    }
    func testMomentumAfterCommitIsSwallowedWithoutSecondSwitch() {
        let o = run([ev(30,0,.began,0), ev(0,0,.ended,0.01), ev(4,0,[],0.02,momentum:.began), ev(4,0,[],0.03,momentum:.changed), ev(0,0,[],0.04,momentum:.ended)])
        XCTAssertEqual(commits(o), 1)
        XCTAssertEqual(Array(o.suffix(3)), [.swallow, .swallow, .swallow])
    }
    func testDiagonalBecomesVerticalAndPasses() {
        let o = run([ev(8,8,.began,0), ev(8,8,.changed,0.01)])
        XCTAssertEqual(o, [.pass, .pass])
    }
    func testVerticalLockedIgnoresLaterHorizontal() {
        let o = run([ev(0,10,.began,0), ev(30,0,.changed,0.01), ev(0,0,.ended,0.02)])
        XCTAssertTrue(o.allSatisfy { $0 == .pass })
    }
    func testEdgeResistsAndSnapsBack() {
        let o = run([ev(30,0,.began,0), ev(30,0,.changed,0.01), ev(0,0,.ended,0.02)], canGo: { _ in false })
        XCTAssertEqual(commits(o), 0)
        if case .track(let x) = o[1] { XCTAssertLessThanOrEqual(abs(x), 28) } else { XCTFail() }
        XCTAssertEqual(o.last, .snapBack)
    }
    func testWheelDebounce300ms() {
        var s = TabSwipeSession()
        func w(_ t: TimeInterval) -> TabSwipeSession.Output {
            s.feed(.init(dx: 0, dy: -3, phase: [], momentum: [], time: t, precise: false, shift: true), canGo: { _ in true })
        }
        XCTAssertEqual(w(10.0), .commit(1)); XCTAssertEqual(w(10.2), .swallow); XCTAssertEqual(w(10.5), .commit(1))
    }
    func testOffsets() {
        XCTAssertEqual(TabSwipeSession.offset(for: 40, allowed: true), 40)
        XCTAssertEqual(TabSwipeSession.offset(for: 60, allowed: true), 46, accuracy: 0.001)
        XCTAssertEqual(TabSwipeSession.offset(for: 100, allowed: true), 58, accuracy: 0.001)
        XCTAssertEqual(TabSwipeSession.offset(for: -100, allowed: false), -28, accuracy: 0.001)
        XCTAssertEqual(TabSwipeSession.offset(for: 40, allowed: false), 14, accuracy: 0.001)
    }
}
