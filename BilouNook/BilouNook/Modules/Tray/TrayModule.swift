import AppKit
import Observation
import SwiftUI

struct TrayModule: NotchModule {
    let id = "files"
    let title = "Files"
    let icon = "tray.fill"
    let liveActivityPriority = 5

    var preferredSize: CGSize {
        // Match the NookModule canvas so switching tabs never resizes the panel.
        CGSize(
            width: NookLayout.nookCanvasWidth,
            height: NotchGeometryCache.shared.current.geometry.notchRect.height + 2 + NookLayout.rowHeight + NookLayout.bottomPadding
        )
    }

    var expandedView: AnyView {
        AnyView(FilesTrayView())
    }
}

enum TimerFormat {
    static func string(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}

struct TimerBandBadge: View {
    let activeModuleID: String?
    @State private var svc = TimerService.shared
    var body: some View {
        if svc.isActive && activeModuleID != "timer" {
            HStack(spacing: 3) {
                Image(systemName: "timer").font(.system(size: 9, weight: .semibold))
                Text(svc.state == .finished ? "Done" : TimerFormat.string(svc.displaySeconds))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(Capsule().fill(Color(red: 1.0, green: 0.2706, blue: 0.2275).opacity(0.9)))
            .transition(.opacity)
            .layoutProbe("band.timerBadge")
        }
    }
}

struct TimerModule: NotchModule {
    let id = "timer"
    let title = "Timer"
    let icon = "timer"
    let liveActivityPriority = 5

    var preferredSize: CGSize {
        CGSize(
            width: NookLayout.nookCanvasWidth,
            height: TimerLayout.panelHeight(notchHeight: NotchGeometryCache.shared.current.geometry.notchRect.height)
        )
    }

    var expandedView: AnyView {
        AnyView(TimerPageView())
    }
}

extension TimerFormat {
    static func island(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%dh%02d", h, m) : String(format: "%02d:%02d", m, sec)
    }
}

enum SystemSounds {
    static let fallback = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
    static let names: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        let n = files.filter { $0.hasSuffix(".aiff") }.map { String($0.dropLast(5)) }.sorted()
        return n.isEmpty ? fallback : n
    }()
}

enum TimerSoundCatalog {
    static let stopPlayingTitle = "Stop playing"
    static let items: [String] = [stopPlayingTitle] + SystemSounds.names
    static let perPage = 9
    static var pageCount: Int { max(1, (items.count + perPage - 1) / perPage) }
}

@MainActor
final class AlarmPlayer {
    static let shared = AlarmPlayer()
    private var sound: NSSound?
    private var stopTask: Task<Void, Never>?
    func play(_ name: String, loop: Bool, maxSeconds: Double) {
        stop()
        guard let s = NSSound(contentsOfFile: "/System/Library/Sounds/\(name).aiff", byReference: true) else { return }
        s.loops = loop
        s.play()
        sound = s
        guard loop, maxSeconds > 0 else { return }
        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(maxSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }
    func stop() {
        stopTask?.cancel(); stopTask = nil
        sound?.stop(); sound = nil
    }
}

@MainActor
@Observable
final class TimerService {
    static let shared = TimerService(defaults: UserDefaults(suiteName: "com.bilounook.timer"))

    enum State: Equatable { case idle, running, paused, finished }
    enum Mode: String { case timer, pomodoro }
    enum Phase: Equatable { case focus, rest }
    enum EndAction: Equatable {
        case sound(String)
        case stopPlaying
        var storage: String {
            switch self { case .sound(let n): return "sound:\(n)"; case .stopPlaying: return "stop" }
        }
        init(storage: String?) {
            if storage == "stop" { self = .stopPlaying }
            else if let s = storage, s.hasPrefix("sound:"), s.count > 6 { self = .sound(String(s.dropFirst(6))) }
            else { self = .sound("Glass") }
        }
    }
    struct Announcement: Equatable {
        let id: Int
        let title: String
        let subtitle: String
        let symbol: String
        let isFinal: Bool
    }

    private(set) var state: State = .idle
    private(set) var phase: Phase = .focus
    private(set) var round = 1
    private(set) var totalSeconds = 0
    private(set) var displaySeconds = 0
    private(set) var endsAt: Date?
    private(set) var announcement: Announcement?
    var mode: Mode = .timer
    var pickHours = 0
    var pickMinutes = 1
    var pickSeconds = 0
    var focusMinutes = 25
    var restMinutes = 5
    var rounds = 4
    var endAction: EndAction = .sound("Glass")

    @ObservationIgnored var clock: () -> Date = { Date() }
    @ObservationIgnored var playAlarm: (String, Bool) -> Void = { _, _ in }
    @ObservationIgnored var stopAlarm: () -> Void = {}
    @ObservationIgnored var stopMedia: () -> Void = {}
    @ObservationIgnored var finishHaptic: () -> Void = {}
    @ObservationIgnored var requestAttention: (TimeInterval) -> Void = { _ in }
    @ObservationIgnored var releaseAttention: () -> Void = {}
    @ObservationIgnored private var defaults: UserDefaults?
    @ObservationIgnored private var endDate = Date.distantPast
    @ObservationIgnored private var pausedRemaining: TimeInterval = 0
    @ObservationIgnored private var tickToken: LifecycleManager.Token?
    @ObservationIgnored private var announcementTask: Task<Void, Never>?
    @ObservationIgnored private var announcementCounter = 0

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        loadPrefs()
    }

    var isActive: Bool { state != .idle }
    var isRunning: Bool { state == .running }
    var pickedTotal: Int { pickHours * 3600 + pickMinutes * 60 + pickSeconds }
    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        let p = 1 - Double(displaySeconds) / Double(totalSeconds)
        return p.isFinite ? min(max(p, 0), 1) : 0
    }

    // MARK: controls
    func start() {
        guard state == .idle else { return }
        stopAlarm()
        announcementTask?.cancel(); announcement = nil
        phase = .focus
        round = 1
        switch mode {
        case .timer:
            guard pickedTotal > 0 else { return }
            begin(seconds: pickedTotal)
        case .pomodoro:
            guard focusMinutes > 0, restMinutes > 0, rounds > 0 else { return }
            begin(seconds: focusMinutes * 60)
        }
        savePrefs()
    }
    func pause() {
        guard state == .running else { return }
        pausedRemaining = max(0, endDate.timeIntervalSince(clock()))
        displaySeconds = Int(pausedRemaining.rounded(.up))
        endsAt = nil
        state = .paused
        stopTicking()
    }
    func resume() {
        guard state == .paused else { return }
        endDate = clock().addingTimeInterval(pausedRemaining)
        endsAt = endDate
        state = .running
        startTicking()
    }
    func cancel() {
        stopAlarm()
        announcementTask?.cancel(); announcement = nil
        stopTicking()
        state = .idle
        displaySeconds = 0
        endsAt = nil
        releaseAttention()
    }
    func stopFinished() { cancel() }
    func restart() { cancel(); start() }
    func skipPhase() {
        guard mode == .pomodoro, state == .running || state == .paused else { return }
        stopTicking()
        state = .running
        phaseCompleted(silent: true)
    }
    func selectSound(_ name: String) { endAction = .sound(name); savePrefs() }
    func selectStopPlaying() { endAction = .stopPlaying; savePrefs() }

    // MARK: engine
    func tick() {
        guard state == .running else { return }
        let remaining = max(0, endDate.timeIntervalSince(clock()))
        let shown = Int(remaining.rounded(.up))
        if shown != displaySeconds { displaySeconds = shown }
        if remaining <= 0 { phaseCompleted(silent: false) }
    }
    private func begin(seconds: Int) {
        totalSeconds = seconds
        displaySeconds = seconds
        endDate = clock().addingTimeInterval(TimeInterval(seconds))
        endsAt = endDate
        state = .running
        startTicking()
    }
    private func phaseCompleted(silent: Bool) {
        stopTicking()
        switch mode {
        case .timer:
            finishAll(title: "Time's up", subtitle: "\(TimerFormat.string(totalSeconds)) timer finished", silent: silent)
        case .pomodoro:
            if phase == .focus {
                if round >= rounds {
                    finishAll(title: "All \(rounds) rounds complete", subtitle: "Great focus session", silent: silent)
                } else {
                    phase = .rest
                    announce(title: "Focus \(round) of \(rounds) complete",
                             subtitle: "Break · \(TimerFormat.string(restMinutes * 60)) started",
                             symbol: "cup.and.saucer.fill", isFinal: false)
                    begin(seconds: restMinutes * 60)
                    if !silent { cue(attention: 6) }
                }
            } else {
                round += 1
                phase = .focus
                announce(title: "Break over",
                         subtitle: "Focus \(round) of \(rounds) · \(TimerFormat.string(focusMinutes * 60)) started",
                         symbol: "flame.fill", isFinal: false)
                begin(seconds: focusMinutes * 60)
                if !silent { cue(attention: 6) }
            }
        }
    }
    private func cue(attention: TimeInterval) {
        switch endAction {
        case .sound(let name): playAlarm(name, false)
        case .stopPlaying: stopMedia()
        }
        finishHaptic()
        requestAttention(attention)
    }
    private func finishAll(title: String, subtitle: String, silent: Bool) {
        state = .finished
        displaySeconds = 0
        endsAt = nil
        announce(title: title, subtitle: subtitle, symbol: "bell.fill", isFinal: true)
        guard !silent else { return }
        switch endAction {
        case .sound(let name): playAlarm(name, true)
        case .stopPlaying: stopMedia()
        }
        finishHaptic()
        requestAttention(15)
    }
    private func announce(title: String, subtitle: String, symbol: String, isFinal: Bool) {
        announcementTask?.cancel()
        announcementCounter += 1
        let a = Announcement(id: announcementCounter, title: title, subtitle: subtitle, symbol: symbol, isFinal: isFinal)
        announcement = a
        guard !isFinal else { return }
        announcementTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled, let self, self.announcement?.id == a.id else { return }
            self.announcement = nil
        }
    }
    private func startTicking() {
        stopTicking()
        tickToken = LifecycleManager.shared.timer("timer.tick", interval: 0.25, tolerance: 0.05, tier: .essential) { [weak self] in
            self?.tick()
        }
    }
    private func stopTicking() { tickToken?.cancel(); tickToken = nil }

    // MARK: persistence
    private func savePrefs() {
        guard let d = defaults else { return }
        d.set(mode.rawValue, forKey: "mode")
        d.set(pickHours, forKey: "h"); d.set(pickMinutes, forKey: "m"); d.set(pickSeconds, forKey: "s")
        d.set(focusMinutes, forKey: "focus"); d.set(restMinutes, forKey: "rest"); d.set(rounds, forKey: "rounds")
        d.set(endAction.storage, forKey: "end")
    }
    private func loadPrefs() {
        guard let d = defaults else { return }
        if let m = d.string(forKey: "mode"), let mm = Mode(rawValue: m) { mode = mm }
        if d.object(forKey: "h") != nil {
            pickHours = min(23, max(0, d.integer(forKey: "h")))
            pickMinutes = min(59, max(0, d.integer(forKey: "m")))
            pickSeconds = min(59, max(0, d.integer(forKey: "s")))
        }
        if d.object(forKey: "focus") != nil {
            focusMinutes = min(120, max(1, d.integer(forKey: "focus")))
            restMinutes = min(60, max(1, d.integer(forKey: "rest")))
            rounds = min(12, max(1, d.integer(forKey: "rounds")))
        }
        endAction = EndAction(storage: d.string(forKey: "end"))
    }

    func installSideEffects() {
        playAlarm = { name, loop in MainActor.assumeIsolated { AlarmPlayer.shared.play(name, loop: loop, maxSeconds: 30) } }
        stopAlarm = { MainActor.assumeIsolated { AlarmPlayer.shared.stop() } }
        finishHaptic = { MainActor.assumeIsolated { HapticsService.timerFinish() } }
    }
}

enum TimerPalette {
    static let blue = Color(red: 0, green: 0.4784, blue: 1.0)
    static let green = Color(red: 0.2039, green: 0.7804, blue: 0.3490)
    static let orange = Color(red: 1.0, green: 0.5843, blue: 0.0)
    static let red = Color(red: 1.0, green: 0.2706, blue: 0.2275)
    static let focus = Color(red: 1.0, green: 0.4196, blue: 0.2392)
    static let gray = Color(red: 0.5569, green: 0.5569, blue: 0.5765)
    @MainActor static func accent(for svc: TimerService) -> Color {
        svc.mode == .pomodoro ? (svc.phase == .focus ? focus : green) : blue
    }
}

final class WheelSurfaceView: PointerProbeView {
    var onScroll: (CGFloat, Bool, NSEvent.Phase, NSEvent.Phase) -> Void = { _, _, _, _ in }
    var onDrag: (CGFloat, Bool) -> Void = { _, _ in }
    private var lastY: CGFloat = 0
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func scrollWheel(with event: NSEvent) {
        onScroll(event.scrollingDeltaY, event.hasPreciseScrollingDeltas, event.phase, event.momentumPhase)
    }
    override func mouseDown(with event: NSEvent) { lastY = convert(event.locationInWindow, from: nil).y }
    override func mouseDragged(with event: NSEvent) {
        let y = convert(event.locationInWindow, from: nil).y
        let dy = y - lastY
        lastY = y
        onDrag(dy, false)
    }
    override func mouseUp(with event: NSEvent) { onDrag(0, true) }
}

struct WheelSurface: NSViewRepresentable {
    var onScroll: (CGFloat, Bool, NSEvent.Phase, NSEvent.Phase) -> Void
    var onDrag: (CGFloat, Bool) -> Void
    func makeNSView(context: Context) -> WheelSurfaceView {
        let v = WheelSurfaceView()
        v.token = "timer.columns"
        v.onScroll = onScroll
        v.onDrag = onDrag
        return v
    }
    func updateNSView(_ v: WheelSurfaceView, context: Context) {
        v.onScroll = onScroll
        v.onDrag = onDrag
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct PillButton: View {
    enum Style { case filled, tinted }
    let title: String
    let color: Color
    var enabled = true
    var style: Style = .filled
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(style == .filled ? Color.white : color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Capsule().fill(style == .filled ? color : color.opacity(0.18)))
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .layoutProbe("timer.primary")
    }
}

struct ModeSwitch: View {
    let mode: TimerService.Mode
    let onChange: (TimerService.Mode) -> Void
    var body: some View {
        GeometryReader { geo in
            let w = max(0, geo.size.width / 2)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(Color.white.opacity(0.16))
                    .frame(width: max(0, w - 2))
                    .padding(1)
                    .offset(x: mode == .timer ? 0 : w)
                    .animation(.spring(response: 0.25, dampingFraction: 0.85), value: mode)
                HStack(spacing: 0) {
                    seg("Timer", .timer, w)
                    seg("Pomodoro", .pomodoro, w)
                }
            }
        }
        .layoutProbe("timer.modeSwitch")
    }
    private func seg(_ title: String, _ m: TimerService.Mode, _ w: CGFloat) -> some View {
        Button { onChange(m) } label: {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(mode == m ? Color.white : TimerPalette.gray)
                .frame(width: w)
                .frame(maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }
}

enum TimerLayout {
    static let rowHeight: CGFloat = 44
    static let wheelHeight: CGFloat = 132
    static let selectionBarHeight: CGFloat = 48
    static let selectionBarRadius: CGFloat = 8
    static let fadeLength: CGFloat = 40
    static let columnWidth: CGFloat = 84
    static let wheelsWidth: CGFloat = 252
    static let sidePadding: CGFloat = 14
    static let gap: CGFloat = 12
    static let contentHeight: CGFloat = 132
    static let segmentedHeight: CGFloat = 26
    static let circleDiameter: CGFloat = 50
    static let soundRowHeight: CGFloat = 32
    static let rightSpacing: CGFloat = 12

    static func panelHeight(notchHeight: CGFloat) -> CGFloat {
        notchHeight + NotchSafeArea.contentTopGap + contentHeight + NookLayout.bottomPadding
    }
}

enum CircleTone {
    case neutral, green, orange, red, focus

    var color: Color {
        switch self {
        case .neutral: return Color.white
        case .green: return TimerPalette.green
        case .orange: return TimerPalette.orange
        case .red: return TimerPalette.red
        case .focus: return TimerPalette.focus
        }
    }
}

struct CircleButton: View {
    let title: String
    let tone: CircleTone
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(tone.color.opacity(tone == .neutral ? 0.18 : 0.35), lineWidth: 1.5)
                Circle().fill(tone.color.opacity(tone == .neutral ? 0.16 : 0.28)).padding(4)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tone == .neutral ? Color.white.opacity(0.9) : tone.color)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .frame(width: TimerLayout.circleDiameter, height: TimerLayout.circleDiameter)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

struct EndSoundRow: View {
    let action: TimerService.EndAction
    var interactive = true
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: action == .stopPlaying ? "pause.circle.fill" : "bell.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(label).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if interactive {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).opacity(0.55)
                }
            }
            .foregroundStyle(Color.white.opacity(0.88))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!interactive)
    }
    private var label: String {
        switch action {
        case .stopPlaying: return TimerSoundCatalog.stopPlayingTitle
        case .sound(let n): return n
        }
    }
}

struct TimerWheel: View {
    let range: ClosedRange<Int>
    @Binding var value: Int
    let unit: String
    @State private var pos: Double = 0
    @State private var lastWhole = 0
    @State private var settleTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var center: Int {
        pos.isFinite ? Int(max(-1000, min(1000, pos)).rounded()) : value
    }

    var body: some View {
        let rh = TimerLayout.rowHeight
        let c = center
        let f = TimerLayout.fadeLength / TimerLayout.wheelHeight
        ZStack {
            ForEach(-2...2, id: \.self) { slot in
                let index = c + slot
                let d = Double(index) - pos
                let a = abs(d)
                row(index: index, closeness: max(0, 1 - a))
                    .scaleEffect(max(0.6, 1 - a * 0.2))
                    .opacity(max(0, 1 - a * 0.65))
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : max(-55, min(55, -d * 22))),
                                      axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                    .offset(y: (CGFloat(d) * rh).finiteOrZero)
            }
        }
        .frame(width: TimerLayout.columnWidth, height: TimerLayout.wheelHeight)
        .clipped()
        .mask(LinearGradient(stops: [
            .init(color: .clear, location: 0), .init(color: .black, location: f),
            .init(color: .black, location: 1 - f), .init(color: .clear, location: 1)],
            startPoint: .top, endPoint: .bottom))
        .overlay(WheelSurface(
            onScroll: { dy, precise, _, _ in MainActor.assumeIsolated { handleScroll(dy: dy, precise: precise) } },
            onDrag: { dy, ended in MainActor.assumeIsolated { handleDrag(dy: dy, ended: ended) } }))
        .onAppear { pos = Double(value); lastWhole = value }
        .onDisappear { settleTask?.cancel() }
    }

    @ViewBuilder
    private func row(index: Int, closeness: Double) -> some View {
        if range.contains(index) {
            HStack(spacing: 4) {
                Text(String(format: "%02d", index))
                    .font(.system(size: 28, weight: .light).monospacedDigit())
                    .foregroundStyle(Color.white)
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(TimerPalette.gray)
                    .fixedSize()
                    .opacity(closeness)
            }
        } else {
            Color.clear.frame(height: 1)
        }
    }

    @MainActor private func handleScroll(dy: CGFloat, precise: Bool) {
        guard dy.isFinite else { return }
        let points = precise ? Double(dy) : Double(dy) * Double(TimerLayout.rowHeight)
        move(by: -points / Double(TimerLayout.rowHeight))
        scheduleSettle()
    }
    @MainActor private func handleDrag(dy: CGFloat, ended: Bool) {
        if ended { settle(); return }
        guard dy.isFinite else { return }
        settleTask?.cancel()
        move(by: Double(dy) / Double(TimerLayout.rowHeight))
    }
    @MainActor private func move(by rows: Double) {
        guard rows.isFinite, pos.isFinite else { return }
        let lo = Double(range.lowerBound), hi = Double(range.upperBound)
        var next = pos + rows
        if next < lo { next = lo - (lo - next) * 0.4 }
        if next > hi { next = hi + (next - hi) * 0.4 }
        next = max(lo - 0.6, min(hi + 0.6, next))
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { pos = next }
        let whole = max(range.lowerBound, min(range.upperBound, Int(next.rounded())))
        if whole != lastWhole {
            lastWhole = whole
            value = whole
            HapticsService.timerTick()
        }
    }
    @MainActor private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            settle()
        }
    }
    @MainActor private func settle() {
        settleTask?.cancel()
        guard pos.isFinite else { pos = Double(value); return }
        let whole = max(range.lowerBound, min(range.upperBound, Int(max(-1000, min(1000, pos)).rounded())))
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.22, dampingFraction: 0.82)) {
            pos = Double(whole)
        }
        if value != whole { value = whole }
        lastWhole = whole
    }
}

struct WheelsPanel: View {
    @Bindable var svc: TimerService
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: TimerLayout.selectionBarRadius, style: .continuous)
                .fill(Color(red: 120.0 / 255.0, green: 120.0 / 255.0, blue: 128.0 / 255.0).opacity(0.24))
                .frame(height: TimerLayout.selectionBarHeight)
            HStack(spacing: 0) {
                if svc.mode == .timer {
                    TimerWheel(range: 0...23, value: $svc.pickHours, unit: "hr")
                    TimerWheel(range: 0...59, value: $svc.pickMinutes, unit: "min")
                    TimerWheel(range: 0...59, value: $svc.pickSeconds, unit: "sec")
                } else {
                    TimerWheel(range: 1...120, value: $svc.focusMinutes, unit: "min\nfocus")
                    TimerWheel(range: 1...60, value: $svc.restMinutes, unit: "min\nbreak")
                    TimerWheel(range: 1...12, value: $svc.rounds, unit: "rounds")
                }
            }
            .id(svc.mode)
        }
        .frame(width: TimerLayout.wheelsWidth, height: TimerLayout.contentHeight)
    }
}

struct CountdownPanel: View {
    let svc: TimerService
    var body: some View {
        let accent = TimerPalette.accent(for: svc)
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 6)
            Circle().trim(from: 0, to: CGFloat(max(0, min(1, 1 - svc.progress))).finiteOrZero)
                .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: svc.displaySeconds)
            VStack(spacing: 3) {
                Text(TimerFormat.string(svc.displaySeconds))
                    .font(.system(size: 32, weight: .light).monospacedDigit())
                    .foregroundStyle(Color.white)
                    .opacity(svc.state == .paused ? 0.55 : 1)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                caption(accent)
            }
            .padding(.horizontal, 14)
        }
        .frame(width: 116, height: 116)
        .frame(width: TimerLayout.wheelsWidth, height: TimerLayout.contentHeight)
    }

    @ViewBuilder
    private func caption(_ accent: Color) -> some View {
        if svc.state == .paused {
            Text("Paused").font(.system(size: 11, weight: .medium)).foregroundStyle(TimerPalette.gray)
        } else if svc.mode == .pomodoro {
            HStack(spacing: 4) {
                let filled = svc.phase == .rest ? svc.round : svc.round - 1
                ForEach(0..<min(max(svc.rounds, 1), 12), id: \.self) { i in
                    Circle()
                        .fill(i < filled ? accent : (i == filled && svc.phase == .focus ? accent.opacity(0.5) : Color.white.opacity(0.15)))
                        .frame(width: 6, height: 6)
                }
            }
        } else if let e = svc.endsAt {
            Text("Ends \(e.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(TimerPalette.gray)
        }
    }
}

struct AnnouncementCard: View {
    let announcement: TimerService.Announcement
    let accent: Color
    @State private var drained = false
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(accent.opacity(0.18))
                Image(systemName: announcement.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 56, height: 56)
            Text(announcement.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(announcement.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(TimerPalette.gray)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .frame(width: TimerLayout.wheelsWidth, height: TimerLayout.contentHeight)
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                Capsule().fill(accent.opacity(0.6)).frame(width: drained ? 0 : max(0, geo.size.width), height: 2)
            }
            .frame(height: 2)
        }
        .onAppear { withAnimation(.linear(duration: 6)) { drained = true } }
        .id(announcement.id)
    }
}

struct FinishedPanel: View {
    let svc: TimerService
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(TimerPalette.red.opacity(0.16))
                Image(systemName: "bell.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(TimerPalette.red)
                    .symbolEffect(.bounce, value: svc.announcement?.id)
            }
            .frame(width: 60, height: 60)
            Text(svc.announcement?.title ?? "Time's up")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(svc.announcement?.subtitle ?? "")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TimerPalette.gray)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .frame(width: TimerLayout.wheelsWidth, height: TimerLayout.contentHeight)
    }
}

struct SoundPickerPanel: View {
    let svc: TimerService
    @Binding var page: Int
    var body: some View {
        let items = TimerSoundCatalog.items
        let safePage = min(max(page, 0), TimerSoundCatalog.pageCount - 1)
        let start = safePage * TimerSoundCatalog.perPage
        let end = min(start + TimerSoundCatalog.perPage, items.count)
        let slice: [String] = start < end ? Array(items[start..<end]) : []
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 9) {
                    ForEach(0..<3, id: \.self) { col in
                        let i = row * 3 + col
                        if i < slice.count { chip(slice[i]) } else { Color.clear.frame(width: 78, height: 34) }
                    }
                }
            }
        }
        .frame(width: TimerLayout.wheelsWidth, height: TimerLayout.contentHeight)
    }

    private func isSelected(_ name: String) -> Bool {
        name == TimerSoundCatalog.stopPlayingTitle ? svc.endAction == .stopPlaying : svc.endAction == .sound(name)
    }

    private func chip(_ name: String) -> some View {
        let selected = isSelected(name)
        return Button {
            if name == TimerSoundCatalog.stopPlayingTitle {
                svc.selectStopPlaying()
                AlarmPlayer.shared.stop()
            } else {
                svc.selectSound(name)
                AlarmPlayer.shared.play(name, loop: false, maxSeconds: 0)
            }
        } label: {
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.8))
                .frame(width: 78, height: 34)
                .background(Capsule().fill(selected ? TimerPalette.blue : Color.white.opacity(0.08)))
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct TimerPageView: View {
    @State private var svc = TimerService.shared
    @State private var showPicker = false
    @State private var pickerPage = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: TimerLayout.gap) {
            leftArea.frame(width: TimerLayout.wheelsWidth, height: TimerLayout.contentHeight)
            rightArea
                .frame(maxWidth: .infinity)
                .frame(height: TimerLayout.contentHeight)
        }
        .padding(.horizontal, TimerLayout.sidePadding)
        .notchSafeContent()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9), value: svc.state)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9), value: showPicker)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9), value: svc.announcement)
        .onDisappear { showPicker = false; AlarmPlayer.shared.stop() }
    }

    @ViewBuilder
    private var leftArea: some View {
        if showPicker {
            SoundPickerPanel(svc: svc, page: $pickerPage).transition(.opacity)
        } else if svc.state == .finished {
            FinishedPanel(svc: svc).transition(.opacity)
        } else if svc.state == .running || svc.state == .paused {
            if let a = svc.announcement {
                AnnouncementCard(announcement: a, accent: TimerPalette.accent(for: svc)).transition(.opacity)
            } else {
                CountdownPanel(svc: svc).transition(.opacity)
            }
        } else {
            WheelsPanel(svc: svc).transition(.opacity)
        }
    }

    @ViewBuilder
    private var rightArea: some View {
        if showPicker {
            pickerControls
        } else {
            switch svc.state {
            case .idle: idleControls
            case .running, .paused: runningControls
            case .finished: finishedControls
            }
        }
    }

    private var canStart: Bool { svc.mode == .pomodoro || svc.pickedTotal > 0 }

    private var idleControls: some View {
        VStack(spacing: TimerLayout.rightSpacing) {
            ModeSwitch(mode: svc.mode) { svc.mode = $0 }
                .frame(height: TimerLayout.segmentedHeight)
            HStack(spacing: 12) {
                CircleButton(title: "Cancel", tone: .neutral, enabled: false) {}
                CircleButton(title: "Start", tone: svc.mode == .timer ? .green : .focus, enabled: canStart) { svc.start() }
            }
            .frame(height: TimerLayout.circleDiameter)
            EndSoundRow(action: svc.endAction) { showPicker = true }
                .frame(height: TimerLayout.soundRowHeight)
        }
    }

    private var runningControls: some View {
        let accent = TimerPalette.accent(for: svc)
        let tag = svc.mode == .timer ? "Timer" : "\(svc.phase == .focus ? "Focus" : "Break") \(svc.round)/\(svc.rounds)"
        let paused = svc.state == .paused
        return VStack(spacing: TimerLayout.rightSpacing) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 7, height: 7)
                Text(tag).font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
                Spacer(minLength: 0)
            }
            .frame(height: TimerLayout.segmentedHeight)
            HStack(spacing: 12) {
                CircleButton(title: "Cancel", tone: .neutral) { svc.cancel() }
                CircleButton(title: paused ? "Resume" : "Pause", tone: paused ? .green : .orange) {
                    if paused { svc.resume() } else { svc.pause() }
                }
            }
            .frame(height: TimerLayout.circleDiameter)
            Group {
                if svc.mode == .pomodoro {
                    Button { svc.skipPhase() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "forward.end.fill").font(.system(size: 11, weight: .semibold))
                            Text("Skip phase").font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color.white.opacity(0.88))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(PressScaleStyle())
                } else {
                    EndSoundRow(action: svc.endAction, interactive: false) {}
                }
            }
            .frame(height: TimerLayout.soundRowHeight)
        }
    }

    private var finishedControls: some View {
        VStack(spacing: TimerLayout.rightSpacing) {
            Text(svc.announcement?.title ?? "Time's up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TimerPalette.red)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: TimerLayout.segmentedHeight)
            HStack(spacing: 12) {
                CircleButton(title: "Stop", tone: .red) { svc.stopFinished() }
                CircleButton(title: "Restart", tone: .green) { svc.restart() }
            }
            .frame(height: TimerLayout.circleDiameter)
            Color.clear.frame(height: TimerLayout.soundRowHeight)
        }
    }

    private var pickerControls: some View {
        VStack(spacing: TimerLayout.rightSpacing) {
            HStack {
                Button { pickerPage = max(0, pickerPage - 1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                Spacer(minLength: 0)
                Text("\(min(pickerPage, TimerSoundCatalog.pageCount - 1) + 1)/\(TimerSoundCatalog.pageCount)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(TimerPalette.gray)
                Spacer(minLength: 0)
                Button { pickerPage = min(TimerSoundCatalog.pageCount - 1, pickerPage + 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.85))
            .frame(height: TimerLayout.segmentedHeight)
            PillButton(title: "Done", color: TimerPalette.blue) {
                AlarmPlayer.shared.stop()
                showPicker = false
            }
            .frame(height: TimerLayout.circleDiameter)
            Text("Tap a sound to preview")
                .font(.system(size: 10))
                .foregroundStyle(TimerPalette.gray)
                .frame(height: TimerLayout.soundRowHeight)
        }
    }
}
