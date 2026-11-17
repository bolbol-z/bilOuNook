import XCTest

final class WeekStripModelTests: XCTestCase {
    func testReferenceDateEnglishGivesExpectedColumns() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(abbreviation: "BST") ?? .gmt
        let locale = Locale(identifier: "en_US")
        let today = makeDate("2024-08-05T12:00:00", calendar: calendar)
        let selected = today
        let model = WeekStripModel(selectedDay: selected, today: today, calendar: calendar, locale: locale)

        XCTAssertEqual(model.days.map(\.headerLetter), ["F", "S", "S", "M", "T", "W", "T"])
        XCTAssertEqual(model.days.map(\.shortHeader), ["FRI", "SAT", "SUN", "MON", "TUE", "WED", "THU"])
        XCTAssertEqual(model.days.map(\.dayNumber), ["02", "03", "04", "05", "06", "07", "08"])
        XCTAssertTrue(model.days[3].isToday)
        XCTAssertTrue(model.days[3].isSelected)
        XCTAssertTrue(model.days[1].isWeekend)
        XCTAssertTrue(model.days[2].isWeekend)
        XCTAssertFalse(model.days[3].isWeekend)
        XCTAssertEqual(model.monthLabel, "Aug")
    }

    func testFrenchLocaleUsesShortWeekdaySymbols() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let locale = Locale(identifier: "fr_FR")
        let today = makeDate("2024-08-05T12:00:00", calendar: calendar)
        let model = WeekStripModel(selectedDay: today, today: today, calendar: calendar, locale: locale)
        XCTAssertEqual(model.days[3].shortHeader.count, 3)
        XCTAssertTrue(model.days[3].shortHeader == model.days[3].shortHeader.uppercased())
    }

    func testMonthBoundaryJulyToAugust() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let locale = Locale(identifier: "en_US")
        let selected = makeDate("2024-07-31T12:00:00", calendar: calendar)
        let today = makeDate("2024-07-31T12:00:00", calendar: calendar)
        let model = WeekStripModel(selectedDay: selected, today: today, calendar: calendar, locale: locale)
        XCTAssertEqual(model.days.map(\.dayNumber), ["28", "29", "30", "31", "01", "02", "03"])
        XCTAssertEqual(model.monthLabel, "Jul")
        let aug = WeekStripModel(selectedDay: makeDate("2024-08-01T12:00:00", calendar: calendar), today: today, calendar: calendar, locale: locale)
        XCTAssertEqual(aug.monthLabel, "Aug")
    }

    func testDstChangeDoesNotCorruptDays() {
        var calendar = Calendar(identifier: .gregorian)
        if let tz = TimeZone(identifier: "Europe/London") {
            calendar.timeZone = tz
        }
        let locale = Locale(identifier: "en_US")
        let selected = makeDate("2024-03-31T01:00:00", calendar: calendar)
        let model = WeekStripModel(selectedDay: selected, today: selected, calendar: calendar, locale: locale)
        XCTAssertEqual(model.days.count, 7)
        XCTAssertTrue(model.days.contains(where: { $0.isSelected }))
    }

    func testPartialNeighboursExistForFades() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let locale = Locale(identifier: "en_US")
        let selected = makeDate("2024-08-05T12:00:00", calendar: calendar)
        let model = WeekStripModel(selectedDay: selected, today: selected, calendar: calendar, locale: locale)
        XCTAssertFalse(model.previousPartial.headerLetter.isEmpty)
        XCTAssertFalse(model.nextPartial.headerLetter.isEmpty)
        XCTAssertEqual(model.previousPartial.dayNumber, "01")
        XCTAssertEqual(model.nextPartial.dayNumber, "09")
    }

    func testSelectedDayDefaultsToTodayAndResetsOnMonthLabelClick() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let today = makeDate("2024-08-05T12:00:00", calendar: calendar)
        let model = WeekStripModel(selectedDay: today, today: today, calendar: calendar, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(model.days[3].isSelected)
        XCTAssertTrue(model.days[3].isToday)
    }

    // MARK: - calendar-strip-fix matrix
    //
    // The strip window must be selectedDay-3 ... selectedDay+3 regardless of
    // `Calendar.firstWeekday`. The owner's Mac is configured with firstWeekday 2
    // (Monday) and the old tests only ran with en_US (firstWeekday 1), so the
    // matrix below pins firstWeekday 1, 2 and 7 across three time zones, every
    // weekday, month boundaries, leap day and both DST change days.

    func testMatrixWindowIsIndependentOfFirstWeekday() {
        for fixture in StripMatrix.fixtures {
            for anchor in StripMatrix.anchors {
                let today = fixture.date(anchor.year, anchor.month, anchor.day, hour: 12)
                for offset in -7...7 {
                    let selected = fixture.calendar.date(byAdding: .day, value: offset, to: today) ?? today
                    let context = "\(fixture.name) anchor=\(anchor.label) offset=\(offset)"

                    let model = WeekStripModel(
                        selectedDay: selected,
                        today: today,
                        calendar: fixture.calendar,
                        locale: StripMatrix.english
                    )

                    XCTAssertEqual(model.days.count, 7, context)
                    XCTAssertEqual(model.days.filter(\.isSelected).count, 1, context)
                    XCTAssertTrue(model.days[3].isSelected, context)

                    for index in 0..<7 {
                        let step = index - 3
                        let expected = fixture.calendar.date(byAdding: .day, value: step, to: selected) ?? selected
                        XCTAssertTrue(
                            fixture.calendar.isDate(model.days[index].date, inSameDayAs: expected),
                            "\(context) column \(index) expected \(expected) got \(model.days[index].date)"
                        )
                        XCTAssertEqual(
                            model.days[index].dayNumber,
                            String(format: "%02d", fixture.calendar.component(.day, from: expected)),
                            "\(context) column \(index) number"
                        )
                        XCTAssertEqual(
                            model.days[index].isWeekend,
                            fixture.calendar.isDateInWeekend(expected),
                            "\(context) column \(index) weekend"
                        )
                        XCTAssertTrue(
                            fixture.calendar.isDate(model.days[index].date, inSameDayAs: expected),
                            "\(context) column \(index) date"
                        )
                    }

                    let previous = fixture.calendar.date(byAdding: .day, value: -4, to: selected) ?? selected
                    let next = fixture.calendar.date(byAdding: .day, value: 4, to: selected) ?? selected
                    XCTAssertTrue(
                        fixture.calendar.isDate(model.previousPartial.date, inSameDayAs: previous),
                        "\(context) previous partial"
                    )
                    XCTAssertTrue(
                        fixture.calendar.isDate(model.nextPartial.date, inSameDayAs: next),
                        "\(context) next partial"
                    )

                    // Only the selected column renders the 3-letter header.
                    for index in 0..<7 {
                        if model.days[index].isSelected {
                            XCTAssertEqual(model.days[index].shortHeader.count, 3, "\(context) selected header")
                        } else {
                            XCTAssertLessThanOrEqual(
                                model.days[index].headerLetter.count, 2,
                                "\(context) column \(index) must stay a very short header"
                            )
                        }
                    }
                }
            }
        }
    }

    func testMatrixColumnCentresAndPartialsMatchSpec() {
        for fixture in StripMatrix.fixtures {
            for index in 0..<7 {
                XCTAssertEqual(
                    CalendarWidgetMetrics.columnFrames[index].midX,
                    56 + CGFloat(index) * 24,
                    "\(fixture.name) column \(index) centre"
                )
                // The centre must not depend on the selected day.
                let model = WeekStripModel(
                    selectedDay: StripMatrix.ownerDay(in: fixture.calendar),
                    today: StripMatrix.ownerDay(in: fixture.calendar),
                    calendar: fixture.calendar,
                    locale: StripMatrix.english
                )
                XCTAssertEqual(model.days[index].dayNumber, StripMatrix.ownerDayNumbers[index], "\(fixture.name) \(index)")
            }
            XCTAssertEqual(CalendarWidgetMetrics.previousPartialFrame.midX, 32, fixture.name)
            XCTAssertEqual(
                CalendarWidgetMetrics.nextPartialColumnFrame.midX,
                224,
                "\(fixture.name) the next partial column is centred on the right edge"
            )
            XCTAssertEqual(CalendarWidgetMetrics.nextPartialFrame.maxX, 224, fixture.name)
            XCTAssertEqual(CalendarWidgetMetrics.stripColumnFrames.count, 9, fixture.name)
        }
    }

    func testOwnerConfigurationMondayCase() {
        // Owner's Mac: 12-hour region, Monday-first weeks, Africa/Tunis, today = Mon 2 Nov 2026.
        let fixture = StripMatrix.fixture(firstWeekday: 2, timeZone: "Africa/Tunis")
        let today = fixture.date(2026, 11, 2, hour: 12)
        let model = WeekStripModel(selectedDay: today, today: today, calendar: fixture.calendar, locale: StripMatrix.english)

        XCTAssertEqual(model.days.map(\.shortHeader), ["FRI", "SAT", "SUN", "MON", "TUE", "WED", "THU"])
        XCTAssertEqual(model.days.map(\.dayNumber), ["30", "31", "01", "02", "03", "04", "05"])
        XCTAssertEqual(model.previousPartial.dayNumber, "29")
        XCTAssertEqual(model.nextPartial.dayNumber, "06")
        XCTAssertEqual(model.monthLabel, "Nov")
        XCTAssertTrue(model.days[3].isToday)
        XCTAssertFalse(model.days[3].isWeekend)
    }

    func testFrenchLocaleKeepsWindowAndUsesThreeLetters() {
        let fixture = StripMatrix.fixture(firstWeekday: 2, timeZone: "Europe/Paris")
        let today = fixture.date(2026, 11, 2, hour: 12)
        let model = WeekStripModel(
            selectedDay: today,
            today: today,
            calendar: fixture.calendar,
            locale: Locale(identifier: "fr_FR")
        )
        XCTAssertEqual(model.days[3].shortHeader, "LUN")
        XCTAssertEqual(model.days.map(\.dayNumber), ["30", "31", "01", "02", "03", "04", "05"])
        XCTAssertEqual(model.monthLabel, "nov.")
    }

    func testDstDaysKeepConsecutiveDayNumbers() {
        for (label, zone, month, day) in [
            ("Paris spring forward", "Europe/Paris", 3, 31),
            ("Paris fall back", "Europe/Paris", 10, 27),
            ("Tunis spring forward", "Africa/Tunis", 3, 31),
            ("Tunis fall back", "Africa/Tunis", 10, 27),
        ] {
            let fixture = StripMatrix.fixture(firstWeekday: 2, timeZone: zone)
            for hour in [0, 1, 2, 3, 12, 23] {
                let today = fixture.date(2024, month, day, hour: hour)
                let model = WeekStripModel(selectedDay: today, today: today, calendar: fixture.calendar, locale: StripMatrix.english)
                XCTAssertEqual(model.days.count, 7, "\(label) hour \(hour)")
                for index in 1..<7 {
                    let previous = model.days[index - 1].date
                    let current = model.days[index].date
                    let gap = fixture.calendar.dateComponents([.day], from: fixture.calendar.startOfDay(for: previous), to: fixture.calendar.startOfDay(for: current)).day
                    XCTAssertEqual(gap, 1, "\(label) hour \(hour) column \(index) must be one day later")
                }
            }
        }
    }

    private func makeDate(_ string: String, calendar: Calendar) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: string) ?? Date()
    }
}

struct StripFixture {
    let name: String
    let calendar: Calendar

    func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components) ?? Date()
    }
}

enum StripMatrix {
    static let english = Locale(identifier: "en_US")

    static let fixtures: [StripFixture] = {
        var result: [StripFixture] = []
        for firstWeekday in [1, 2, 7] {
            for zone in ["Europe/Paris", "Africa/Tunis", "UTC"] {
                result.append(fixture(firstWeekday: firstWeekday, timeZone: zone))
            }
        }
        return result
    }()

    static func fixture(firstWeekday: Int, timeZone: String) -> StripFixture {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = firstWeekday
        calendar.timeZone = TimeZone(identifier: timeZone) ?? TimeZone(secondsFromGMT: 0) ?? .gmt
        return StripFixture(name: "firstWeekday=\(firstWeekday) tz=\(timeZone)", calendar: calendar)
    }

    struct Anchor {
        let label: String
        let year: Int
        let month: Int
        let day: Int
    }

    static let anchors: [Anchor] = [
        Anchor(label: "owner Mon 2 Nov 2026", year: 2026, month: 11, day: 2),
        Anchor(label: "reference Mon 5 Aug 2024", year: 2024, month: 8, day: 5),
        Anchor(label: "Sun 1 Nov 2026", year: 2026, month: 11, day: 1),
        Anchor(label: "Sat 31 Oct 2026", year: 2026, month: 10, day: 31),
        Anchor(label: "week Mon 5 Aug 2024", year: 2024, month: 8, day: 5),
        Anchor(label: "week Tue 6 Aug 2024", year: 2024, month: 8, day: 6),
        Anchor(label: "week Wed 7 Aug 2024", year: 2024, month: 8, day: 7),
        Anchor(label: "week Thu 8 Aug 2024", year: 2024, month: 8, day: 8),
        Anchor(label: "week Fri 9 Aug 2024", year: 2024, month: 8, day: 9),
        Anchor(label: "week Sat 10 Aug 2024", year: 2024, month: 8, day: 10),
        Anchor(label: "week Sun 11 Aug 2024", year: 2024, month: 8, day: 11),
        Anchor(label: "month end 31 Jul 2024", year: 2024, month: 7, day: 31),
        Anchor(label: "month start 1 Aug 2024", year: 2024, month: 8, day: 1),
        Anchor(label: "leap day 29 Feb 2024", year: 2024, month: 2, day: 29),
        Anchor(label: "leap day before 28 Feb 2024", year: 2024, month: 2, day: 28),
        Anchor(label: "leap day after 1 Mar 2024", year: 2024, month: 3, day: 1),
        Anchor(label: "Paris DST spring 31 Mar 2024", year: 2024, month: 3, day: 31),
        Anchor(label: "Paris DST autumn 27 Oct 2024", year: 2024, month: 10, day: 27),
        Anchor(label: "Tunis 31 Mar 2024", year: 2024, month: 3, day: 31),
        Anchor(label: "Tunis 27 Oct 2024", year: 2024, month: 10, day: 27),
    ]

    static func ownerDay(in calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 2
        components.hour = 12
        return calendar.date(from: components) ?? Date()
    }

    static let ownerDayNumbers = ["30", "31", "01", "02", "03", "04", "05"]
}
