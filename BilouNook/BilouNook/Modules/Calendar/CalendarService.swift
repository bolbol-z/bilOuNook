import AppKit
import EventKit
import Foundation
import Observation

enum CalendarAuthorizationState: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: NSColor
}

protocol CalendarEventSource: AnyObject {
    var authorizationState: CalendarAuthorizationState { get }
    func requestAccess() async -> CalendarAuthorizationState
    func events(for day: Date, calendar: Calendar) -> [CalendarEvent]
}

final class EventKitCalendarEventSource: CalendarEventSource {
    private let store = EKEventStore()

    var authorizationState: CalendarAuthorizationState {
        Self.state(for: EKEventStore.authorizationStatus(for: .event))
    }

    func requestAccess() async -> CalendarAuthorizationState {
        if #available(macOS 14.0, *) {
            _ = try? await store.requestFullAccessToEvents()
        } else {
            await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { _, _ in
                    continuation.resume()
                }
            }
        }
        return authorizationState
    }

    func events(for day: Date, calendar: Calendar) -> [CalendarEvent] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { event in
            CalendarEvent(
                id: event.eventIdentifier ?? "\(event.calendarItemIdentifier)-\(event.startDate.timeIntervalSince1970)",
                title: event.title ?? "",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                color: event.calendar.color
            )
        }
    }

    private static func state(for status: EKAuthorizationStatus) -> CalendarAuthorizationState {
        if #available(macOS 14.0, *) {
            switch status {
            case .notDetermined:
                return .notDetermined
            case .restricted:
                return .restricted
            case .denied, .writeOnly:
                return .denied
            case .fullAccess, .authorized:
                return .authorized
            @unknown default:
                return .denied
            }
        }
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        default:
            return .denied
        }
    }
}

private final class CalendarNotificationBag {
    var tokens: [NSObjectProtocol] = []

    deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

@MainActor
@Observable
final class CalendarService {
    static let shared = CalendarService()

    let calendar: Calendar
    let locale: Locale
    private(set) var authorizationState: CalendarAuthorizationState
    private(set) var revision = 0
    private(set) var dayChangeCount = 0

    private let source: CalendarEventSource
    private let nowProvider: () -> Date
    private var eventsToken = 0
    /// Events for the day the UI is currently showing. Populated by loadEvents(for:).
    private(set) var eventsForSelectedDay: [CalendarEvent] = []
    private var didRequestAccess = false
    private let observationBag = CalendarNotificationBag()

    init(
        source: CalendarEventSource = EventKitCalendarEventSource(),
        calendar: Calendar = .current,
        locale: Locale = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.source = source
        self.locale = locale
        self.nowProvider = now
        var configured = calendar
        configured.locale = locale
        self.calendar = configured
        self.authorizationState = source.authorizationState
        observeChanges()
    }

    var today: Date { nowProvider() }

    var isAuthorized: Bool { authorizationState == .authorized }

    func requestAccessIfNeeded() async {
        guard !didRequestAccess else { return }
        didRequestAccess = true
        guard authorizationState == .notDetermined else { return }
        authorizationState = await source.requestAccess()
        revision += 1
    }

    func events(for day: Date) -> [CalendarEvent] {
        _ = revision
        guard authorizationState == .authorized else { return [] }
        return Self.normalize(source.events(for: day, calendar: calendar), for: day, calendar: calendar)
    }

    static func normalize(_ events: [CalendarEvent], for day: Date, calendar: Calendar) -> [CalendarEvent] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events
            .filter { $0.end >= start && $0.start < end }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    /// Fetches events off the main thread, then publishes them if the day is
    /// still the one being shown (stale results are dropped).
    func loadEvents(for day: Date) async {
        _ = revision
        guard authorizationState == .authorized else {
            eventsForSelectedDay = []
            return
        }
        let source = self.source
        let calendar = self.calendar
        eventsToken += 1
        let token = eventsToken
        let fetched = await Task.detached(priority: .userInitiated) {
            source.events(for: day, calendar: calendar)
        }.value
        guard token == eventsToken else { return }
        eventsForSelectedDay = Self.normalize(fetched, for: day, calendar: calendar)
    }

    func refresh() {
        revision += 1
    }

    private func observeChanges() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .EKEventStoreChanged,
            .NSCalendarDayChanged,
            .NSSystemClockDidChange,
            NSLocale.currentLocaleDidChangeNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.revision += 1
                    if name == .NSCalendarDayChanged {
                        self.dayChangeCount += 1
                    }
                }
            }
            observationBag.tokens.append(token)
        }
    }
}
