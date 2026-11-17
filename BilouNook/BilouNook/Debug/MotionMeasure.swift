#if DEBUG
import AppKit
import Foundation
import QuartzCore

enum MotionMeasure {
    @MainActor
    static func run(label: String) {
        let runner = Runner(label: label)
        runner.start()
    }

    @MainActor
    private final class Runner {
        private let label: String
        private let refresh: Double
        private let warmupCycles = 2
        private let measuredCycles = 20
        private var cycle = 0
        private var openMetrics: [CycleMetrics] = []
        private var closeMetrics: [CycleMetrics] = []
        private var savedDefaults: [String: Any] = [:]

        init(label: String) {
            self.label = label
            self.refresh = Double(NSScreen.main?.maximumFramesPerSecond ?? 60)
        }

        func start() {
            NSApp.activate(ignoringOtherApps: true)
            ProcessInfo.processInfo.disableSuddenTermination()
            ProcessInfo.processInfo.disableAutomaticTermination("motion-measure")
            MotionRecorder.shared.setMeasuring(true)
            saveSettings()
            configureMeasurementEnvironment()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
                MouseMonitor.shared.simulateMove(to: exitPoint())
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.runNextCycle()
                }
            }
        }

        private func runNextCycle() {
            guard cycle < warmupCycles + measuredCycles else {
                finish()
                return
            }
            guard NotchState.shared.phase == .closed else {
                NotchState.shared.closeImmediately(reason: .programmatic)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.runNextCycle() }
                return
            }
            let measured = cycle >= warmupCycles
            let index = cycle - warmupCycles
            cycle += 1

            MotionRecorder.shared.begin(cycle: index, direction: .open)
            MouseMonitor.shared.simulateMove(to: entryPoint())

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
                let openTrace = MotionRecorder.shared.end()
                if measured, let openTrace {
                    openMetrics.append(analyze(openTrace, direction: .open))
                }

                MotionRecorder.shared.begin(cycle: index, direction: .close)
                MouseMonitor.shared.simulateMove(to: exitPoint())

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
                    let closeTrace = MotionRecorder.shared.end()
                    if measured, let closeTrace {
                        closeMetrics.append(analyze(closeTrace, direction: .close))
                    }

                    if NotchState.shared.phase != .closed {
                        NotchState.shared.closeImmediately(reason: .programmatic)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        self.runNextCycle()
                    }
                }
            }
        }

        private func finish() {
            MotionRecorder.shared.setMeasuring(false)
            restoreSettings()
            NowPlayingService.shared.setSnapshotForTesting(nil)
            let report = makeReport()
            write(report)
            print(report.markdown)
            fflush(stdout)
            exit(report.missed ? 1 : 0)
        }

        private func configureMeasurementEnvironment() {
            Watchdog.shared.stop()
            MouseMonitor.shared.stop()
            SettingsStore.shared.openOnHover = true
            SettingsStore.shared.hoverIntentDelay = 0
            SettingsStore.shared.closeDelay = 0
            SettingsStore.shared.minStateDwell = 0
            SettingsStore.shared.flyByGuardEnabled = false
            SettingsStore.shared.mediaWidgetEnabled = true
            SettingsStore.shared.calendarWidgetEnabled = true
            SettingsStore.shared.hapticsEnabled = false

            NowPlayingService.shared.stop()
            NowPlayingService.shared.setSnapshotForTesting(
                NowPlayingSnapshot(
                    title: "Midnight City",
                    artist: "M83",
                    album: "Hurry Up, We're Dreaming",
                    artwork: nil,
                    artworkMimeType: nil,
                    isPlaying: true,
                    elapsed: 84,
                    duration: 244,
                    bundleIdentifier: "com.apple.Music",
                    parentApplicationBundleIdentifier: "com.apple.Music",
                    updatedAt: Date()
                )
            )
        }

        private func saveSettings() {
            let defaults = UserDefaults.standard
            for key in Self.settingsKeys {
                savedDefaults[key] = defaults.object(forKey: key)
            }
        }

        private func restoreSettings() {
            let defaults = UserDefaults.standard
            for key in Self.settingsKeys {
                if let value = savedDefaults[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        private func entryPoint() -> NSPoint {
            let snapshot = NotchGeometryCache.shared.current
            let rect = InteractionRegion.hotZone(
                screenFrame: snapshot.screen.frame,
                notchGeom: snapshot.geometry
            )
            return NSPoint(x: rect.midX, y: rect.midY)
        }

        private func exitPoint() -> NSPoint {
            let frame = NotchGeometryCache.shared.current.screen.frame
            return NSPoint(x: frame.midX, y: frame.minY + 120)
        }

        private func analyze(_ trace: MotionTrace, direction: MotionTraceDirection) -> CycleMetrics {
            guard let pointer = trace.pointerTime else {
                return CycleMetrics.empty(index: trace.cycle)
            }
            let shapes = trace.shapes.filter { $0.time >= pointer }
            let contents = trace.contents.filter { $0.time >= pointer }
            guard let firstShape = shapes.first else {
                return CycleMetrics.empty(index: trace.cycle)
            }

            let startWidth = firstShape.width
            let targetWidth = shapes.last?.width ?? startWidth
            let peakWidth = direction == .open
                ? (shapes.map(\.width).max() ?? targetWidth)
                : (shapes.map(\.width).min() ?? targetWidth)
            let overshoot = abs(peakWidth - targetWidth)
            let delta = targetWidth - startWidth

            func containerProgress(_ sample: MotionShapeSample) -> Double {
                guard abs(delta) > 0.01 else { return direction == .open ? 1 : 0 }
                return min(max(Double((sample.width - startWidth) / delta), 0), 1)
            }

            let firstChange = shapes.first { abs($0.width - startWidth) > 0.01 }
            let to25 = shapes.first { containerProgress($0) >= 0.25 }
            let to50 = shapes.first { containerProgress($0) >= 0.50 }
            let to95 = shapes.first { containerProgress($0) >= 0.95 }

            func maxOpacity(_ sample: MotionContentSample) -> Double {
                max(sample.tabs, sample.media, sample.calendar)
            }

            let firstContent: MotionContentSample?
            let content50: MotionContentSample?
            let controls: MotionContentSample?
            if direction == .open {
                firstContent = contents.first { maxOpacity($0) > 0.001 }
                content50 = contents.first { maxOpacity($0) >= 0.5 }
                controls = contents.first { $0.media >= 0.95 }
            } else {
                firstContent = contents.first { maxOpacity($0) < 0.999 }
                content50 = contents.first { maxOpacity($0) <= 0.5 }
                controls = contents.first { $0.media <= 0.05 }
            }

            let times = shapes.map(\.time)
            var intervals: [Double] = []
            for index in 1..<times.count {
                let delta = (times[index] - times[index - 1]) * 1000
                if delta >= 0 {
                    intervals.append(delta)
                }
            }

            let mainThread = shapes.map { $0.mainThreadSeconds * 1000 }
                + contents.map { $0.mainThreadSeconds * 1000 }
            let mainThreadPositive = mainThread.filter { $0 > 0 }

            return CycleMetrics(
                index: trace.cycle,
                pointerToFirstChange: millis(pointer, firstChange?.time),
                pointerTo25: millis(pointer, to25?.time),
                pointerTo50: millis(pointer, to50?.time),
                pointerTo95: millis(pointer, to95?.time),
                pointerToFirstContent: millis(pointer, firstContent?.time),
                pointerToContent50: millis(pointer, content50?.time),
                pointerToControls: millis(pointer, controls?.time),
                overshoot: overshoot,
                frameIntervals: intervals,
                frameMainThread: mainThreadPositive
            )
        }

        private func millis(_ start: CFTimeInterval, _ end: CFTimeInterval?) -> Double {
            guard let end else { return .nan }
            return (end - start) * 1000
        }

        private func makeReport() -> Report {
            let open = summarize(openMetrics)
            let close = summarize(closeMetrics)
            let criteria = Criteria(
                firstContent: open.pointerToFirstContent.median <= 100,
                content50: open.pointerToContent50.median <= 170,
                container95: open.pointerTo95.median <= 300,
                noFrameAbove3x: open.frameIntervals.max <= refreshIntervalMs * 3,
                frameP95: open.frameIntervals.p95 <= refreshIntervalMs * 1.25,
                closeStable: close.pointerTo95.median.isFinite
            )
            let missed = !criteria.firstContent || !criteria.content50 || !criteria.container95
                || !criteria.noFrameAbove3x || !criteria.frameP95
            let markdown = renderMarkdown(open: open, close: close, criteria: criteria, missed: missed)
            return Report(markdown: markdown, missed: missed, open: open, close: close)
        }

        private func summarize(_ cycles: [CycleMetrics]) -> Summary {
            Summary(
                cycles: cycles,
                pointerToFirstChange: Stats(values: cycles.map(\.pointerToFirstChange), refreshMs: refreshIntervalMs),
                pointerTo25: Stats(values: cycles.map(\.pointerTo25), refreshMs: refreshIntervalMs),
                pointerTo50: Stats(values: cycles.map(\.pointerTo50), refreshMs: refreshIntervalMs),
                pointerTo95: Stats(values: cycles.map(\.pointerTo95), refreshMs: refreshIntervalMs),
                pointerToFirstContent: Stats(values: cycles.map(\.pointerToFirstContent), refreshMs: refreshIntervalMs),
                pointerToContent50: Stats(values: cycles.map(\.pointerToContent50), refreshMs: refreshIntervalMs),
                pointerToControls: Stats(values: cycles.map(\.pointerToControls), refreshMs: refreshIntervalMs),
                frameIntervals: Stats(values: cycles.flatMap(\.frameIntervals), refreshMs: refreshIntervalMs),
                frameMainThread: Stats(values: cycles.flatMap(\.frameMainThread), refreshMs: refreshIntervalMs)
            )
        }

        private func renderMarkdown(
            open: Summary,
            close: Summary,
            criteria: Criteria,
            missed: Bool
        ) -> String {
            var text = "# Nook motion measurement — \(label)\n\n"
            text += "Refresh: \(Int(refresh)) Hz (\(String(format: "%.2f", refreshIntervalMs)) ms)\n\n"
            text += "Cycles: \(open.cycles.count) open + \(close.cycles.count) close after \(warmupCycles) warmups\n\n"
            text += "## Per-cycle open (ms)\n\n"
            text += "| cycle | first container | 25% | 50% | 95% | first pixel | content 50% | controls | overshoot | frame p50 | frame p95 | frame max | >1.5x | >3x |\n"
            text += "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n"
            for cycle in open.cycles {
                let frames = Stats(values: cycle.frameIntervals, refreshMs: refreshIntervalMs)
                text += "| \(cycle.index) | \(fmt(cycle.pointerToFirstChange)) | \(fmt(cycle.pointerTo25)) | \(fmt(cycle.pointerTo50)) | \(fmt(cycle.pointerTo95)) | \(fmt(cycle.pointerToFirstContent)) | \(fmt(cycle.pointerToContent50)) | \(fmt(cycle.pointerToControls)) | \(fmt(cycle.overshoot)) | \(fmt(frames.p50)) | \(fmt(frames.p95)) | \(fmt(frames.max)) | \(frames.above15) | \(frames.above3) |\n"
            }
            text += "\n## Per-cycle close (ms)\n\n"
            text += "| cycle | first container | 25% | 50% | 95% | first fade | content 50% | controls hidden | frame p50 | frame p95 | frame max | >1.5x | >3x |\n"
            text += "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n"
            for cycle in close.cycles {
                let frames = Stats(values: cycle.frameIntervals, refreshMs: refreshIntervalMs)
                text += "| \(cycle.index) | \(fmt(cycle.pointerToFirstChange)) | \(fmt(cycle.pointerTo25)) | \(fmt(cycle.pointerTo50)) | \(fmt(cycle.pointerTo95)) | \(fmt(cycle.pointerToFirstContent)) | \(fmt(cycle.pointerToContent50)) | \(fmt(cycle.pointerToControls)) | \(fmt(frames.p50)) | \(fmt(frames.p95)) | \(fmt(frames.max)) | \(frames.above15) | \(frames.above3) |\n"
            }
            text += "\n## Summary (ms)\n\n"
            text += "| metric | open median | open p95 | close median | close p95 |\n"
            text += "|---|---:|---:|---:|---:|\n"
            text += "| pointer → first container change | \(fmt(open.pointerToFirstChange.median)) | \(fmt(open.pointerToFirstChange.p95)) | \(fmt(close.pointerToFirstChange.median)) | \(fmt(close.pointerToFirstChange.p95)) |\n"
            text += "| pointer → container 25% | \(fmt(open.pointerTo25.median)) | \(fmt(open.pointerTo25.p95)) | \(fmt(close.pointerTo25.median)) | \(fmt(close.pointerTo25.p95)) |\n"
            text += "| pointer → container 50% | \(fmt(open.pointerTo50.median)) | \(fmt(open.pointerTo50.p95)) | \(fmt(close.pointerTo50.median)) | \(fmt(close.pointerTo50.p95)) |\n"
            text += "| pointer → container 95% | \(fmt(open.pointerTo95.median)) | \(fmt(open.pointerTo95.p95)) | \(fmt(close.pointerTo95.median)) | \(fmt(close.pointerTo95.p95)) |\n"
            text += "| pointer → first content pixel | \(fmt(open.pointerToFirstContent.median)) | \(fmt(open.pointerToFirstContent.p95)) | \(fmt(close.pointerToFirstContent.median)) | \(fmt(close.pointerToFirstContent.p95)) |\n"
            text += "| pointer → content 50% | \(fmt(open.pointerToContent50.median)) | \(fmt(open.pointerToContent50.p95)) | \(fmt(close.pointerToContent50.median)) | \(fmt(close.pointerToContent50.p95)) |\n"
            text += "| pointer → controls visible/hidden | \(fmt(open.pointerToControls.median)) | \(fmt(open.pointerToControls.p95)) | \(fmt(close.pointerToControls.median)) | \(fmt(close.pointerToControls.p95)) |\n"
            text += "\nOpen overshoot: \(fmt(open.cycles.map(\.overshoot).max() ?? 0)) pt\n"
            text += "\n## Frame intervals (open, ms)\n\n"
            text += "p50 \(fmt(open.frameIntervals.p50)), p95 \(fmt(open.frameIntervals.p95)), max \(fmt(open.frameIntervals.max)), count \(open.frameIntervals.count), above 1.5x \(open.frameIntervals.above15), above 3x \(open.frameIntervals.above3)\n\n"
            text += "## Main-thread frame work (open, shape + content body, ms)\n\n"
            text += "p50 \(fmt3(open.frameMainThread.p50)), p95 \(fmt3(open.frameMainThread.p95)), max \(fmt3(open.frameMainThread.max)), samples \(open.frameMainThread.count)\n\n"
            text += "## Pass criteria\n\n"
            text += "- first content pixel ≤100 ms: \(criteria.firstContent ? "PASS" : "MISSED") (\(fmt(open.pointerToFirstContent.median)) ms)\n"
            text += "- content 50% ≤170 ms: \(criteria.content50 ? "PASS" : "MISSED") (\(fmt(open.pointerToContent50.median)) ms)\n"
            text += "- container 95% ≤300 ms: \(criteria.container95 ? "PASS" : "MISSED") (\(fmt(open.pointerTo95.median)) ms)\n"
            text += "- no frame >3x refresh: \(criteria.noFrameAbove3x ? "PASS" : "MISSED") (max \(fmt(open.frameIntervals.max)) ms)\n"
            text += "- frame p95 ≤1.25x refresh: \(criteria.frameP95 ? "PASS" : "MISSED") (p95 \(fmt(open.frameIntervals.p95)) ms)\n"
            text += "\nResult: \(missed ? "MISSED" : "PASS")\n"
            return text
        }

        private func write(_ report: Report) {
            let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("docs")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let markdownURL = directory.appendingPathComponent("motion-measure-\(label).md")
            try? report.markdown.write(to: markdownURL, atomically: true, encoding: .utf8)

            let json: [String: Any] = [
                "label": label,
                "refreshHz": Int(refresh),
                "open": jsonSummary(report.open),
                "close": jsonSummary(report.close),
            ]
            if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: directory.appendingPathComponent("motion-measure-\(label).json"))
            }
        }

        private func jsonSummary(_ summary: Summary) -> [String: Any] {
            [
                "firstChangeMedian": summary.pointerToFirstChange.median,
                "container25Median": summary.pointerTo25.median,
                "container50Median": summary.pointerTo50.median,
                "container95Median": summary.pointerTo95.median,
                "firstContentMedian": summary.pointerToFirstContent.median,
                "content50Median": summary.pointerToContent50.median,
                "controlsMedian": summary.pointerToControls.median,
                "frameP50": summary.frameIntervals.p50,
                "frameP95": summary.frameIntervals.p95,
                "frameMax": summary.frameIntervals.max,
                "frameAbove15": summary.frameIntervals.above15,
                "frameAbove3": summary.frameIntervals.above3,
                "mainThreadP50": summary.frameMainThread.p50,
                "mainThreadP95": summary.frameMainThread.p95,
                "overshootMax": summary.cycles.map(\.overshoot).max() ?? 0,
            ]
        }

        private func fmt(_ value: Double) -> String {
            value.isFinite ? String(format: "%.1f", value) : "—"
        }

        private func fmt3(_ value: Double) -> String {
            value.isFinite ? String(format: "%.3f", value) : "—"
        }

        private var refreshIntervalMs: Double {
            1000 / max(refresh, 1)
        }

        private static let settingsKeys = [
            "openOnHover", "hoverIntentDelay", "closeDelay", "minStateDwell",
            "flyByGuardEnabled", "hapticsEnabled", "mediaWidgetEnabled", "calendarWidgetEnabled",
        ]
    }
}

private struct CycleMetrics {
    let index: Int
    let pointerToFirstChange: Double
    let pointerTo25: Double
    let pointerTo50: Double
    let pointerTo95: Double
    let pointerToFirstContent: Double
    let pointerToContent50: Double
    let pointerToControls: Double
    let overshoot: Double
    let frameIntervals: [Double]
    let frameMainThread: [Double]

    static func empty(index: Int) -> CycleMetrics {
        CycleMetrics(
            index: index,
            pointerToFirstChange: .nan,
            pointerTo25: .nan,
            pointerTo50: .nan,
            pointerTo95: .nan,
            pointerToFirstContent: .nan,
            pointerToContent50: .nan,
            pointerToControls: .nan,
            overshoot: 0,
            frameIntervals: [],
            frameMainThread: []
        )
    }
}

private struct Stats {
    let values: [Double]
    let refreshMs: Double

    var count: Int { values.filter(\.isFinite).count }
    var p50: Double { percentile(0.50) }
    var p95: Double { percentile(0.95) }
    var max: Double { values.filter(\.isFinite).max() ?? 0 }
    var median: Double { p50 }
    var above15: Int { values.filter { $0 > refreshMs * 1.5 }.count }
    var above3: Int { values.filter { $0 > refreshMs * 3 }.count }

    private func percentile(_ p: Double) -> Double {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return 0 }
        let index = Int(Double(sorted.count - 1) * p)
        return sorted[index]
    }
}

private struct Summary {
    let cycles: [CycleMetrics]
    let pointerToFirstChange: Stats
    let pointerTo25: Stats
    let pointerTo50: Stats
    let pointerTo95: Stats
    let pointerToFirstContent: Stats
    let pointerToContent50: Stats
    let pointerToControls: Stats
    let frameIntervals: Stats
    let frameMainThread: Stats
}

private struct Criteria {
    let firstContent: Bool
    let content50: Bool
    let container95: Bool
    let noFrameAbove3x: Bool
    let frameP95: Bool
    let closeStable: Bool
}

private struct Report {
    let markdown: String
    let missed: Bool
    let open: Summary
    let close: Summary
}
#endif
