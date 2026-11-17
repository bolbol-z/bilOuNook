import AppKit
import SwiftUI

enum CalendarSettingsLink {
    static func open() {
        guard let url = URL(string: CalendarWidgetMetrics.settingsURLString) else { return }
        NSWorkspace.shared.open(url)
    }
}

struct CalendarWidgetView: View {
    @Environment(\.calendarService) private var service
    @Environment(\.calendarInitialSelectedDay) private var initialSelectedDay
    @State private var selectedDay: Date?
    @State private var scrollAccumulator: CGFloat = 0
    @State private var scrollAnimationToken = 0
    @State private var slideStart: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(initialSelectedDay: Date? = nil) {
        _selectedDay = State(initialValue: initialSelectedDay)
    }

    private var notchState: NotchState { .shared }

    private var effectiveSelectedDay: Date {
        selectedDay ?? initialSelectedDay ?? service.today
    }

    private var model: WeekStripModel {
        WeekStripModel(
            selectedDay: effectiveSelectedDay,
            today: service.today,
            calendar: service.calendar,
            locale: service.locale
        )
    }

    var body: some View {
        let model = model
        ZStack(alignment: .topLeading) {
            weekStrip(model)
            content(model)
            CalendarWeekStripCatcher(onSelect: select, onScroll: scroll)
                .frame(width: CalendarWidgetMetrics.stripFrame.width, height: CalendarWidgetMetrics.stripHeight)
                .position(x: CalendarWidgetMetrics.stripFrame.midX, y: CalendarWidgetMetrics.stripFrame.midY)
            monthLabel(model)
        }
        .background(PointerProbe(token: "calendar.weekStrip"))
        .frame(width: CalendarWidgetMetrics.width, height: CalendarWidgetMetrics.height, alignment: .topLeading)
        .clipped()
        .animation(CalendarAnimations.respectingReduceMotion(CalendarAnimations.dayHighlight, reduceMotion: reduceMotion), value: model.selectedDay)
        .animation(CalendarAnimations.respectingReduceMotion(CalendarAnimations.eventsReveal, reduceMotion: reduceMotion), value: model.selectedDay)
        .task(id: notchState.phase) {
            guard notchState.phase == .open || notchState.phase == .opening else { return }
            await service.requestAccessIfNeeded()
        }
        .task(id: "\(model.selectedDay.timeIntervalSince1970)-\(service.revision)") {
            await service.loadEvents(for: model.selectedDay)
        }
        .layoutProbe("nook.calendar")
        .onChange(of: service.dayChangeCount) { _, _ in
            selectedDay = nil
            scrollAccumulator = 0
        }
    }

    private func monthLabel(_ model: WeekStripModel) -> some View {
        Button(action: resetToToday) {
            Text(model.monthLabel)
                .font(.system(size: CalendarWidgetMetrics.monthFontSize, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: CalendarWidgetMetrics.monthLabelFrame.width, height: CalendarWidgetMetrics.monthLabelFrame.height, alignment: .leading)
                .contentTransition(.opacity)
        }
        .buttonStyle(.plain)
        .frame(width: CalendarWidgetMetrics.monthLabelFrame.width, height: CalendarWidgetMetrics.monthLabelFrame.height)
        .position(x: CalendarWidgetMetrics.monthLabelFrame.midX, y: CalendarWidgetMetrics.monthLabelFrame.midY)
        .animation(CalendarAnimations.respectingReduceMotion(CalendarAnimations.headerSwap, reduceMotion: reduceMotion), value: model.monthLabel)
        .accessibilityLabel("Return to today")
    }

    private func weekStrip(_ model: WeekStripModel) -> some View {
        ZStack(alignment: .topLeading) {
            partialDay(model.previousPartial, frame: CalendarWidgetMetrics.previousPartialFrame)
            ForEach(Array(model.days.enumerated()), id: \.offset) { index, day in
                if CalendarWidgetMetrics.columnFrames.indices.contains(index) {
                    dayColumn(day, frame: CalendarWidgetMetrics.columnFrames[index])
                }
            }
            partialDay(model.nextPartial, frame: CalendarWidgetMetrics.nextPartialColumnFrame)
        }
        .frame(
            width: CalendarWidgetMetrics.stripFrame.width,
            height: CalendarWidgetMetrics.stripFrame.height,
            alignment: .topLeading
        )
        .clipped()
        .mask { stripFadeMask }
        .keyframeAnimator(initialValue: CGFloat.zero, trigger: scrollAnimationToken) { content, shift in
            content.offset(x: shift)
        } keyframes: { _ in
            KeyframeTrack(\.self) {
                // Jump to the pre-scroll position so the new window looks
                // identical to the previous frame, then slide the 24pt step.
                CubicKeyframe(slideStart, duration: 0)
                if reduceMotion {
                    CubicKeyframe(0, duration: Animations.reduceMotionDuration)
                } else {
                    SpringKeyframe(0, spring: InteractionMotion.calendarStripScrollSpring)
                }
            }
        }
        .position(x: CalendarWidgetMetrics.stripFrame.midX, y: CalendarWidgetMetrics.stripFrame.midY)
    }

    private var stripFadeMask: some View {
        let width = CalendarWidgetMetrics.stripFrame.width
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: CalendarWidgetMetrics.previousPartialFrame.minX / width),
                .init(color: .white, location: CalendarWidgetMetrics.columnFrames[0].minX / width),
                .init(color: .white, location: CalendarWidgetMetrics.nextPartialFrame.minX / width),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func dayColumn(_ day: WeekStripDay, frame: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Text(day.isSelected ? day.shortHeader : day.headerLetter)
                .font(.system(size: CalendarWidgetMetrics.headerFontSize, weight: .semibold))
                .foregroundStyle(headerColor(day))
                .lineLimit(1)
                .frame(width: CalendarWidgetMetrics.columnWidth, height: CalendarWidgetMetrics.headerFrame.height)
                .position(x: frame.midX, y: CalendarWidgetMetrics.headerCenterY)

            Text(day.dayNumber)
                .font(.system(
                    size: day.isSelected ? CalendarWidgetMetrics.selectedNumberFontSize : CalendarWidgetMetrics.numberFontSize,
                    weight: day.isSelected ? .semibold : .medium
                ))
                .foregroundStyle(numberColor(day))
                .monospacedDigit()
                .frame(
                    width: CalendarWidgetMetrics.columnWidth,
                    height: day.isSelected ? CalendarWidgetMetrics.selectedNumberHeight : CalendarWidgetMetrics.numberHeight
                )
                .position(
                    x: frame.midX,
                    y: day.isSelected ? CalendarWidgetMetrics.selectedNumberCenterY : CalendarWidgetMetrics.numberCenterY
                )
        }
        .frame(
            width: CalendarWidgetMetrics.stripFrame.width,
            height: CalendarWidgetMetrics.stripFrame.height,
            alignment: .topLeading
        )
    }

    private func partialDay(_ day: WeekStripDay, frame: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Text(day.headerLetter)
                .font(.system(size: CalendarWidgetMetrics.headerFontSize, weight: .semibold))
                .foregroundStyle(headerColor(day))
                .lineLimit(1)
                .frame(width: CalendarWidgetMetrics.columnWidth, height: CalendarWidgetMetrics.headerFrame.height)
                .position(x: frame.midX, y: CalendarWidgetMetrics.headerCenterY)

            Text(day.dayNumber)
                .font(.system(size: CalendarWidgetMetrics.numberFontSize, weight: .medium))
                .foregroundStyle(numberColor(day))
                .monospacedDigit()
                .frame(width: CalendarWidgetMetrics.columnWidth, height: CalendarWidgetMetrics.numberHeight)
                .position(x: frame.midX, y: CalendarWidgetMetrics.numberCenterY)
        }
        .frame(
            width: CalendarWidgetMetrics.stripFrame.width,
            height: CalendarWidgetMetrics.stripFrame.height,
            alignment: .topLeading
        )
        .accessibilityHidden(true)
    }

    private func headerColor(_ day: WeekStripDay) -> Color {
        if day.isSelected { return Color.white.opacity(CalendarWidgetMetrics.selectedHeaderOpacity) }
        if day.isWeekend {
            return Color(cgColor: CalendarWidgetMetrics.weekendRed)
                .opacity(CalendarWidgetMetrics.weekendOpacity)
        }
        return Color.white.opacity(CalendarWidgetMetrics.headerOpacity)
    }

    private func numberColor(_ day: WeekStripDay) -> Color {
        if day.isSelected {
            return day.isToday ? Color(nsColor: .systemBlue) : Color.white
        }
        if day.isWeekend {
            return Color(cgColor: CalendarWidgetMetrics.weekendRed)
                .opacity(CalendarWidgetMetrics.weekendOpacity)
        }
        return Color.white.opacity(CalendarWidgetMetrics.numberOpacity)
    }

    @ViewBuilder
    private func content(_ model: WeekStripModel) -> some View {
        switch service.authorizationState {
        case .notDetermined:
            EmptyView()
        case .denied, .restricted:
            deniedView
        case .authorized:
            let events = service.eventsForSelectedDay
            if events.isEmpty {
                emptyView
            } else {
                eventsView(events)
            }
        }
    }

    private func eventsView(_ events: [CalendarEvent]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(events.prefix(CalendarWidgetMetrics.eventRowCount).enumerated()), id: \.element.id) { index, event in
                eventRow(event, frame: CalendarWidgetMetrics.eventRowFrames[index])
            }

            if events.count > CalendarWidgetMetrics.eventRowCount {
                Text("+\(events.count - CalendarWidgetMetrics.eventRowCount) more")
                    .font(.system(size: CalendarWidgetMetrics.moreFontSize, weight: .regular))
                    .foregroundStyle(Color.white.opacity(CalendarWidgetMetrics.moreOpacity))
                    .lineLimit(1)
                    .frame(width: CalendarWidgetMetrics.moreFrame.width, height: CalendarWidgetMetrics.moreFrame.height, alignment: .leading)
                    .position(x: CalendarWidgetMetrics.moreFrame.midX, y: CalendarWidgetMetrics.moreFrame.midY)
            }
        }
        .id(model.selectedDay)
        .transition(.opacity.combined(with: .offset(y: CalendarAnimations.eventsOffset)))
    }

    private func eventRow(_ event: CalendarEvent, frame: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color(nsColor: event.color))
                .frame(width: CalendarWidgetMetrics.colorBarWidth, height: CalendarWidgetMetrics.colorBarHeight)
                .position(x: frame.minX + CalendarWidgetMetrics.colorBarWidth / 2, y: frame.midY)

            Text(event.title)
                .font(.system(size: CalendarWidgetMetrics.eventTitleFontSize, weight: .medium))
                .foregroundStyle(Color.white.opacity(CalendarWidgetMetrics.eventTitleOpacity))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: CalendarWidgetMetrics.eventTitleWidth, height: frame.height, alignment: .leading)
                .position(x: CalendarWidgetMetrics.eventTitleX + CalendarWidgetMetrics.eventTitleWidth / 2, y: frame.midY)

            Text(timeLabel(for: event))
                .font(.system(size: CalendarWidgetMetrics.eventTimeFontSize, weight: .regular))
                .foregroundStyle(Color.white.opacity(CalendarWidgetMetrics.eventTimeOpacity))
                .lineLimit(1)
                .frame(width: CalendarWidgetMetrics.eventTimeWidth, height: frame.height, alignment: .trailing)
                .position(x: CalendarWidgetMetrics.eventTimeX + CalendarWidgetMetrics.eventTimeWidth / 2, y: frame.midY)
        }
    }

    private var emptyView: some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(Color.white.opacity(CalendarWidgetMetrics.emptyIconOpacity))
                .position(CalendarWidgetMetrics.emptyIconCenter)

            Text("Nothing for today")
                .font(.system(size: CalendarWidgetMetrics.emptyTextFontSize, weight: .regular))
                .foregroundStyle(Color.white.opacity(CalendarWidgetMetrics.emptyTextOpacity))
                .frame(width: CalendarWidgetMetrics.eventsArea.width, height: 13)
                .position(x: CalendarWidgetMetrics.width / 2, y: CalendarWidgetMetrics.emptyTextCenterY)
        }
    }

    private var deniedView: some View {
        ZStack(alignment: .topLeading) {
            Text("Calendar access is off")
                .font(.system(size: CalendarWidgetMetrics.deniedTextFontSize, weight: .regular))
                .foregroundStyle(Color.white.opacity(CalendarWidgetMetrics.emptyTextOpacity))
                .frame(width: CalendarWidgetMetrics.eventsArea.width, height: 13)
                .position(x: CalendarWidgetMetrics.width / 2, y: CalendarWidgetMetrics.deniedTextCenterY)

            Button(action: CalendarSettingsLink.open) {
                Text("Open Settings")
                    .font(.system(size: CalendarWidgetMetrics.settingsButtonFontSize, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: CalendarWidgetMetrics.settingsButtonFrame.width, height: CalendarWidgetMetrics.settingsButtonFrame.height)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
            .position(x: CalendarWidgetMetrics.settingsButtonFrame.midX, y: CalendarWidgetMetrics.settingsButtonFrame.midY)
            .accessibilityLabel("Open Settings")
        }
    }

    private func timeLabel(for event: CalendarEvent) -> String {
        guard !event.isAllDay else { return "All day" }
        let formatter = DateFormatter()
        formatter.calendar = service.calendar
        formatter.locale = service.locale
        formatter.timeZone = service.calendar.timeZone
        formatter.dateFormat = "H:mm"
        return "\(formatter.string(from: event.start))–\(formatter.string(from: event.end))"
    }

    private func select(_ x: CGFloat) {
        let absoluteX = x + CalendarWidgetMetrics.stripFrame.minX
        selectedDay = WeekStripHitTest.day(atX: absoluteX, model: model).date
        scrollAccumulator = 0
    }

    private func scroll(_ deltaX: CGFloat) {
        let resolution = WeekStripScroll.resolve(
            selectedDay: effectiveSelectedDay,
            calendar: service.calendar,
            accumulated: scrollAccumulator,
            deltaX: deltaX
        )
        scrollAccumulator = resolution.remainder
        guard resolution.didStep else { return }
        selectedDay = resolution.selectedDay
        slideStart = resolution.slideOffset
        scrollAnimationToken += 1
    }

    private func resetToToday() {
        selectedDay = nil
        scrollAccumulator = 0
        slideStart = 0
        scrollAnimationToken += 1
    }
}
