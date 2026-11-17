import CoreGraphics
import Foundation

struct WeekStripDay: Equatable {
    let date: Date
    let headerLetter: String
    let shortHeader: String
    let dayNumber: String
    let isToday: Bool
    let isWeekend: Bool
    let isSelected: Bool
}

struct WeekStripModel: Equatable {
    let selectedDay: Date
    let monthLabel: String
    let days: [WeekStripDay]
    let previousPartial: WeekStripDay
    let nextPartial: WeekStripDay

    init(selectedDay: Date, today: Date, calendar: Calendar, locale: Locale) {
        let selected = calendar.startOfDay(for: selectedDay)
        self.selectedDay = selected
        self.monthLabel = Self.monthLabel(for: selected, calendar: calendar, locale: locale)

        // Headers come from the requested locale, never from the calendar's
        // `firstWeekday`. A Monday-first region (firstWeekday == 2) must not
        // move the window: it is always selectedDay - 3 ... selectedDay + 3.
        var symbolCalendar = calendar
        symbolCalendar.locale = locale
        let weekdaySymbols = symbolCalendar.veryShortWeekdaySymbols
        let shortSymbols = symbolCalendar.shortWeekdaySymbols

        func day(offset: Int) -> WeekStripDay {
            let date = calendar.date(byAdding: .day, value: offset, to: selected) ?? selected
            let weekday = calendar.component(.weekday, from: date) - 1
            let header = weekdaySymbols.indices.contains(weekday) ? weekdaySymbols[weekday] : ""
            let short = shortSymbols.indices.contains(weekday)
                ? Self.threeLetterHeader(shortSymbols[weekday], locale: locale)
                : ""
            return WeekStripDay(
                date: date,
                headerLetter: header,
                shortHeader: short,
                dayNumber: String(format: "%02d", calendar.component(.day, from: date)),
                isToday: calendar.isDate(date, inSameDayAs: today),
                isWeekend: calendar.isDateInWeekend(date),
                isSelected: calendar.isDate(date, inSameDayAs: selected)
            )
        }

        self.days = (-3...3).map(day)
        self.previousPartial = day(offset: -4)
        self.nextPartial = day(offset: 4)
    }

    private static func threeLetterHeader(_ symbol: String, locale: Locale) -> String {
        let letters = symbol.uppercased(with: locale).filter { $0.isLetter }
        return String(letters.prefix(3))
    }

    private static func monthLabel(for date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }
}

enum WeekStripScroll {
    static func steps(accumulated: CGFloat, stepPoints: CGFloat = CalendarWidgetMetrics.scrollStepPoints) -> (steps: Int, remainder: CGFloat) {
        guard stepPoints > 0 else { return (0, accumulated) }
        let steps = Int(accumulated / stepPoints)
        return (steps, accumulated - CGFloat(steps) * stepPoints)
    }

    struct Resolution: Equatable {
        let remainder: CGFloat
        let selectedDay: Date
        let slideOffset: CGFloat
        let didStep: Bool
    }

    /// Turns one scroll event into the new selected day plus the exact 24pt
    /// slide that keeps the strip visually continuous while it re-centres.
    static func resolve(
        selectedDay: Date,
        calendar: Calendar,
        accumulated: CGFloat,
        deltaX: CGFloat,
        stepPoints: CGFloat = CalendarWidgetMetrics.scrollStepPoints
    ) -> Resolution {
        let resolved = steps(accumulated: accumulated + deltaX, stepPoints: stepPoints)
        guard resolved.steps != 0,
              let date = calendar.date(byAdding: .day, value: -resolved.steps, to: selectedDay)
        else {
            return Resolution(
                remainder: resolved.remainder,
                selectedDay: selectedDay,
                slideOffset: 0,
                didStep: false
            )
        }
        return Resolution(
            remainder: resolved.remainder,
            selectedDay: date,
            slideOffset: CalendarWidgetMetrics.stripSlideOffset(steps: resolved.steps),
            didStep: true
        )
    }
}

enum WeekStripHitTest {
    static func day(atX x: CGFloat, model: WeekStripModel) -> WeekStripDay {
        if x < CalendarWidgetMetrics.columnFrames[0].minX {
            return model.previousPartial
        }
        if x >= CalendarWidgetMetrics.nextPartialFrame.minX {
            return model.nextPartial
        }
        let index = Int((x - CalendarWidgetMetrics.columnFrames[0].minX) / CalendarWidgetMetrics.columnWidth)
        return model.days[min(max(0, index), model.days.count - 1)]
    }
}
