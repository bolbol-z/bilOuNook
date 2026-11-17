import AppKit
import Foundation
import Observation

struct NowPlayingPendingSeek: Equatable {
    let target: TimeInterval
    let issuedAt: Date
    let trackIdentity: String
}

@Observable
final class NowPlayingService {
    static let shared = NowPlayingService()

    private(set) var snapshot: NowPlayingSnapshot? {
        didSet { updateLiveActivityState() }
    }
    private(set) var liveActivityState = NowPlayingLiveActivityState.empty
    private(set) var pendingSeek: NowPlayingPendingSeek?
    private(set) var playbackAnchor: MediaPlaybackAnchor?
    private(set) var providerName: String = "none"
    private(set) var isRunning = false

    private let seekTolerance: TimeInterval = 1.5
    private var reconciler = SeekReconciler()
    private var staleGuard = ArtworkStaleGuard()

    private let providers: [NowPlayingProvider]
    private var activeProvider: NowPlayingProvider?
    private var activeProviderIndex: Int?
    private var failedProviders: Set<ObjectIdentifier> = []
    private var tickToken: LifecycleManager.Token?
    private var lastTickAt: Date?
    private var workspaceObserver: NSObjectProtocol?

    private let timerEnabled: Bool
    private let tickInterval: TimeInterval
    private let now: () -> Date
    private let scheduler: NotchScheduler

    init(
        providers: [NowPlayingProvider]? = nil,
        timerEnabled: Bool = true,
        tickInterval: TimeInterval = 1,
        now: @escaping () -> Date = Date.init,
        scheduler: NotchScheduler = SystemNotchScheduler()
    ) {
        self.providers = providers ?? Self.defaultProviders()
        self.timerEnabled = timerEnabled
        self.tickInterval = tickInterval
        self.now = now
        self.scheduler = scheduler
    }

    #if DEBUG
    func setSnapshotForTesting(_ snapshot: NowPlayingSnapshot?) {
        self.snapshot = snapshot
    }
    #endif

    var isPlaying: Bool {
        snapshot?.isPlaying ?? false
    }

    var progress: Double {
        snapshot?.progress ?? 0
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        failedProviders.removeAll()
        startWorkspaceObserver()
        startFirstAvailableProvider()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopTimer()
        activeProvider?.stop()
        activeProvider = nil
        activeProviderIndex = nil
        clearPendingSeek()
        providerName = "none"
        snapshot = nil
        removeWorkspaceObserver()
    }

    func togglePlayPause() {
        activeProvider?.send(.togglePlayPause)
    }

    func next() {
        activeProvider?.send(.next)
    }

    func previous() {
        activeProvider?.send(.previous)
    }

    func seek(to seconds: TimeInterval) {
        guard
            let provider = activeProvider,
            let snapshot,
            snapshot.duration > 0,
            seconds.isFinite
        else {
            return
        }

        let target = min(max(0, seconds), snapshot.duration)
        let issuedAt = now()
        clearPendingSeek()
        reconciler.begin(target: target, now: issuedAt, trackIdentity: snapshot.trackIdentity)
        playbackAnchor = MediaPlaybackAnchor(
            elapsedAtAnchor: target,
            anchorDate: issuedAt,
            isPlaying: snapshot.isPlaying
        )

        var optimistic = snapshot
        optimistic.elapsed = target
        optimistic.updatedAt = issuedAt
        self.snapshot = optimistic
        lastTickAt = issuedAt
        provider.send(.seek(target))
    }

    func advanceElapsed(by interval: TimeInterval) {
        guard var snapshot, snapshot.isPlaying, interval > 0 else { return }
        snapshot.elapsed = max(0, snapshot.elapsed + interval)
        if snapshot.duration > 0 {
            snapshot.elapsed = min(snapshot.elapsed, snapshot.duration)
        }
        self.snapshot = snapshot
    }

    static func defaultProviders() -> [NowPlayingProvider] {
        [
            MediaRemoteNowPlayingProvider(),
            AppleScriptNowPlayingProvider(target: .spotify),
            AppleScriptNowPlayingProvider(target: .music),
        ]
    }

    private func firstAvailableProviderIndex() -> Int? {
        providers.indices.first {
            providers[$0].isAvailable && !failedProviders.contains(ObjectIdentifier(providers[$0]))
        }
    }

    private func startFirstAvailableProvider() {
        if let index = firstAvailableProviderIndex() {
            startProvider(at: index)
        } else {
            clearActiveProvider()
        }
    }

    private func startNextProvider(after index: Int) {
        let nextIndex = index + 1
        guard nextIndex < providers.count else {
            clearActiveProvider()
            return
        }
        for candidateIndex in nextIndex..<providers.count where providers[candidateIndex].isAvailable {
            startProvider(at: candidateIndex)
            return
        }
        clearActiveProvider()
    }

    private func startProvider(at index: Int) {
        activeProvider?.stop()
        activeProvider = nil
        activeProviderIndex = nil
        providerName = "none"
        snapshot = nil
        stopTimer()

        let candidate = providers[index]
        guard candidate.isAvailable else {
            startNextProvider(after: index)
            return
        }

        activeProvider = candidate
        activeProviderIndex = index
        providerName = candidate.identifier
        candidate.start(
            onUpdate: { [weak self, weak candidate] snapshot in
                guard
                    let self,
                    let candidate,
                    self.activeProvider === candidate
                else {
                    return
                }
                self.accept(snapshot)
            },
            onFailure: { [weak self, weak candidate] in
                guard
                    let self,
                    let candidate,
                    self.activeProvider === candidate
                else {
                    return
                }
                DispatchQueue.main.async {
                    guard self.activeProvider === candidate else { return }
                    self.failedProviders.insert(ObjectIdentifier(candidate))
                    self.startNextProvider(after: index)
                }
            }
        )
    }

    private func clearActiveProvider() {
        activeProvider?.stop()
        activeProvider = nil
        activeProviderIndex = nil
        playbackAnchor = nil
        clearPendingSeek()
        providerName = "none"
        snapshot = nil
        stopTimer()
    }

    private func accept(_ incoming: NowPlayingSnapshot?) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.accept(incoming)
            }
            return
        }

        guard var snapshot = normalized(incoming) else {
            clearPendingSeek()
            playbackAnchor = nil
            self.snapshot = nil
            if activeProvider is AppleScriptNowPlayingProvider {
                startTimer()
            } else {
                stopTimer()
            }
            return
        }

        let previous = self.snapshot
        let trackChanged = previous.map { $0.trackIdentity != snapshot.trackIdentity } ?? false
        if trackChanged {
            // Track change: metadata, artwork and progress must move together.
            reconciler.clear()
            playbackAnchor = MediaPlaybackAnchor(
                elapsedAtAnchor: snapshot.elapsed,
                anchorDate: now(),
                isPlaying: snapshot.isPlaying
            )
        } else if snapshot.artwork == nil, let previous, previous.trackIdentity == snapshot.trackIdentity {
            snapshot.artwork = previous.artwork
            snapshot.artworkMimeType = previous.artworkMimeType
        }

        let verdict = staleGuard.evaluate(prevIdentity: previous?.trackIdentity, prevAlbum: previous?.album ?? "", prevArtist: previous?.artist ?? "", prevDigest: previous?.artworkDigest, incomingIdentity: snapshot.trackIdentity, incomingAlbum: snapshot.album, incomingArtist: snapshot.artist, incomingDigest: snapshot.artworkDigest, now: Date())
        if verdict == .suppressArtwork { snapshot.artwork = nil }
        #if DEBUG
        NowPlayingTrace.log("id=\(snapshot.trackIdentity.replacingOccurrences(of: "\u{1F}", with: "|")) digest=\(String(describing: snapshot.artworkDigest)) bytes=\(snapshot.artwork?.count ?? 0) verdict=\(verdict) playing=\(snapshot.isPlaying) updatedAt=\(snapshot.updatedAt.timeIntervalSince1970)")
        #endif

        switch reconciler.evaluate(incomingElapsed: snapshot.elapsed, payloadTime: snapshot.updatedAt, now: now(), isPlaying: snapshot.isPlaying, trackIdentity: snapshot.trackIdentity) {
        case .acceptPlayer: break
        case .keepAnchor(let expected): snapshot.elapsed = expected
        }

        self.snapshot = snapshot
        lastTickAt = now()
        if snapshot.isPlaying || activeProvider is AppleScriptNowPlayingProvider {
            startTimer()
        } else {
            stopTimer()
        }
    }

    private func clearPendingSeek() {
        pendingSeek = nil
    }

    private func updateLiveActivityState() {
        let next = NowPlayingLiveActivityState.from(snapshot)
        guard next != liveActivityState else { return }
        liveActivityState = next
    }

    private func normalized(_ snapshot: NowPlayingSnapshot?) -> NowPlayingSnapshot? {
        guard var snapshot else { return nil }
        snapshot.title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.artist = snapshot.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.album = snapshot.album.trimmingCharacters(in: .whitespacesAndNewlines)
        guard snapshot.hasContent else { return nil }

        snapshot.elapsed = max(0, snapshot.elapsed)
        snapshot.duration = max(0, snapshot.duration)
        if snapshot.duration > 0 {
            snapshot.elapsed = min(snapshot.elapsed, snapshot.duration)
        }
        return snapshot
    }

    private func startTimer() {
        guard timerEnabled else {
            lastTickAt = now()
            return
        }
        stopTimer()
        lastTickAt = now()
        tickToken = MainActor.assumeIsolated {
            LifecycleManager.shared.timer(
                "nowplaying.tick",
                interval: 1.0,
                tolerance: 0.25,
                tier: .essential
            ) { [weak self] in
                guard let self else { return }
                let current = self.now()
                let elapsed = current.timeIntervalSince(self.lastTickAt ?? current)
                self.lastTickAt = current
                self.advanceElapsed(by: elapsed)
                if let appleScript = self.activeProvider as? AppleScriptNowPlayingProvider {
                    // AppleScript providers cannot push reliably; poll only while one
                    // is active (MediaRemote must have failed to reach this point).
                    appleScript.poll()
                }
            }
        }
    }

    private func stopTimer() {
        MainActor.assumeIsolated {
            tickToken?.cancel()
            tickToken = nil
        }
        lastTickAt = nil
    }

    private func startWorkspaceObserver() {
        guard workspaceObserver == nil else { return }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.clearRecoveredAppleScriptFailures()
            let preferredIndex = self.firstAvailableProviderIndex()
            if let preferredIndex, let activeProviderIndex = self.activeProviderIndex {
                if preferredIndex < activeProviderIndex {
                    self.startProvider(at: preferredIndex)
                }
            } else if self.activeProvider == nil {
                self.startFirstAvailableProvider()
            }
        }
    }

    private func clearRecoveredAppleScriptFailures() {
        for provider in providers {
            guard provider is AppleScriptNowPlayingProvider, provider.isAvailable else { continue }
            failedProviders.remove(ObjectIdentifier(provider))
        }
    }

    private func removeWorkspaceObserver() {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        workspaceObserver = nil
    }
}

struct SeekReconciler {
    struct Pending { var target: Double; var issuedAt: Date; var trackIdentity: String }
    enum Decision: Equatable { case acceptPlayer, keepAnchor(expected: Double) }
    private(set) var pending: Pending?
    static let graceWindow: TimeInterval = 0.4
    static let closeness: Double = 1.5

    mutating func begin(target: Double, now: Date, trackIdentity: String) {
        pending = Pending(target: target, issuedAt: now, trackIdentity: trackIdentity)
    }
    mutating func clear() { pending = nil }
    func expected(now: Date, isPlaying: Bool) -> Double? {
        guard let p = pending else { return nil }
        return p.target + (isPlaying ? max(0, now.timeIntervalSince(p.issuedAt)) : 0)
    }
    mutating func evaluate(incomingElapsed: Double, payloadTime: Date, now: Date, isPlaying: Bool, trackIdentity: String) -> Decision {
        guard let p = pending else { return .acceptPlayer }
        if p.trackIdentity != trackIdentity { pending = nil; return .acceptPlayer }
        let expected = p.target + (isPlaying ? max(0, now.timeIntervalSince(p.issuedAt)) : 0)
        if payloadTime < p.issuedAt { return .keepAnchor(expected: expected) }          // produced before the seek: pre-seek data
        if payloadTime < p.issuedAt.addingTimeInterval(Self.graceWindow) {              // ambiguous window: require closeness
            if abs(incomingElapsed - expected) <= Self.closeness { pending = nil; return .acceptPlayer }
            return .keepAnchor(expected: expected)
        }
        pending = nil                                                                    // genuine post-seek payload: it is the truth
        return .acceptPlayer
    }
}

struct ArtworkStaleGuard {
    enum Verdict: Equatable { case useIncoming, suppressArtwork }
    private var suspectIdentity: String?
    private var suspectDigest: Int?
    private var suspectUntil: Date?

    mutating func evaluate(prevIdentity: String?, prevAlbum: String, prevArtist: String, prevDigest: Int?,
                           incomingIdentity: String, incomingAlbum: String, incomingArtist: String,
                           incomingDigest: Int?, now: Date) -> Verdict {
        if let id = suspectIdentity, id == incomingIdentity, let until = suspectUntil {
            if incomingDigest != suspectDigest { clear(); return .useIncoming }
            if now < until { return .suppressArtwork }
            clear(); return .useIncoming
        }
        if suspectIdentity != nil && suspectIdentity != incomingIdentity { clear() }
        guard let prevIdentity, prevIdentity != incomingIdentity,
              let incomingDigest, let prevDigest, incomingDigest == prevDigest,
              (incomingAlbum != prevAlbum || incomingArtist != prevArtist) else { return .useIncoming }
        suspectIdentity = incomingIdentity
        suspectDigest = incomingDigest
        suspectUntil = now.addingTimeInterval(incomingAlbum != prevAlbum ? 8.0 : 1.5)
        return .suppressArtwork
    }
    private mutating func clear() { suspectIdentity = nil; suspectDigest = nil; suspectUntil = nil }
}

#if DEBUG
enum NowPlayingTrace {
    private static let q = DispatchQueue(label: "com.bilou.nptrace", qos: .background)
    static func log(_ s: String) {
        q.async {
            let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/BilouNook", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("nowplaying.log")
            let line = "\(Date().timeIntervalSince1970) \(s)\n"
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
            else { try? line.write(to: url, atomically: true, encoding: .utf8) }
        }
    }
}
#endif
