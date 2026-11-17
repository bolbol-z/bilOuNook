import XCTest

final class NotchStateTestClock: NotchClock {
    private(set) var current = Date(timeIntervalSince1970: 1_000_000)
    func now() -> Date { current }
    func advance(_ seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
}

final class NotchStateTestScheduler: NotchScheduler {
    private final class Item {
        let id: Int
        let deadline: TimeInterval
        let action: () -> Void

        init(id: Int, deadline: TimeInterval, action: @escaping () -> Void) {
            self.id = id
            self.deadline = deadline
            self.action = action
        }
    }

    private var items: [Item] = []
    private var nextID = 0
    private(set) var currentTime: TimeInterval = 0

    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> NotchScheduled {
        let item = Item(id: nextID, deadline: currentTime + delay, action: action)
        nextID += 1
        items.append(item)
        let id = item.id
        return NotchScheduled { [weak self] in self?.remove(id) }
    }

    func advance(by seconds: TimeInterval) {
        currentTime += seconds
        while true {
            let due = items
                .filter { $0.deadline <= currentTime }
                .sorted { ($0.deadline, $0.id) < ($1.deadline, $1.id) }
            guard let next = due.first else { break }
            remove(next.id)
            next.action()
        }
    }

    private func remove(_ id: Int) {
        items.removeAll { $0.id == id }
    }
}

final class NotchStateTests: XCTestCase {
    private func makeState() -> (NotchState, NotchStateTestClock, NotchStateTestScheduler) {
        let clock = NotchStateTestClock()
        let scheduler = NotchStateTestScheduler()
        let state = NotchState(clock: clock, scheduler: scheduler)
        state.minStateDwell = 0.12
        state.closeDelay = 0.15
        return (state, clock, scheduler)
    }

    func testEnterIntentTwiceRequestsOneOpen() {
        let (state, _, _) = makeState()
        state.enterIntent()
        let phase = state.phase
        state.enterIntent()
        XCTAssertEqual(state.phase, phase)
        XCTAssertEqual(state.phase, .open)
    }

    func testEnterIntentIsIgnoredAfterClickCloseUntilLockExpires() {
        let (state, clock, scheduler) = makeState()
        state.requestOpen(trigger: .click)
        XCTAssertEqual(state.phase, .open)

        clock.advance(0.15)          // clear the 0.12 dwell before closing
        state.toggle()               // click-close; lock = 0.15 + 0.30 = 0.45
        scheduler.advance(by: 0.2)   // closeDelay 0.15 fires -> .closed
        XCTAssertEqual(state.phase, .closed)

        state.enterIntent()          // now 0.15 < 0.45 -> ignored
        XCTAssertEqual(state.phase, .closed)

        clock.advance(0.29)          // now 0.44 < 0.45 -> still locked
        state.enterIntent()
        XCTAssertEqual(state.phase, .closed)

        clock.advance(0.02)          // now 0.46 >= 0.45 -> opens
        state.enterIntent()
        XCTAssertEqual(state.phase, .open)
    }

    func testEnterIntentIsLevelTriggeredIdempotentWhileOpen() {
        let (state, _, _) = makeState()
        state.enterIntent()
        XCTAssertEqual(state.phase, .open)
        state.enterIntent()
        state.enterIntent()
        XCTAssertEqual(state.phase, .open)
    }

    func testOpenIsImmediate() {
        let (state, _, _) = makeState()
        state.requestOpen(trigger: .click)
        XCTAssertEqual(state.phase, .open)
    }

    func testClickOnlyOpensAndNeverCloses() {
        let (state, clock, _) = makeState()
        state.enterIntent()
        XCTAssertEqual(state.phase, .open)

        clock.advance(0.2)
        state.click()

        XCTAssertEqual(state.phase, .open)
    }

    func testCloseWaitsForCloseDelay() {
        let (state, clock, scheduler) = makeState()
        state.requestOpen(trigger: .click)
        clock.advance(0.2)
        state.requestClose(reason: .mouseLeft)
        XCTAssertEqual(state.phase, .closing)
        scheduler.advance(by: 0.14)
        XCTAssertEqual(state.phase, .closing)
        scheduler.advance(by: 0.02)
        XCTAssertEqual(state.phase, .closed)
    }

    func testDwellRejectsEarlyClose() {
        let (state, clock, _) = makeState()
        state.requestOpen(trigger: .click)
        clock.advance(0.05)
        state.requestClose(reason: .mouseLeft)
        XCTAssertEqual(state.phase, .open)
        clock.advance(0.08)
        state.requestClose(reason: .mouseLeft)
        XCTAssertEqual(state.phase, .closing)
    }

    func testWatchdogConfirmsAfterHalfSecondOutside() {
        let (state, clock, scheduler) = makeState()
        state.requestOpen(trigger: .click)
        clock.advance(0.2)
        state.watchdogTick(isOutside: true)
        XCTAssertEqual(state.phase, .open)
        clock.advance(0.25)
        state.watchdogTick(isOutside: true)
        XCTAssertEqual(state.phase, .open)
        clock.advance(0.24)
        state.watchdogTick(isOutside: true)
        XCTAssertEqual(state.phase, .open)
        clock.advance(0.01)
        state.watchdogTick(isOutside: true)
        XCTAssertEqual(state.phase, .closing)
        scheduler.advance(by: 0.15)
        XCTAssertEqual(state.phase, .closed)
    }

    func testHoverIntentIsIgnoredDuringClosingAndReopensAfter() {
        let (state, clock, scheduler) = makeState()
        state.requestOpen(trigger: .click)
        clock.advance(0.2)
        state.requestClose(reason: .mouseLeft)
        XCTAssertEqual(state.phase, .closing)

        state.enterIntent() // ignored: phase != .closed
        XCTAssertEqual(state.phase, .closing)

        scheduler.advance(by: 0.2) // closeDelay 0.15 -> .closed
        XCTAssertEqual(state.phase, .closed)

        state.enterIntent() // mouseLeft close sets no hover lock -> reopens
        XCTAssertEqual(state.phase, .open)
    }

    func testHoverOpensImmediately() {
        let (state, _, scheduler) = makeState()
        state.requestOpen(trigger: .hover)
        XCTAssertEqual(state.phase, .open)
        scheduler.advance(by: 0.2)
        XCTAssertEqual(state.phase, .open)
    }

    func testCloseImmediatelyUsesClosingPath() {
        let (state, clock, scheduler) = makeState()
        state.requestOpen(trigger: .click)
        clock.advance(0.2)
        state.closeImmediately(reason: .programmatic)
        XCTAssertEqual(state.phase, .closing)
        scheduler.advance(by: 0.15)
        XCTAssertEqual(state.phase, .closed)
    }

    func testEnterIntentSchedulesOpenWhenOpenOnHoverIsEnabled() {
        let (state, _, scheduler) = makeState()
        state.openOnHover = true
        state.intentDelay = 0.1
        state.enterIntent()
        XCTAssertEqual(state.phase, .closed)
        scheduler.advance(by: 0.1)
        XCTAssertEqual(state.phase, .open)
    }

    func testEnterIntentDoesNotScheduleOpenWhenOpenOnHoverIsDisabled() {
        let (state, _, scheduler) = makeState()
        state.openOnHover = false
        state.intentDelay = 0.1
        state.enterIntent()
        XCTAssertEqual(state.phase, .closed)
        scheduler.advance(by: 1.0)
        XCTAssertEqual(state.phase, .closed)
    }

    func testClickStillOpensWhenOpenOnHoverIsDisabled() {
        let (state, _, _) = makeState()
        state.openOnHover = false
        state.requestOpen(trigger: .click)
        XCTAssertEqual(state.phase, .open)
    }

    func testReenterDuringClosingCancelsCloseAndReopens() {
        let (state, clock, scheduler) = makeState()
        state.requestOpen(trigger: .click)
        clock.advance(0.2)              // dwell elapsed before close
        state.requestClose(reason: .mouseLeft)
        XCTAssertEqual(state.phase, .closing)

        clock.advance(0.15)             // minStateDwell 0.12 elapsed since close
        state.enterIntent()
        XCTAssertEqual(state.phase, .open)
        XCTAssertEqual(state.phase, .open)
        // No pending close fires after reopening.
        scheduler.advance(by: 0.5)
        XCTAssertEqual(state.phase, .open)
    }

    func testEnterIntentIgnoredBeforeMinStateDwellWhileClosing() {
        let (state, clock, scheduler) = makeState()
        state.requestOpen(trigger: .click)
        clock.advance(0.2)
        state.requestClose(reason: .mouseLeft)
        XCTAssertEqual(state.phase, .closing)

        state.enterIntent()             // dwell not yet elapsed -> ignored
        XCTAssertEqual(state.phase, .closing)
    }
}
