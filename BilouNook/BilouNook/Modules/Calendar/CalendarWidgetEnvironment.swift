import Foundation
import SwiftUI

private struct CalendarServiceEnvironmentKey: EnvironmentKey {
    static let defaultValue = CalendarService.shared
}

private struct CalendarInitialSelectedDayEnvironmentKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    var calendarService: CalendarService {
        get { self[CalendarServiceEnvironmentKey.self] }
        set { self[CalendarServiceEnvironmentKey.self] = newValue }
    }

    /// Seeds the week strip with a selected day other than today. Nil in the
    /// live app, where the selection starts at today and only click/scroll move it.
    var calendarInitialSelectedDay: Date? {
        get { self[CalendarInitialSelectedDayEnvironmentKey.self] }
        set { self[CalendarInitialSelectedDayEnvironmentKey.self] = newValue }
    }
}
