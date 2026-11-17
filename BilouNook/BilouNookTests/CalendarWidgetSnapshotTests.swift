import AppKit
import SwiftUI
import XCTest

#if DEBUG
@MainActor
final class CalendarWidgetSnapshotTests: XCTestCase {
    private struct Scenario {
        let name: String
        let authorization: CalendarAuthorizationState
        let events: [CalendarEvent]
        let selectedDay: Date?
    }

    private var now: Date { makeDate(day: 5, hour: 12) }
    private var calendar: Calendar { makeCalendar() }
    private let locale = Locale(identifier: "en_US")

    func testRenderCalendarWidgetStatesToScreens() throws {
        _ = NSApplication.shared
        let output = screensDirectory()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let scenarios = [
            Scenario(name: "empty", authorization: .authorized, events: [], selectedDay: nil),
            Scenario(name: "1-event", authorization: .authorized, events: [event(title: "Design review", hour: 9)], selectedDay: nil),
            Scenario(
                name: "3-events",
                authorization: .authorized,
                events: [
                    event(title: "Design review", hour: 9),
                    event(title: "Standup", hour: 11, color: .systemGreen),
                    event(title: "Launch", hour: 15, color: .systemOrange),
                ],
                selectedDay: nil
            ),
            Scenario(name: "denied", authorization: .denied, events: [], selectedDay: nil),
            Scenario(
                name: "selected-non-today",
                authorization: .authorized,
                events: [event(title: "Wednesday sync", hour: 10)],
                selectedDay: makeDate(day: 7, hour: 12)
            ),
            Scenario(
                name: "weekend-selected",
                authorization: .authorized,
                events: [event(title: "Long lunch", hour: 13, color: .systemPink)],
                selectedDay: makeDate(day: 3, hour: 12)
            ),
        ]

        for scenario in scenarios {
            let service = makeService(authorization: scenario.authorization, events: scenario.events)
            let data = try renderWidget(service: service, selectedDay: scenario.selectedDay)
            let url = output.appendingPathComponent("calendar-widget-\(scenario.name).png")
            try data.write(to: url)
            XCTAssertGreaterThan(data.count, 2_500, url.lastPathComponent)
            print("[CALENDAR WIDGET] \(url.path)")
        }
    }

    func testRenderFullPageMediaAndCalendarAt420() throws {
        _ = NSApplication.shared
        let output = screensDirectory()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let calendarService = makeService(
            authorization: .authorized,
            events: [
                event(title: "Design review", hour: 9),
                event(title: "Standup", hour: 11, color: .systemGreen),
            ]
        )
        let rendered = try renderPage(calendarService: calendarService, mediaService: makeMediaService())

        let url = output.appendingPathComponent("calendar-widget-full-page.png")
        try rendered.data.write(to: url)
        XCTAssertGreaterThan(rendered.data.count, 4_000, url.lastPathComponent)
        print("[CALENDAR WIDGET] \(url.path)")
    }

    private func renderPage(
        calendarService: CalendarService,
        mediaService: NowPlayingService,
        selectedDay: Date? = nil,
        pageSize: CGSize = CGSize(width: 420, height: 118)
    ) throws -> (data: Data, bitmap: NSBitmapImageRep, scale: CGFloat) {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: pageSize.width, height: pageSize.height)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false

        let root = NotchRootView(
            panel: panel,
            previewMetrics: NotchMetrics(w: pageSize.width, h: pageSize.height, t: 6, b: 20),
            previewShowContent: true,
            registry: ModuleRegistry(modules: [NookModule()])
        )
        .environment(\.calendarService, calendarService)
        .environment(\.calendarInitialSelectedDay, selectedDay)
        .environment(\.nowPlayingService, mediaService)
        .environment(\.mediaSourceAppOverride, sourceApp())
        .frame(width: pageSize.width, height: pageSize.height)
        .overlay {
            CalendarSnapshotOverlay(showHardwareNotch: true)
        }

        let seedDay = selectedDay ?? calendarService.today
        Task { await calendarService.loadEvents(for: seedDay) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))

        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: NSSize(width: pageSize.width, height: pageSize.height))
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw SnapshotError.renderFailed
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.encodingFailed
        }
        let scale = CGFloat(bitmap.pixelsWide) / pageSize.width
        return (png, bitmap, scale)
    }

    private func makeMediaService() -> NowPlayingService {
        let mediaService = NowPlayingService(providers: [], timerEnabled: false)
        mediaService.setSnapshotForTesting(
            NowPlayingSnapshot(
                title: "Midnight City",
                artist: "M83",
                album: "Hurry Up, We're Dreaming",
                artwork: makeArtwork(),
                artworkMimeType: "image/png",
                isPlaying: true,
                elapsed: 84,
                duration: 244,
                bundleIdentifier: "com.apple.Music",
                parentApplicationBundleIdentifier: "com.apple.Music",
                updatedAt: now
            )
        )
        return mediaService
    }

    // MARK: - calendar-strip-fix

    func testRenderStripFixScenarios() throws {
        _ = NSApplication.shared
        let output = screensDirectory()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let tunis = StripMatrix.fixture(firstWeekday: 2, timeZone: "Africa/Tunis")
        let paris = StripMatrix.fixture(firstWeekday: 2, timeZone: "Europe/Paris")
        let french = Locale(identifier: "fr_FR")

        let scenarios: [(name: String, fixture: StripFixture, today: Date, selected: Date?, locale: Locale)] = [
            (
                "today-mon-2026-11-02-fw2-africa-tunis",
                tunis,
                tunis.date(2026, 11, 2),
                nil,
                Locale(identifier: "en_US")
            ),
            (
                "today-sun-2026-11-01-fw2-africa-tunis",
                tunis,
                tunis.date(2026, 11, 1),
                nil,
                Locale(identifier: "en_US")
            ),
            (
                "today-sat-2026-10-31-fw2-africa-tunis",
                tunis,
                tunis.date(2026, 10, 31),
                nil,
                Locale(identifier: "en_US")
            ),
            (
                "selected-sat-2026-11-07-today-2026-11-02-fw2-africa-tunis",
                tunis,
                tunis.date(2026, 11, 2),
                tunis.date(2026, 11, 7),
                Locale(identifier: "en_US")
            ),
            (
                "month-boundary-selected-2024-07-31-today-2024-08-01-fw2-europe-paris",
                paris,
                paris.date(2024, 8, 1),
                paris.date(2024, 7, 31),
                Locale(identifier: "en_US")
            ),
            (
                "french-fr-fr-today-2026-11-02-fw2-europe-paris",
                paris,
                paris.date(2026, 11, 2),
                nil,
                french
            ),
        ]

        for scenario in scenarios {
            let service = makeService(
                authorization: .authorized,
                events: [],
                calendar: scenario.fixture.calendar,
                locale: scenario.locale,
                now: scenario.today
            )
            let rendered = try renderPage(
                calendarService: service,
                mediaService: makeMediaService(),
                selectedDay: scenario.selected
            )
            XCTAssertEqual(rendered.scale, 2, "snapshots render at the 2x backing scale")
            let url = output.appendingPathComponent("calendar-strip-fix-\(scenario.name).png")
            try rendered.data.write(to: url)
            XCTAssertGreaterThan(rendered.data.count, 4_000, url.lastPathComponent)
            print("[CALENDAR STRIP] \(url.path)")
        }
    }

    func testRenderTopBandAt420() throws {
        _ = NSApplication.shared
        let output = screensDirectory()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let fixture = StripMatrix.fixture(firstWeekday: 2, timeZone: "Africa/Tunis")
        let service = makeService(
            authorization: .authorized,
            events: [],
            calendar: fixture.calendar,
            now: fixture.date(2026, 11, 2)
        )
        let rendered = try renderPage(calendarService: service, mediaService: makeMediaService())
        let bandHeight = 36.0
        let cropped = try crop(
            rendered.bitmap,
            to: CGRect(x: 0, y: 0, width: 420, height: bandHeight),
            scale: rendered.scale
        )
        let url = output.appendingPathComponent("calendar-strip-fix-top-band-420x36.png")
        try cropped.write(to: url)
        XCTAssertGreaterThan(cropped.count, 1_000, url.lastPathComponent)
        print("[CALENDAR STRIP] \(url.path)")
    }

    private func crop(_ bitmap: NSBitmapImageRep, to rect: CGRect, scale: CGFloat) throws -> Data {
        let pixels = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        guard let cropped = bitmap.cgImage?.cropping(to: pixels) else {
            throw SnapshotError.renderFailed
        }
        let representation = NSBitmapImageRep(cgImage: cropped)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            throw SnapshotError.encodingFailed
        }
        return png
    }

    func testOwnerMondayRendersSelectedDayInTheFourthColumn() throws {
        _ = NSApplication.shared
        let fixture = StripMatrix.fixture(firstWeekday: 2, timeZone: "Africa/Tunis")
        let today = fixture.date(2026, 11, 2)
        let service = makeService(
            authorization: .authorized,
            events: [],
            calendar: fixture.calendar,
            now: today
        )

        let output = screensDirectory()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let rendered = try renderWidgetBitmap(service: service, selectedDay: nil, showsOverlay: false)
        let overlay = try renderWidgetBitmap(service: service, selectedDay: nil)
        let url = output.appendingPathComponent("calendar-strip-fix-repro-mon-2-nov-2026-fw2-tunis.png")
        try overlay.data.write(to: url)
        print("[CALENDAR STRIP] \(url.path)")

        print("[CALENDAR STRIP] ink profile \(inkProfile(in: rendered.bitmap, scale: rendered.scale))")
        if let blue = blueInkBounds(in: rendered.bitmap) {
            print("[CALENDAR STRIP] blue ink \(blue.minX / rendered.scale)...\(blue.maxX / rendered.scale)")
        }
        let ink = blueInkBounds(in: rendered.bitmap)
        let bounds = try XCTUnwrap(ink, "the selected (blue) number must be visible")
        let centerX = bounds.midX / rendered.scale
        let centerY = bounds.midY / rendered.scale
        XCTAssertEqual(
            centerX,
            CalendarWidgetMetrics.columnFrames[3].midX,
            accuracy: 2.5,
            "the selected number must render in the fourth column"
        )
        XCTAssertEqual(
            centerY,
            CalendarWidgetMetrics.selectedNumberCenterY,
            accuracy: 2.5,
            "the selected number must render on its baseline centre"
        )
    }

    private func blueInkBounds(in bitmap: NSBitmapImageRep) -> CGRect? {
        inkBounds(in: bitmap) { red, green, blue in
            blue > 0.6 && blue - red > 0.25 && blue - green > 0.15
        }
    }

    private func inkBounds(
        in bitmap: NSBitmapImageRep,
        matching matches: (_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> Bool
    ) -> CGRect? {
        var minX = Int.max
        var minY = Int.max
        var maxX = Int.min
        var maxY = Int.min
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                guard matches(color.redComponent, color.greenComponent, color.blueComponent) else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard minX <= maxX, minY <= maxY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func inkProfile(in bitmap: NSBitmapImageRep, scale: CGFloat) -> String {
        var occupied = Set<Int>()
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                guard max(color.redComponent, color.greenComponent, color.blueComponent) > 0.35 else { continue }
                occupied.insert(Int(CGFloat(x) / scale))
            }
        }
        let sorted = occupied.sorted()
        var runs: [String] = []
        var start: Int?
        var previous = -10
        for value in sorted {
            if value != previous + 1 {
                if let start { runs.append("\(start)-\(previous)") }
                start = value
            }
            previous = value
        }
        if let start { runs.append("\(start)-\(previous)") }
        return runs.joined(separator: " ")
    }

    private func renderWidget(service: CalendarService, selectedDay: Date?) throws -> Data {
        try renderWidgetBitmap(service: service, selectedDay: selectedDay).data
    }

    private func renderWidgetBitmap(
        service: CalendarService,
        selectedDay: Date?,
        showsOverlay: Bool = true
    ) throws -> (data: Data, bitmap: NSBitmapImageRep, scale: CGFloat) {
        let seedDay = selectedDay ?? service.today
        Task { await service.loadEvents(for: seedDay) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let widget = CalendarWidgetView(initialSelectedDay: selectedDay)
            .environment(\.calendarService, service)
            .frame(width: CalendarWidgetMetrics.width, height: CalendarWidgetMetrics.height)
            .background(Color.black)
            .overlay {
                if showsOverlay {
                    CalendarSnapshotOverlay(showHardwareNotch: false)
                }
            }

        let host = NSHostingView(rootView: widget)
        host.frame = NSRect(
            origin: .zero,
            size: NSSize(width: CalendarWidgetMetrics.width, height: CalendarWidgetMetrics.height)
        )
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw SnapshotError.renderFailed
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.encodingFailed
        }
        let scale = CGFloat(bitmap.pixelsWide) / CalendarWidgetMetrics.width
        return (png, bitmap, scale)
    }

    private func makeService(
        authorization: CalendarAuthorizationState,
        events: [CalendarEvent],
        calendar: Calendar? = nil,
        locale: Locale? = nil,
        now: Date? = nil
    ) -> CalendarService {
        let resolvedNow = now ?? self.now
        return CalendarService(
            source: SnapshotCalendarSource(authorizationState: authorization, events: events),
            calendar: calendar ?? self.calendar,
            locale: locale ?? self.locale,
            now: { resolvedNow }
        )
    }

    private func event(title: String, hour: Int, color: NSColor = .systemBlue) -> CalendarEvent {
        let start = makeDate(day: 5, hour: hour)
        return CalendarEvent(
            id: title,
            title: title,
            start: start,
            end: start.addingTimeInterval(3600),
            isAllDay: false,
            color: color
        )
    }

    private func sourceApp() -> MediaSourceApp {
        let image = NSImage(size: NSSize(width: 40, height: 40))
        image.lockFocus()
        NSColor(calibratedRed: 0.98, green: 0.31, blue: 0.42, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 40, height: 40), xRadius: 9, yRadius: 9).fill()
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: NSRect(x: 11, y: 11, width: 18, height: 18)).fill()
        image.unlockFocus()
        return MediaSourceApp(bundleIdentifier: "com.apple.Music", name: "Music", icon: image)
    }

    private func makeArtwork() -> Data? {
        let image = NSImage(size: NSSize(width: 150, height: 150))
        image.lockFocus()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.16, green: 0.31, blue: 0.82, alpha: 1),
            NSColor(calibratedRed: 0.74, green: 0.15, blue: 0.56, alpha: 1),
        ])?.draw(in: NSRect(x: 0, y: 0, width: 150, height: 150), angle: 35)
        NSColor.white.withAlphaComponent(0.22).setFill()
        NSBezierPath(ovalIn: NSRect(x: 34, y: 34, width: 82, height: 82)).fill()
        NSColor.black.withAlphaComponent(0.28).setFill()
        NSBezierPath(ovalIn: NSRect(x: 61, y: 61, width: 28, height: 28)).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func screensDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("build/screens")
    }
    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func makeDate(day: Int, hour: Int) -> Date {
        let calendar = makeCalendar()
        return calendar.date(from: DateComponents(year: 2024, month: 8, day: day, hour: hour)) ?? Date()
    }
}

private final class SnapshotCalendarSource: CalendarEventSource {
    let authorizationState: CalendarAuthorizationState
    let eventsByDay: [CalendarEvent]

    init(authorizationState: CalendarAuthorizationState, events: [CalendarEvent]) {
        self.authorizationState = authorizationState
        self.eventsByDay = events
    }

    func requestAccess() async -> CalendarAuthorizationState {
        authorizationState
    }

    func events(for day: Date, calendar: Calendar) -> [CalendarEvent] {
        eventsByDay.filter { calendar.isDate($0.start, inSameDayAs: day) }
    }
}

private struct CalendarSnapshotOverlay: View {
    let showHardwareNotch: Bool

    var body: some View {
        Canvas { context, size in
            var grid = Path()
            for x in stride(from: 0, through: size.width, by: 5) {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0, through: size.height, by: 5) {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(.white.opacity(0.07)), lineWidth: 0.5)

            if size.width > 300 {
                outline(CalendarWidgetMetrics.monthLabelFrame.offsetBy(dx: 196, dy: 34), in: &context, color: Color(red: 1, green: 0, blue: 1))
                let origin = CGPoint(x: 196 + CalendarWidgetMetrics.stripFrame.minX, y: 34)
                outline(CGRect(x: origin.x, y: origin.y, width: CalendarWidgetMetrics.stripFrame.width, height: CalendarWidgetMetrics.stripHeight), in: &context, color: Color(red: 0, green: 1, blue: 1))
                for frame in CalendarWidgetMetrics.columnFrames {
                    outline(frame.offsetBy(dx: 196, dy: 34), in: &context, color: .green)
                }
                outline(CalendarWidgetMetrics.eventsArea.offsetBy(dx: 196, dy: 34), in: &context, color: .yellow)
            } else {
                outline(CalendarWidgetMetrics.monthLabelFrame, in: &context, color: Color(red: 1, green: 0, blue: 1))
                outline(CalendarWidgetMetrics.stripFrame, in: &context, color: Color(red: 0, green: 1, blue: 1))
                for frame in CalendarWidgetMetrics.columnFrames {
                    outline(frame, in: &context, color: .green)
                }
                outline(CalendarWidgetMetrics.eventsArea, in: &context, color: .yellow)
                for frame in CalendarWidgetMetrics.eventRowFrames {
                    outline(frame, in: &context, color: .orange)
                }
                outline(CalendarWidgetMetrics.moreFrame, in: &context, color: .orange)
            }

            if showHardwareNotch {
                let frame = CGRect(x: (size.width - 179) / 2, y: 0, width: 179, height: 32)
                context.fill(Path(frame), with: .color(Color(red: 1, green: 0, blue: 1).opacity(0.35)))
                context.stroke(Path(frame), with: .color(Color(red: 1, green: 0, blue: 1).opacity(0.9)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    private func outline(_ frame: CGRect, in context: inout GraphicsContext, color: Color) {
        context.stroke(Path(frame), with: .color(color.opacity(0.85)), lineWidth: 0.75)
    }
}

private enum SnapshotError: Error {
    case renderFailed
    case encodingFailed
}
#endif
