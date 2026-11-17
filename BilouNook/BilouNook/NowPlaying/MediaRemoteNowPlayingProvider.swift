import AppKit
import Foundation

final class MediaRemoteNowPlayingProvider: NowPlayingProvider {
    struct Runtime {
        let script: URL
        let framework: URL
    }

    let identifier = "mediaremote"

    private let runtime: Runtime?
    private let fileManager: FileManager
    private var onUpdate: ((NowPlayingSnapshot?) -> Void)?
    private var onFailure: (() -> Void)?
    private var isStopping = false
    private var streamToken: LifecycleManager.Token?

    private let controlQueue = DispatchQueue(label: "com.bilou.nowplaying.mediaremote.control")
    private var controlProcess: Process?
    private let controlLock = NSLock()
    private var terminateObserver: NSObjectProtocol?
    private var lastBundleIdentifiers: Set<String> = []

    private lazy var coalescer = MainCoalescer<NowPlayingSnapshot?>(interval: 0.05) { [weak self] snap in self?.onUpdate?(snap) }
    private lazy var runner = AdapterStreamRunner(
        executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
        arguments: [runtime?.script.path ?? "", runtime?.framework.path ?? "", "stream", "--no-diff", "--debounce=50"],
        environment: nil,
        onLine: { [weak self] line in self?.handleLine(line) },
        onGiveUp: { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isStopping else { return }
                self.onFailure?()
            }
        }
    )

    var isStreaming: Bool {
        runner.isRunning
    }

    var _handlesClearedForTesting: Bool {
        runner.isClearedForTesting
    }

    init(runtime: Runtime? = nil, fileManager: FileManager = .default) {
        self.runtime = runtime ?? Self.bundledRuntime(fileManager: fileManager)
        self.fileManager = fileManager
    }

    var isAvailable: Bool {
        guard let runtime else { return false }
        return fileManager.isExecutableFile(atPath: "/usr/bin/perl")
            && fileManager.fileExists(atPath: runtime.script.path)
            && fileManager.fileExists(atPath: runtime.framework.path)
            && fileManager.fileExists(
                atPath: runtime.framework.appendingPathComponent("MediaRemoteAdapter").path
            )
    }

    func start(
        onUpdate: @escaping (NowPlayingSnapshot?) -> Void,
        onFailure: @escaping () -> Void
    ) {
        stop()
        guard isAvailable, let runtime else {
            onFailure()
            return
        }
        self.onUpdate = onUpdate
        self.onFailure = onFailure
        isStopping = false

        runner.start()
        streamToken = MainActor.assumeIsolated {
            streamToken?.cancel()
            return LifecycleManager.shared.register(
                "mediaremote.stream",
                tier: .essential,
                start: { [weak self] in self?.runner.resume() },
                stop: { [weak self] in self?.runner.stop() }
            )
        }
        observePlayerTermination()
    }

    func stop() {
        isStopping = true
        onUpdate = nil
        onFailure = nil

        runner.stop()

        controlLock.lock()
        let runningControl = controlProcess
        controlLock.unlock()
        if let runningControl, runningControl.isRunning {
            runningControl.terminate()
        }

        if let terminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminateObserver)
        }
        terminateObserver = nil
        lastBundleIdentifiers.removeAll()
    }

    func send(_ command: NowPlayingCommand) {
        guard let runtime else { return }
        let arguments: [String]
        switch command {
        case .togglePlayPause:
            arguments = ["send", "2"]
        case .next:
            arguments = ["send", "4"]
        case .previous:
            arguments = ["send", "5"]
        case .seek(let seconds):
            let micros = Int64(max(0, seconds) * 1_000_000)
            arguments = ["seek", String(micros)]
        }
        runControl(arguments: arguments, runtime: runtime)
    }

    private static var lastArtworkCount = -1
    private static var lastArtworkHash = 0
    private static var lastArtwork: Data?
    static var artworkDecodeCount = 0

    static func snapshot(from payload: [String: Any], now: Date = Date()) -> NowPlayingSnapshot? {
        guard !payload.isEmpty else { return nil }
        let title = trimmedString(payload["title"])
        guard !title.isEmpty else { return nil }

        var sourceTimestamp: Date?
        if payload["timestampEpochMicros"] != nil {
            let micros = doubleValue(payload["timestampEpochMicros"])
            if micros > 0 {
                sourceTimestamp = Date(timeIntervalSince1970: micros / 1_000_000)
            }
        } else if payload["timestamp"] != nil {
            let seconds = doubleValue(payload["timestamp"])
            if seconds > 0 {
                sourceTimestamp = Date(timeIntervalSince1970: seconds)
            }
        }
        let playbackRate: Double? = payload["playbackRate"] != nil
            ? doubleValue(payload["playbackRate"])
            : nil

        let artwork: Data?
        if let encoded = payload["artworkData"] as? String, !encoded.isEmpty {
            var hash = 5381
            var count = 0
            for byte in encoded.utf8 {
                hash = (hash &* 33) &+ Int(byte)
                count += 1
            }
            if count == lastArtworkCount, hash == lastArtworkHash {
                artwork = lastArtwork
            } else {
                artwork = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)
                artworkDecodeCount += 1
                lastArtworkCount = count
                lastArtworkHash = hash
                lastArtwork = artwork
            }
        } else {
            artwork = nil
        }

        let updatedAt = sourceTimestamp ?? now
        return NowPlayingSnapshot(
            title: title,
            artist: trimmedString(payload["artist"]),
            album: trimmedString(payload["album"]),
            artwork: artwork,
            artworkMimeType: payload["artworkMimeType"] as? String,
            isPlaying: boolValue(payload["playing"]),
            elapsed: max(0, doubleValue(payload["elapsedTime"])),
            duration: max(0, doubleValue(payload["duration"])),
            bundleIdentifier: payload["bundleIdentifier"] as? String,
            parentApplicationBundleIdentifier: payload["parentApplicationBundleIdentifier"] as? String,
            updatedAt: updatedAt,
            sourceTimestamp: sourceTimestamp,
            playbackRate: playbackRate
        )
    }

    fileprivate func handleLine(_ line: Data) {
        guard
            let data = try? JSONSerialization.jsonObject(with: line),
            let object = data as? [String: Any],
            let type = object["type"] as? String,
            type == "data",
            let payload = object["payload"] as? [String: Any]
        else {
            return
        }

        let snapshot = Self.snapshot(from: payload)
        let identifiers = Set([
            payload["bundleIdentifier"] as? String,
            payload["parentApplicationBundleIdentifier"] as? String,
        ].compactMap { $0 })
        if !identifiers.isEmpty {
            self.lastBundleIdentifiers = identifiers
        }
        coalescer.push(snapshot)
    }

    private func observePlayerTermination() {
        if let terminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminateObserver)
        }
        terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                let bundleIdentifier = app.bundleIdentifier,
                self.lastBundleIdentifiers.contains(bundleIdentifier)
            else {
                return
            }
            self.lastBundleIdentifiers.removeAll()
            self.onUpdate?(nil)
        }
    }

    private func runControl(arguments: [String], runtime: Runtime) {
        controlQueue.async { [weak self] in
            guard let self else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [
                runtime.script.path,
                runtime.framework.path,
            ] + arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            self.controlLock.lock()
            self.controlProcess = process
            self.controlLock.unlock()

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // Control is best-effort; the stream remains the source of truth.
            }

            self.controlLock.lock()
            if self.controlProcess === process {
                self.controlProcess = nil
            }
            self.controlLock.unlock()
        }
    }

    private static func bundledRuntime(fileManager: FileManager) -> Runtime? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let directory = resources.appendingPathComponent("NowPlaying", isDirectory: true)
        let script = directory.appendingPathComponent("mediaremote-adapter.pl")
        let framework = directory.appendingPathComponent("MediaRemoteAdapter.framework", isDirectory: true)
        guard fileManager.fileExists(atPath: script.path) else { return nil }
        return Runtime(script: script, framework: framework)
    }

    private static func trimmedString(_ value: Any?) -> String {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func doubleValue(_ value: Any?) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? String, let parsed = Double(value) { return parsed }
        return 0
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }
}

final class AdapterStreamRunner {
    private let queue = DispatchQueue(label: "com.bilou.adapter.stream", qos: .utility)
    private let executableURL: URL
    private let arguments: [String]
    private let environment: [String: String]?
    private let onLine: (Data) -> Void
    private let onGiveUp: () -> Void
    private var process: Process?
    private var pipe: Pipe?
    private var generation = 0
    private var buffer = Data()
    private var restartTimes: [Date] = []
    private var restartItem: DispatchWorkItem?
    private var givenUp = false
    private static let maxBuffer = 4 * 1024 * 1024
    private static let maxRestartsPer60s = 3
    private static let backoff: [TimeInterval] = [1, 2, 4]

    var isRunning: Bool { process?.isRunning ?? false }
    var isClearedForTesting: Bool { process == nil && buffer.isEmpty }

    init(executableURL: URL, arguments: [String], environment: [String: String]?,
         onLine: @escaping (Data) -> Void, onGiveUp: @escaping () -> Void) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.onLine = onLine
        self.onGiveUp = onGiveUp
    }

    func start() { queue.sync { [self] in launch() } }
    func resume() { queue.async { [self] in givenUp = false; restartTimes.removeAll(); launch() } }
    func stop() {
        queue.sync { [self] in
            restartItem?.cancel()
            restartItem = nil
            generation += 1
            teardown()
        }
    }

    private func launch() {
        guard process == nil, !givenUp else { return }
        generation += 1
        let gen = generation
        let p = Process()
        p.executableURL = executableURL
        p.arguments = arguments
        if let environment { p.environment = environment }
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            self?.queue.async { self?.consume(data, generation: gen) }
        }
        p.terminationHandler = { [weak self] _ in
            self?.queue.async { self?.ended(generation: gen) }
        }
        process = p
        pipe = out
        do { try p.run() } catch { ended(generation: gen) }
    }

    private func consume(_ data: Data, generation gen: Int) {
        guard gen == generation else { return }
        if data.isEmpty { ended(generation: gen); return }
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<nl])
            buffer.removeSubrange(buffer.startIndex...nl)
            if !line.isEmpty { onLine(line) }
        }
        if buffer.count > Self.maxBuffer { buffer.removeAll(keepingCapacity: false) }
    }

    private func ended(generation gen: Int) {
        guard gen == generation else { return }
        generation += 1
        teardown()
        let now = Date()
        restartTimes = restartTimes.filter { now.timeIntervalSince($0) < 60 }
        if restartTimes.count >= Self.maxRestartsPer60s { givenUp = true; onGiveUp(); return }
        let delay = Self.backoff[min(restartTimes.count, Self.backoff.count - 1)]
        restartTimes.append(now)
        let item = DispatchWorkItem { [weak self] in self?.launch() }
        restartItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func teardown() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        pipe = nil
        buffer.removeAll(keepingCapacity: false)
    }
}

final class MainCoalescer<T> {
    private let lock = NSLock()
    private var pending: T?
    private var scheduled = false
    private let interval: TimeInterval
    private let deliver: @MainActor (T) -> Void
    init(interval: TimeInterval = 0.05, deliver: @escaping @MainActor (T) -> Void) {
        self.interval = interval
        self.deliver = deliver
    }
    func push(_ value: T) {
        lock.lock()
        pending = value
        let shouldSchedule = !scheduled
        scheduled = true
        lock.unlock()
        guard shouldSchedule else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in self?.flush() }
    }
    private func flush() {
        lock.lock()
        let v = pending
        pending = nil
        scheduled = false
        lock.unlock()
        if let v { MainActor.assumeIsolated { deliver(v) } }
    }
}
