import AppKit
import XCTest

final class CalendarServiceTests: XCTestCase {
    private final class FakeSource: CalendarEventSource {
        var authorizationState: CalendarAuthorizationState
        var requestedState: CalendarAuthorizationState
        var requestCount = 0
        var eventsCallCount = 0
        var storedEvents: [CalendarEvent] = []

        init(
            authorizationState: CalendarAuthorizationState,
            requestedState: CalendarAuthorizationState = .authorized,
            events: [CalendarEvent] = []
        ) {
            self.authorizationState = authorizationState
            self.requestedState = requestedState
            self.storedEvents = events
        }

        func requestAccess() async -> CalendarAuthorizationState {
            requestCount += 1
            authorizationState = requestedState
            return authorizationState
        }

        func events(for day: Date, calendar: Calendar) -> [CalendarEvent] {
            eventsCallCount += 1
            return storedEvents
        }
    }

    @MainActor
    func testAuthorizedWithZeroOneTwoThreeEvents() {
        for count in 0...3 {
            let events = (0..<count).map { index in
                event(title: "Event \(index)", hour: 9 + index)
            }
            let source = FakeSource(authorizationState: .authorized, events: events)
            let service = makeService(source: source)
            XCTAssertEqual(service.events(for: service.today).count, count)
        }
    }

    @MainActor
    func testAllDayEventsSortFirstThenByStartTime() {
        let source = FakeSource(authorizationState: .authorized, events: [
            event(title: "Later", hour: 10),
            event(title: "All day", hour: 0, isAllDay: true),
            event(title: "Earlier", hour: 9),
        ])
        let service = makeService(source: source)
        let events = service.events(for: service.today)
        XCTAssertEqual(events.map(\.title), ["All day", "Earlier", "Later"])
    }

    @MainActor
    func testDeniedReturnsNoEventsAndDoesNotQuerySource() {
        let source = FakeSource(authorizationState: .denied, events: [event(title: "Hidden", hour: 9)])
        let service = makeService(source: source)
        XCTAssertTrue(service.events(for: service.today).isEmpty)
        XCTAssertEqual(source.eventsCallCount, 0)
    }

    @MainActor
    func testLoadEventsPublishesEventsForSelectedDay() async {
        let source = FakeSource(authorizationState: .authorized, events: [
            event(title: "Later", hour: 10),
            event(title: "Morning", hour: 9),
        ])
        let service = makeService(source: source)
        await service.loadEvents(for: service.today)
        XCTAssertEqual(service.eventsForSelectedDay.map(\.title), ["Morning", "Later"])
    }

    @MainActor
    func testLoadEventsDeniedAccessPublishesNothing() async {
        let source = FakeSource(authorizationState: .denied, events: [event(title: "Hidden", hour: 9)])
        let service = makeService(source: source)
        await service.loadEvents(for: service.today)
        XCTAssertTrue(service.eventsForSelectedDay.isEmpty)
        XCTAssertEqual(source.eventsCallCount, 0)
    }

    @MainActor
    func testAccessIsRequestedOnlyOnce() async {
        let source = FakeSource(authorizationState: .notDetermined)
        let service = makeService(source: source)
        await service.requestAccessIfNeeded()
        await service.requestAccessIfNeeded()
        XCTAssertEqual(source.requestCount, 1)
        XCTAssertEqual(service.authorizationState, .authorized)
    }

    @MainActor
    func testRestrictedDoesNotRequestAccessAgain() async {
        let source = FakeSource(authorizationState: .restricted)
        let service = makeService(source: source)
        await service.requestAccessIfNeeded()
        XCTAssertEqual(source.requestCount, 0)
        XCTAssertEqual(service.authorizationState, .restricted)
    }

    @MainActor
    func testRefreshOnStoreChangeAndDayChange() async {
        let source = FakeSource(authorizationState: .authorized, events: [event(title: "First", hour: 9)])
        let service = makeService(source: source)
        XCTAssertEqual(service.revision, 0)

        source.storedEvents = [event(title: "Second", hour: 10)]
        NotificationCenter.default.post(name: .EKEventStoreChanged, object: nil)
        await Task.yield()
        XCTAssertEqual(service.revision, 1)
        XCTAssertEqual(service.events(for: service.today).map(\.title), ["Second"])

        NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
        await Task.yield()
        XCTAssertEqual(service.revision, 2)
        XCTAssertEqual(service.dayChangeCount, 1)
    }

    @MainActor
    func testRefreshOnClockAndLocaleChange() async {
        let source = FakeSource(authorizationState: .authorized)
        let service = makeService(source: source)
        NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
        NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        await Task.yield()
        XCTAssertEqual(service.revision, 2)
        XCTAssertEqual(service.dayChangeCount, 0)
    }

    @MainActor
    private func makeService(source: FakeSource) -> CalendarService {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = calendar.date(from: DateComponents(year: 2024, month: 8, day: 5, hour: 12)) ?? Date()
        return CalendarService(
            source: source,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            now: { now }
        )
    }

    private func event(title: String, hour: Int, isAllDay: Bool = false) -> CalendarEvent {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let start = calendar.date(from: DateComponents(year: 2024, month: 8, day: 5, hour: hour)) ?? Date()
        return CalendarEvent(
            id: title,
            title: title,
            start: start,
            end: start.addingTimeInterval(3600),
            isAllDay: isAllDay,
            color: .systemBlue
        )
    }
}
