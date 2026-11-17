import AppKit
import SwiftUI
import Darwin
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panelController: NotchPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        let slowMotionValue = SettingsCleanup.purgeSlowMotion()
        if let slowMotionValue {
            MouseLog.write(String(format: "SETTINGS slowMotion_purged_before_launch value=%@", slowMotionValue ? "true" : "false"))
        }
        let purgedPaddings = SettingsCleanup.purgeHotZonePaddings()
        if let purgedPaddings {
            let x = (purgedPaddings["hotPaddingX"] as? Double) ?? -1
            let y = (purgedPaddings["hotPaddingBelow"] as? Double) ?? -1
            MouseLog.write(String(format: "SETTINGS hotPadding_purged_before_launch hotPaddingX=%.1f hotPaddingBelow=%.1f", x, y))
        }
        #else
        SettingsCleanup.purgeSlowMotion()
        SettingsCleanup.purgeHotZonePaddings()
        #endif
        panelController = NotchPanelController()
        if let panel = panelController?.panel {
            LifecycleManager.shared.observeOcclusion(of: panel)
        }
        panelController?.show()
        #if DEBUG
        if DebugLaunchModes.handle(CommandLine.arguments) { return }
        #endif
        let swipe = TabSwipeController.shared
        swipe.isEnabled = { NotchState.shared.phase == .opening || NotchState.shared.phase == .open }
        swipe.pointerInside = { NSApp.windows.first(where: { $0 is NotchPanel })?.frame.contains(NSEvent.mouseLocation) ?? false }
        swipe.ownedByChild = { MainActor.assumeIsolated { GestureOwnerRegistry.shared.isOwned("calendar.weekStrip") } }
        swipe.canGo = { dir in
            let r = ModuleRegistry.shared
            let ids = r.enabledModules.map(\.id)
            guard let activeID = r.activeModuleID, let i = ids.firstIndex(of: activeID) else { return false }
            return ids.indices.contains(i + dir)
        }
        swipe.commit = { dir in
            let r = ModuleRegistry.shared
            let ids = r.enabledModules.map(\.id)
            guard let activeID = r.activeModuleID, let i = ids.firstIndex(of: activeID), ids.indices.contains(i + dir) else { return }
            withAnimation(Animations.tabSwitch) {
                r.select(id: ids[i + dir])
                TabSwipeController.shared.settle()
            }
        }
        FileDropMonitor.shared.start()
        NowPlayingService.shared.start()
        LifecycleManager.shared.install()
        HangWatchdog.shared.start()
        ResourceSampler.shared.start()

        let timerService = TimerService.shared
        timerService.installSideEffects()
        timerService.releaseAttention = {
            NotchHold.shared.release()
            MouseMonitor.shared.reevaluate()
        }
        timerService.requestAttention = { seconds in
            MainActor.assumeIsolated {
                NotchHold.shared.hold(seconds: seconds)
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.05) {
                    MouseMonitor.shared.reevaluate()
                }
                NotchState.shared.requestOpen(trigger: .drag)
                ModuleRegistry.shared.select(id: "timer")
            }
        }
        timerService.stopMedia = {
            MainActor.assumeIsolated {
                if NowPlayingService.shared.liveActivityState.isPlaying { NowPlayingService.shared.togglePlayPause() }
            }
        }
        ApproachMonitor.shared.start()
        #if DEBUG
        if CommandLine.arguments.contains("--layout-autocapture") {
            Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
                MainActor.assumeIsolated { LayoutDump.captureCurrent(force: false) }
            }
        }
        #endif
        _ = NotchSafeAreaPublisher.shared
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        #if DEBUG
        if NotchCalibrationState.shared.isVisible {
            NotchCalibrationState.shared.printValues(label: "final")
        }
        #endif
        panelController?.stop()
        Watchdog.shared.stop()
        FileDropMonitor.shared.stop()
        NowPlayingService.shared.stop()
    }
}

final class HangWatchdog {
    static let shared = HangWatchdog()
    private let queue = DispatchQueue(label: "com.bilou.hangwatchdog", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    private var lastMain = DispatchTime.now().uptimeNanoseconds
    private var pingInFlight = false
    private var lastCapture = Date.distantPast
    static var logDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/BilouNook", isDirectory: true)
    }

    func start() {
        guard timer == nil else { return }
        try? FileManager.default.createDirectory(at: Self.logDir, withIntermediateDirectories: true)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 2.0, leeway: .milliseconds(800))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func tick() {
        lock.lock()
        let last = lastMain
        let inFlight = pingInFlight
        if !inFlight { pingInFlight = true }
        lock.unlock()
        if !inFlight {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                self.lastMain = DispatchTime.now().uptimeNanoseconds
                self.pingInFlight = false
                self.lock.unlock()
            }
        }
        let stalledMs = (DispatchTime.now().uptimeNanoseconds &- last) / 1_000_000
        if stalledMs > 4000, Date().timeIntervalSince(lastCapture) > 120 {
            lastCapture = Date()
            capture(stalledMs: stalledMs)
        }
    }

    private func capture(stalledMs: UInt64) {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let path = Self.logDir.appendingPathComponent("hang-\(f.string(from: Date())).txt").path
        let note = "main stalled \(stalledMs) ms; footprint \(ResourceSampler.footprintMB()) MB; threads \(ResourceSampler.threadCount())\n"
        try? note.write(toFile: path + ".note", atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        p.arguments = ["\(getpid())", "3", "-file", path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return }
        queue.asyncAfter(deadline: .now() + 12) { if p.isRunning { p.terminate() } }
    }
}

final class ResourceSampler {
    static let shared = ResourceSampler()
    private let queue = DispatchQueue(label: "com.bilou.resourcesampler", qos: .background)
    private var timer: DispatchSourceTimer?
    private var lastCPU = 0.0
    private var lastWall = Date()

    func start() {
        guard timer == nil else { return }
        let dir = HangWatchdog.logDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("resources.csv")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "time,cpu_pct,footprint_mb,threads\n".write(to: url, atomically: true, encoding: .utf8)
        }
        lastCPU = Self.cpuSeconds()
        lastWall = Date()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 30, repeating: 30, leeway: .seconds(2))
        t.setEventHandler { [weak self] in self?.sample(to: url) }
        t.resume()
        timer = t
    }

    private func sample(to url: URL) {
        let cpu = Self.cpuSeconds()
        let now = Date()
        let pct = (cpu - lastCPU) / max(now.timeIntervalSince(lastWall), 0.001) * 100
        lastCPU = cpu
        lastWall = now
        let line = "\(ISO8601DateFormatter().string(from: now)),\(String(format: "%.2f", pct)),\(String(format: "%.1f", Self.footprintMB())),\(Self.threadCount())\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        }
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    static func cpuSeconds() -> Double {
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_utime.tv_sec) + Double(u.ru_utime.tv_usec) / 1e6 + Double(u.ru_stime.tv_sec) + Double(u.ru_stime.tv_usec) / 1e6
    }

    static func threadCount() -> Int {
        var list: thread_act_array_t?
        var n: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &list, &n) == KERN_SUCCESS else { return -1 }
        if let list {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: list)), vm_size_t(Int(n) * MemoryLayout<thread_t>.size))
        }
        return Int(n)
    }
}

@MainActor
@Observable
final class ContentPrewarm {
    static let shared = ContentPrewarm()
    private(set) var isWarm = false
    @ObservationIgnored private var releaseTask: Task<Void, Never>?

    func request() {
        releaseTask?.cancel(); releaseTask = nil
        if !isWarm { isWarm = true }
    }

    func releaseSoon(after seconds: Double = 1.2) {
        guard isWarm, releaseTask == nil else { return }
        releaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.isWarm = false
            self.releaseTask = nil
        }
    }
}

final class ApproachMonitor {
    static let shared = ApproachMonitor()
    private var local: Any?
    private var global: Any?
    private var gate = EventGate(minInterval: 1.0 / 15.0)
    func start() {
        guard global == nil else { return }
        global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            self?.handle(NSEvent.mouseLocation, t: e.timestamp)
        }
        local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            self?.handle(NSEvent.mouseLocation, t: e.timestamp)
            return e
        }
    }
    private func handle(_ p: NSPoint, t: TimeInterval) {
        guard gate.allow(t) else { return }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) else { return }
        let f = screen.frame
        let near = abs(p.x - f.midX) <= 170 && p.y >= f.maxY - 100
        MainActor.assumeIsolated {
            if near { ContentPrewarm.shared.request() } else { ContentPrewarm.shared.releaseSoon() }
        }
    }
}

