import XCTest

private final class FakeNowPlayingProvider: NowPlayingProvider {
    let identifier: String
    var isAvailable: Bool

    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var sentCommands: [NowPlayingCommand] = []
    private var onUpdate: ((NowPlayingSnapshot?) -> Void)?
    private var onFailure: (() -> Void)?

    init(identifier: String, isAvailable: Bool = true) {
        self.identifier = identifier
        self.isAvailable = isAvailable
    }

    func start(
        onUpdate: @escaping (NowPlayingSnapshot?) -> Void,
        onFailure: @escaping () -> Void
    ) {
        startCount += 1
        self.onUpdate = onUpdate
        self.onFailure = onFailure
    }

    func stop() {
        stopCount += 1
    }

    func send(_ command: NowPlayingCommand) {
        sentCommands.append(command)
    }

    func emit(_ snapshot: NowPlayingSnapshot?) {
        onUpdate?(snapshot)
    }

    func fail() {
        onFailure?()
    }
}

@MainActor
final class NowPlayingServiceTests: XCTestCase {
    private func makeSnapshot(
        title: String = "Song",
        artist: String = "Artist",
        album: String = "Album",
        artwork: Data? = nil,
        isPlaying: Bool = true,
        elapsed: TimeInterval = 10,
        duration: TimeInterval = 100
    ) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            title: title,
            artist: artist,
            album: album,
            artwork: artwork,
            artworkMimeType: artwork == nil ? nil : "image/jpeg",
            isPlaying: isPlaying,
            elapsed: elapsed,
            duration: duration,
            bundleIdentifier: "com.example.player",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }

    func testUsesFirstAvailableProvider() {
        let unavailable = FakeNowPlayingProvider(identifier: "unavailable", isAvailable: false)
        let primary = FakeNowPlayingProvider(identifier: "primary")
        let secondary = FakeNowPlayingProvider(identifier: "secondary")
        let service = NowPlayingService(
            providers: [unavailable, primary, secondary],
            timerEnabled: false
        )

        service.start()

        XCTAssertEqual(service.providerName, "primary")
        XCTAssertEqual(primary.startCount, 1)
        XCTAssertEqual(secondary.startCount, 0)
        XCTAssertEqual(unavailable.startCount, 0)

        service.stop()
        XCTAssertEqual(primary.stopCount, 1)
        XCTAssertEqual(service.snapshot, nil)
    }

    func testFallsBackWhenActiveProviderFails() {
        let primary = FakeNowPlayingProvider(identifier: "primary")
        let secondary = FakeNowPlayingProvider(identifier: "secondary")
        let service = NowPlayingService(
            providers: [primary, secondary],
            timerEnabled: false
        )
        service.start()
        XCTAssertEqual(service.providerName, "primary")

        primary.fail()
        settle()

        XCTAssertEqual(service.providerName, "secondary")
        XCTAssertEqual(primary.stopCount, 1)
        XCTAssertEqual(secondary.startCount, 1)
        service.stop()
    }

    func testElapsedAdvancesOnlyWhilePlaying() {
        let provider = FakeNowPlayingProvider(identifier: "fake")
        let service = NowPlayingService(providers: [provider], timerEnabled: false)
        service.start()

        provider.emit(makeSnapshot(isPlaying: true, elapsed: 10, duration: 100))
        service.advanceElapsed(by: 2.5)
        XCTAssertEqual(service.snapshot?.elapsed, 12.5)

        provider.emit(makeSnapshot(isPlaying: false, elapsed: 12.5, duration: 100))
        service.advanceElapsed(by: 5)
        XCTAssertEqual(service.snapshot?.elapsed, 12.5)
        XCTAssertEqual(service.progress, 0.125, accuracy: 0.0001)
        service.stop()
    }

    func testLiveActivityStateIgnoresElapsedChanges() {
        let provider = FakeNowPlayingProvider(identifier: "fake")
        let service = NowPlayingService(providers: [provider], timerEnabled: false)
        service.start()

        provider.emit(makeSnapshot(elapsed: 10, duration: 100))
        let liveState = service.liveActivityState
        service.advanceElapsed(by: 2.5)

        XCTAssertEqual(service.snapshot?.elapsed, 12.5)
        XCTAssertEqual(service.liveActivityState, liveState)
        service.stop()
    }

    func testLiveActivityStateTracksPlaybackTrackAndArtwork() {
        let provider = FakeNowPlayingProvider(identifier: "fake")
        let service = NowPlayingService(providers: [provider], timerEnabled: false)
        service.start()

        provider.emit(makeSnapshot(title: "A", isPlaying: true))
        XCTAssertTrue(service.liveActivityState.isPlaying)
        XCTAssertEqual(service.liveActivityState.trackIdentity, makeSnapshot(title: "A").trackIdentity)
        XCTAssertNil(service.liveActivityState.artwork)

        provider.emit(makeSnapshot(title: "A", isPlaying: false))
        XCTAssertFalse(service.liveActivityState.isPlaying)

        let artwork = Data([1, 2, 3, 4])
        provider.emit(makeSnapshot(title: "B", artwork: artwork, isPlaying: true))
        XCTAssertEqual(service.liveActivityState.trackIdentity, makeSnapshot(title: "B").trackIdentity)
        XCTAssertEqual(service.liveActivityState.artwork, artwork)
        service.stop()

        XCTAssertEqual(service.liveActivityState, .empty)
    }

    func testElapsedClampsAtDuration() {
        let provider = FakeNowPlayingProvider(identifier: "fake")
        let service = NowPlayingService(providers: [provider], timerEnabled: false)
        service.start()

        provider.emit(makeSnapshot(elapsed: 99, duration: 100))
        service.advanceElapsed(by: 5)
        XCTAssertEqual(service.snapshot?.elapsed, 100)
        service.stop()
    }

    func testArtworkIsPreservedForSameTrackAndClearedForNewTrack() {
        let provider = FakeNowPlayingProvider(identifier: "fake")
        let service = NowPlayingService(providers: [provider], timerEnabled: false)
        service.start()
        let artwork = Data([1, 2, 3, 4])

        provider.emit(makeSnapshot(title: "A", artwork: artwork))
        provider.emit(makeSnapshot(title: "A", artwork: nil))
        XCTAssertEqual(service.snapshot?.artwork, artwork)
        XCTAssertEqual(service.snapshot?.artworkMimeType, "image/jpeg")

        provider.emit(makeSnapshot(title: "B", artwork: nil))
        XCTAssertNil(service.snapshot?.artwork)
        XCTAssertNil(service.snapshot?.artworkMimeType)
        service.stop()
    }

    func testRapidTrackChangesKeepLatestSnapshot() {
        let provider = FakeNowPlayingProvider(identifier: "fake")
        let service = NowPlayingService(providers: [provider], timerEnabled: false)
        service.start()

        for index in 0..<50 {
            provider.emit(makeSnapshot(title: "Track \(index)"))
        }

        XCTAssertEqual(service.snapshot?.title, "Track 49")
        service.stop()
    }

    func testNilSnapshotClearsPlayer() {
        let provider = FakeNowPlayingProvider(identifier: "fake")
        let service = NowPlayingService(providers: [provider], timerEnabled: false)
        service.start()

        provider.emit(makeSnapshot())
        XCTAssertNotNil(service.snapshot)
        provider.emit(nil)
        XCTAssertNil(service.snapshot)
        service.stop()
    }

    func testCommandsForwardToActiveProvider() {
        let provider = FakeNowPlayingProvider(identifier: "fake")
        let service = NowPlayingService(providers: [provider], timerEnabled: false)
        service.start()
        provider.emit(makeSnapshot())

        service.togglePlayPause()
        service.next()
        service.previous()
        service.seek(to: 42)

        XCTAssertEqual(provider.sentCommands, [
            .togglePlayPause,
            .next,
            .previous,
            .seek(42),
        ])
        service.stop()
    }

    func testNoAvailableProviderReportsNone() {
        let unavailable = FakeNowPlayingProvider(identifier: "unavailable", isAvailable: false)
        let service = NowPlayingService(providers: [unavailable], timerEnabled: false)

        service.start()
        XCTAssertEqual(service.providerName, "none")
        XCTAssertNil(service.snapshot)
        service.stop()
    }

    func testEmptyMetadataIsIgnored() {
        let provider = FakeNowPlayingProvider(identifier: "fake")
        let service = NowPlayingService(providers: [provider], timerEnabled: false)
        service.start()

        provider.emit(NowPlayingSnapshot(title: "   "))
        XCTAssertNil(service.snapshot)
        service.stop()
    }

    func testAppleScriptProviderNeverRunsWhenAppIsNotRunning() {
        var scriptRuns = 0
        let provider = AppleScriptNowPlayingProvider(
            target: .spotify,
            runningCheck: { _ in false },
            scriptRunner: { _ in
                scriptRuns += 1
                return ScriptRun(result: .success(NSAppleEventDescriptor.null()), duration: 0)
            }
        )
        var updates: [NowPlayingSnapshot?] = []
        provider.start(onUpdate: { updates.append($0) }, onFailure: {})
        settle()

        provider.send(.togglePlayPause)
        provider.send(.seek(30))
        settle()

        XCTAssertEqual(scriptRuns, 0)
        XCTAssertEqual(updates.count, 1)
        XCTAssertNil(updates[0])
        provider.stop()
    }

    func testAppleScriptProviderFailsAfterThreeConsecutiveTimeouts() {
        var failureCount = 0
        let provider = AppleScriptNowPlayingProvider(
            target: .music,
            runningCheck: { _ in true },
            scriptRunner: { _ in
                ScriptRun(result: .success(NSAppleEventDescriptor.null()), duration: 2.0)
            }
        )
        provider.start(onUpdate: { _ in }, onFailure: { failureCount += 1 })
        settle()
        provider.poll()
        settle()
        provider.poll()
        settle()

        XCTAssertEqual(failureCount, 1)
        provider.stop()
    }

    func testArtTrackChangeDropsPreviousArtworkWithNewMetadata() {
        // T1
        let provider = FakeNowPlayingProvider(identifier: "fake")
        let service = NowPlayingService(providers: [provider], timerEnabled: false)
        service.start()

        provider.emit(makeSnapshot(title: "A", artwork: Data([1, 2, 3, 4])))
        provider.emit(makeSnapshot(title: "B", artwork: nil))

        XCTAssertEqual(service.snapshot?.title, "B")
        XCTAssertNil(service.snapshot?.artwork)
        service.stop()
    }

    func testArtTrackChangePublishesNewArtworkWithNewMetadata() {
        // T2
        let provider = FakeNowPlayingProvider(identifier: "fake")
        let service = NowPlayingService(providers: [provider], timerEnabled: false)
        service.start()

        let newArtwork = Data([9, 8, 7, 6, 5])
        provider.emit(makeSnapshot(title: "A", artwork: Data([1, 2, 3, 4])))
        provider.emit(makeSnapshot(title: "B", artwork: newArtwork))

        XCTAssertEqual(service.snapshot?.title, "B")
        XCTAssertEqual(service.snapshot?.artwork, newArtwork)
        service.stop()
    }

    func testSameTrackKeepsArtworkWhenUpdateCarriesNone() {
        // T3
        let provider = FakeNowPlayingProvider(identifier: "fake")
        let service = NowPlayingService(providers: [provider], timerEnabled: false)
        service.start()
        let artwork = Data([1, 2, 3, 4])

        provider.emit(makeSnapshot(title: "A", artwork: artwork))
        provider.emit(makeSnapshot(title: "A", artwork: nil))

        XCTAssertEqual(service.snapshot?.artwork, artwork)
        service.stop()
    }

    func testLiveActivityStateChangesOnlyWithIdentity() {
        // T5 — stable across 1 Hz ticks; differs on track change and on artwork identity change
        let provider = FakeNowPlayingProvider(identifier: "fake")
        let service = NowPlayingService(providers: [provider], timerEnabled: false)
        service.start()

        provider.emit(makeSnapshot(title: "A", isPlaying: true, elapsed: 10))
        let stateA = service.liveActivityState
        provider.emit(makeSnapshot(title: "A", isPlaying: true, elapsed: 11))
        XCTAssertEqual(service.liveActivityState, stateA)

        provider.emit(makeSnapshot(title: "B", isPlaying: true, elapsed: 11))
        XCTAssertNotEqual(service.liveActivityState, stateA)
        let stateB = service.liveActivityState

        provider.emit(makeSnapshot(title: "B", artwork: Data([1]), isPlaying: true, elapsed: 11))
        let stateC = service.liveActivityState
        XCTAssertNotEqual(stateC, stateB)
        provider.emit(makeSnapshot(title: "B", artwork: Data([1, 2, 3, 4, 5]), isPlaying: true, elapsed: 11))
        XCTAssertNotEqual(service.liveActivityState, stateC)
        service.stop()
    }
}

final class MediaRemoteNowPlayingProviderTests: XCTestCase {
    func testSnapshotParsesArtworkAndPlayback() {
        let payload: [String: Any] = [
            "title": "Song",
            "artist": "Artist",
            "album": "Album",
            "artworkData": Data([1, 2, 3]).base64EncodedString(),
            "artworkMimeType": "image/png",
            "playing": true,
            "elapsedTime": 12.5,
            "duration": 100.0,
            "bundleIdentifier": "com.example.player",
        ]

        let snapshot = MediaRemoteNowPlayingProvider.snapshot(from: payload)

        XCTAssertEqual(snapshot?.title, "Song")
        XCTAssertEqual(snapshot?.artist, "Artist")
        XCTAssertEqual(snapshot?.album, "Album")
        XCTAssertEqual(snapshot?.artwork, Data([1, 2, 3]))
        XCTAssertEqual(snapshot?.artworkMimeType, "image/png")
        XCTAssertEqual(snapshot?.isPlaying, true)
        XCTAssertEqual(snapshot?.elapsed, 12.5)
        XCTAssertEqual(snapshot?.duration, 100)
        XCTAssertEqual(snapshot?.bundleIdentifier, "com.example.player")
        XCTAssertNil(snapshot?.parentApplicationBundleIdentifier)
    }

    func testSnapshotCarriesParentApplicationBundleIdentifier() {
        let payload: [String: Any] = [
            "title": "Live Stream",
            "bundleIdentifier": "com.apple.WebKit.GPU",
            "parentApplicationBundleIdentifier": "com.apple.Safari",
            "playing": false,
        ]

        let snapshot = MediaRemoteNowPlayingProvider.snapshot(from: payload)

        XCTAssertEqual(snapshot?.bundleIdentifier, "com.apple.WebKit.GPU")
        XCTAssertEqual(snapshot?.parentApplicationBundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(snapshot?.sourceBundleIdentifier, "com.apple.Safari")
    }

    func testSnapshotRejectsEmptyOrUntitledPayload() {
        XCTAssertNil(MediaRemoteNowPlayingProvider.snapshot(from: [:]))
        XCTAssertNil(MediaRemoteNowPlayingProvider.snapshot(from: ["playing": true]))
        XCTAssertNil(MediaRemoteNowPlayingProvider.snapshot(from: ["title": "   "]))
    }

    func testStopTerminatesStreamingHelper() throws {
        let (directory, provider) = try makeFakeStreamingProvider()
        defer { try? FileManager.default.removeItem(at: directory) }

        provider.start(onUpdate: { _ in }, onFailure: {})
        XCTAssertTrue(provider.isStreaming)

        provider.stop()
        XCTAssertFalse(provider.isStreaming)
    }

    func testStopLeavesNoHandlersAndTerminatesProcess() throws {
        let (directory, provider) = try makeFakeStreamingProvider()
        defer { try? FileManager.default.removeItem(at: directory) }

        provider.start(onUpdate: { _ in }, onFailure: {})
        XCTAssertTrue(provider.isStreaming)

        provider.stop()
        XCTAssertFalse(provider.isStreaming)
        XCTAssertTrue(provider._handlesClearedForTesting)
    }

    func testIdenticalArtworkStringDecodesOnce() {
        let encoded = Data([1, 2, 3, 4, 5]).base64EncodedString()
        let payload: [String: Any] = [
            "title": "Song",
            "artworkData": encoded,
        ]
        let decodesBefore = MediaRemoteNowPlayingProvider.artworkDecodeCount

        let first = MediaRemoteNowPlayingProvider.snapshot(from: payload)
        let second = MediaRemoteNowPlayingProvider.snapshot(from: payload)

        XCTAssertEqual(MediaRemoteNowPlayingProvider.artworkDecodeCount - decodesBefore, 1)
        XCTAssertEqual(first?.artwork, second?.artwork)
        XCTAssertNil(MediaRemoteNowPlayingProvider.snapshot(from: ["title": "Song", "artworkData": ""])?.artwork)
    }

    private func makeFakeStreamingProvider() throws -> (URL, MediaRemoteNowPlayingProvider) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NowPlayingTests-\(UUID().uuidString)", isDirectory: true)
        let framework = directory.appendingPathComponent("MediaRemoteAdapter.framework", isDirectory: true)
        let binary = framework.appendingPathComponent("MediaRemoteAdapter")
        let script = directory.appendingPathComponent("mediaremote-adapter.pl")
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        try Data().write(to: binary)
        try "sleep 60\n".write(to: script, atomically: true, encoding: .utf8)
        let provider = MediaRemoteNowPlayingProvider(
            runtime: .init(script: script, framework: framework)
        )
        return (directory, provider)
    }
}

@MainActor
final class NowPlayingPendingSeekTests: XCTestCase {
    func testStalePayloadBeforeSeekNeverOverwritesElapsed() {
        var r = SeekReconciler(); let t0 = Date()
        r.begin(target: 105, now: t0, trackIdentity: "a")
        let d = r.evaluate(incomingElapsed: 22, payloadTime: t0.addingTimeInterval(-5), now: t0.addingTimeInterval(9), isPlaying: true, trackIdentity: "a")
        XCTAssertEqual(d, .keepAnchor(expected: 114)); XCTAssertNotNil(r.pending)
    }
    func testGraceWindowRequiresCloseness() {
        var r = SeekReconciler(); let t0 = Date()
        r.begin(target: 105, now: t0, trackIdentity: "a")
        let far = r.evaluate(incomingElapsed: 22, payloadTime: t0.addingTimeInterval(0.2), now: t0.addingTimeInterval(0.25), isPlaying: true, trackIdentity: "a")
        XCTAssertEqual(far, .keepAnchor(expected: 105.25))
        let near = r.evaluate(incomingElapsed: 105.3, payloadTime: t0.addingTimeInterval(0.3), now: t0.addingTimeInterval(0.35), isPlaying: true, trackIdentity: "a")
        XCTAssertEqual(near, .acceptPlayer); XCTAssertNil(r.pending)
    }
    func testPostSeekPayloadIsTruthEvenIfFar() {
        var r = SeekReconciler(); let t0 = Date()
        r.begin(target: 105, now: t0, trackIdentity: "a")
        let d = r.evaluate(incomingElapsed: 40, payloadTime: t0.addingTimeInterval(1.0), now: t0.addingTimeInterval(1.05), isPlaying: true, trackIdentity: "a")
        XCTAssertEqual(d, .acceptPlayer); XCTAssertNil(r.pending)
    }
    func testPausedDoesNotExtrapolate() {
        var r = SeekReconciler(); let t0 = Date()
        r.begin(target: 50, now: t0, trackIdentity: "a")
        XCTAssertEqual(r.expected(now: t0.addingTimeInterval(4), isPlaying: false), 50)
    }
    func testTrackChangeClearsPending() {
        var r = SeekReconciler(); let t0 = Date()
        r.begin(target: 50, now: t0, trackIdentity: "a")
        XCTAssertEqual(r.evaluate(incomingElapsed: 3, payloadTime: t0.addingTimeInterval(0.1), now: t0.addingTimeInterval(0.1), isPlaying: true, trackIdentity: "b"), .acceptPlayer)
        XCTAssertNil(r.pending)
    }
}

final class LifecycleManagerTests: XCTestCase {
    func testEventGateCapsRate() {
        var g = EventGate(minInterval: 1.0/60.0)
        XCTAssertTrue(g.allow(1.000)); XCTAssertFalse(g.allow(1.005)); XCTAssertTrue(g.allow(1.020))
    }

    @MainActor
    func testLifecycleStopsWhileOpenEntriesOnClose() {
        let lm = LifecycleManager.shared
        var starts = 0, stops = 0
        let tok = lm.register("test.open", tier: .whileOpen, start: { starts += 1 }, stop: { stops += 1 })
        lm.setNotchOpen(true); lm.setNotchOpen(false)
        XCTAssertEqual(starts, 1); XCTAssertEqual(stops, 1)
        lm.setNotchOpen(true); tok.cancel()
        XCTAssertEqual(stops, 2)
        lm.setNotchOpen(false)
    }

    @MainActor
    func testLifecycleSleepStopsEssential() {
        let lm = LifecycleManager.shared
        var running = false
        let tok = lm.register("test.essential", tier: .essential, start: { running = true }, stop: { running = false })
        XCTAssertTrue(running); lm.setSystemAwake(false); XCTAssertFalse(running)
        lm.setSystemAwake(true); XCTAssertTrue(running); tok.cancel()
    }
}

final class ArtworkStaleGuardTests: XCTestCase {
    func testStaleArtworkSuppressedWhenAlbumChanges() {
        var g = ArtworkStaleGuard(); let t0 = Date()
        XCTAssertEqual(g.evaluate(prevIdentity: "a", prevAlbum: "A", prevArtist: "X", prevDigest: 7, incomingIdentity: "b", incomingAlbum: "B", incomingArtist: "X", incomingDigest: 7, now: t0), .suppressArtwork)
        XCTAssertEqual(g.evaluate(prevIdentity: "a", prevAlbum: "A", prevArtist: "X", prevDigest: 7, incomingIdentity: "b", incomingAlbum: "B", incomingArtist: "X", incomingDigest: 7, now: t0.addingTimeInterval(5)), .suppressArtwork)
        XCTAssertEqual(g.evaluate(prevIdentity: "a", prevAlbum: "A", prevArtist: "X", prevDigest: 7, incomingIdentity: "b", incomingAlbum: "B", incomingArtist: "X", incomingDigest: 9, now: t0.addingTimeInterval(5.1)), .useIncoming)
    }
    func testSameAlbumSameArtKeepsArtwork() {
        var g = ArtworkStaleGuard()
        XCTAssertEqual(g.evaluate(prevIdentity: "a", prevAlbum: "A", prevArtist: "X", prevDigest: 7, incomingIdentity: "b", incomingAlbum: "A", incomingArtist: "X", incomingDigest: 7, now: Date()), .useIncoming)
    }
    func testSuppressionExpiresAfterWindow() {
        var g = ArtworkStaleGuard(); let t0 = Date()
        _ = g.evaluate(prevIdentity: "a", prevAlbum: "A", prevArtist: "X", prevDigest: 7, incomingIdentity: "b", incomingAlbum: "A", incomingArtist: "Y", incomingDigest: 7, now: t0)
        XCTAssertEqual(g.evaluate(prevIdentity: "a", prevAlbum: "A", prevArtist: "X", prevDigest: 7, incomingIdentity: "b", incomingAlbum: "A", incomingArtist: "Y", incomingDigest: 7, now: t0.addingTimeInterval(1.6)), .useIncoming)
    }
}


@MainActor
final class AirDropTransferTests: XCTestCase {
    func testSendFlowPhases() {
        let t = AirDropTransfer.shared
        t.pickerOpened(); XCTAssertEqual(t.phase, .picker); XCTAssertFalse(t.isVisibleOnIsland)
        t.began(); XCTAssertEqual(t.phase, .sending); XCTAssertTrue(t.isVisibleOnIsland)
        t.finished(success: true); XCTAssertEqual(t.phase, .sent); XCTAssertTrue(t.isVisibleOnIsland)
        t.cancelled(); XCTAssertEqual(t.phase, .idle)
    }
    func testFailureAndCancel() {
        let t = AirDropTransfer.shared
        t.began(); t.finished(success: false); XCTAssertEqual(t.phase, .failed)
        t.pickerOpened(); t.cancelled(); XCTAssertEqual(t.phase, .idle); XCTAssertFalse(t.isVisibleOnIsland)
    }
    func testNotchHoldReleases() {
        NotchHold.shared.hold(seconds: 60); XCTAssertTrue(NotchHold.shared.isActive)
        NotchHold.shared.release(); XCTAssertFalse(NotchHold.shared.isActive)
    }
}

final class IslandLayoutTests: XCTestCase {
    func testModePriority() {
        XCTAssertEqual(IslandLayout.mode(mediaPlaying: true, timerActive: true, airdropVisible: true, trayCount: 3), .airdrop)
        XCTAssertEqual(IslandLayout.mode(mediaPlaying: true, timerActive: true, airdropVisible: false, trayCount: 3), .split)
        XCTAssertEqual(IslandLayout.mode(mediaPlaying: false, timerActive: true, airdropVisible: false, trayCount: 3), .timer)
        XCTAssertEqual(IslandLayout.mode(mediaPlaying: true, timerActive: false, airdropVisible: false, trayCount: 3), .media)
        XCTAssertEqual(IslandLayout.mode(mediaPlaying: false, timerActive: false, airdropVisible: false, trayCount: 2), .storage)
        XCTAssertEqual(IslandLayout.mode(mediaPlaying: false, timerActive: false, airdropVisible: false, trayCount: 0), .none)
    }
    func testWings() {
        XCTAssertEqual(IslandLayout.wing(for: .media), 36)
        XCTAssertEqual(IslandLayout.wing(for: .split), 36)
        XCTAssertEqual(IslandLayout.wing(for: .timer), 36)
        XCTAssertEqual(IslandLayout.wing(for: .airdrop), 36)
        XCTAssertEqual(IslandLayout.wing(for: .storage), 36)
        XCTAssertEqual(IslandLayout.wing(for: .none), 0)
    }
}

@MainActor
final class TimerServiceTests: XCTestCase {
    private func make(_ now: Date) -> (TimerService, () -> Date, (TimeInterval) -> Void) {
        let s = TimerService()
        var current = now
        s.clock = { current }
        return (s, { current }, { current = current.addingTimeInterval($0) })
    }
    func testCountdownFromEndDate() {
        let (s, _, advance) = make(Date())
        s.pickHours = 0; s.pickMinutes = 1; s.pickSeconds = 30
        s.start(); XCTAssertEqual(s.displaySeconds, 90); XCTAssertEqual(s.state, .running)
        advance(30); s.tick(); XCTAssertEqual(s.displaySeconds, 60)
        s.cancel()
    }
    func testPauseResume() {
        let (s, _, advance) = make(Date())
        s.pickHours = 0; s.pickMinutes = 1; s.pickSeconds = 0
        s.start(); advance(20); s.pause()
        XCTAssertEqual(s.state, .paused); XCTAssertEqual(s.displaySeconds, 40)
        advance(100); s.resume(); advance(10); s.tick()
        XCTAssertEqual(s.displaySeconds, 30)
        s.cancel()
    }
    func testFinishAndZeroStartBlocked() {
        let (s, _, advance) = make(Date())
        s.pickHours = 0; s.pickMinutes = 0; s.pickSeconds = 0
        s.start(); XCTAssertEqual(s.state, .idle)
        s.pickSeconds = 5; s.start(); advance(6); s.tick()
        XCTAssertEqual(s.state, .finished); XCTAssertEqual(s.displaySeconds, 0)
        s.cancel()
    }
    func testFormat() {
        XCTAssertEqual(TimerFormat.string(5), "00:05")
        XCTAssertEqual(TimerFormat.string(323), "05:23")
        XCTAssertEqual(TimerFormat.string(3725), "1:02:05")
    }
}

@MainActor
final class TimerPomodoroTests: XCTestCase {
    private func make() -> (TimerService, (TimeInterval) -> Void) {
        let s = TimerService()
        var now = Date()
        s.clock = { now }
        return (s, { now = now.addingTimeInterval($0) })
    }
    func testPomodoroTwoRounds() {
        let (s, advance) = make()
        s.mode = .pomodoro; s.focusMinutes = 1; s.restMinutes = 1; s.rounds = 2
        s.start()
        XCTAssertEqual(s.phase, .focus); XCTAssertEqual(s.round, 1); XCTAssertEqual(s.displaySeconds, 60)
        advance(61); s.tick()
        XCTAssertEqual(s.phase, .rest); XCTAssertEqual(s.state, .running)
        XCTAssertEqual(s.announcement?.title, "Focus 1 of 2 complete")
        advance(61); s.tick()
        XCTAssertEqual(s.phase, .focus); XCTAssertEqual(s.round, 2)
        advance(61); s.tick()
        XCTAssertEqual(s.state, .finished); XCTAssertEqual(s.announcement?.isFinal, true)
        s.stopFinished(); XCTAssertEqual(s.state, .idle); XCTAssertNil(s.announcement)
    }
    func testSkipMovesToRest() {
        let (s, _) = make()
        s.mode = .pomodoro; s.focusMinutes = 25; s.restMinutes = 5; s.rounds = 3
        s.start(); s.skipPhase()
        XCTAssertEqual(s.phase, .rest); XCTAssertEqual(s.displaySeconds, 300)
        s.cancel()
    }
    func testTimerFinishLoopsSoundAndRestartKeepsDuration() {
        let (s, advance) = make()
        var looped = false
        s.playAlarm = { _, loop in looped = loop }
        s.mode = .timer; s.pickHours = 0; s.pickMinutes = 0; s.pickSeconds = 5
        s.endAction = .sound("Glass")
        s.start(); advance(6); s.tick()
        XCTAssertEqual(s.state, .finished); XCTAssertTrue(looped)
        s.restart()
        XCTAssertEqual(s.state, .running); XCTAssertEqual(s.displaySeconds, 5)
        s.cancel()
    }
    func testStopPlayingPausesMediaInsteadOfSound() {
        let (s, advance) = make()
        var media = false, sound = false
        s.stopMedia = { media = true }
        s.playAlarm = { _, _ in sound = true }
        s.pickMinutes = 0; s.pickSeconds = 3
        s.endAction = .stopPlaying
        s.start(); advance(4); s.tick()
        XCTAssertTrue(media); XCTAssertFalse(sound)
        s.cancel()
    }
    func testAttentionRequestedOnFinishAndPhaseChange() {
        let (s, advance) = make()
        var asked: [TimeInterval] = []
        s.requestAttention = { asked.append($0) }
        s.mode = .pomodoro; s.focusMinutes = 1; s.restMinutes = 1; s.rounds = 2
        s.start(); advance(61); s.tick()
        XCTAssertEqual(asked, [6])
        s.cancel()
    }
    func testEndActionStorage() {
        XCTAssertEqual(TimerService.EndAction(storage: "stop"), .stopPlaying)
        XCTAssertEqual(TimerService.EndAction(storage: "sound:Hero"), .sound("Hero"))
        XCTAssertEqual(TimerService.EndAction(storage: nil), .sound("Glass"))
        XCTAssertEqual(TimerService.EndAction.sound("Ping").storage, "sound:Ping")
    }
    func testSoundCatalog() {
        XCTAssertFalse(SystemSounds.names.isEmpty)
        XCTAssertEqual(TimerSoundCatalog.items.first, "Stop playing")
        XCTAssertGreaterThanOrEqual(TimerSoundCatalog.pageCount, 1)
    }
}

#if DEBUG
final class LayoutDumpTests: XCTestCase {
    func testOverlapFullPartialNone() {
        let n = LayoutDump.Rect(x: 100, y: 0, w: 200, h: 32)
        XCTAssertEqual(LayoutDump.overlapPct(.init(x: 120, y: 4, w: 40, h: 10), notch: n), 100, accuracy: 0.001)
        XCTAssertEqual(LayoutDump.overlapPct(.init(x: 80, y: 0, w: 40, h: 32), notch: n), 50, accuracy: 0.001)
        XCTAssertEqual(LayoutDump.overlapPct(.init(x: 0, y: 0, w: 50, h: 32), notch: n), 0, accuracy: 0.001)
        XCTAssertEqual(LayoutDump.overlapPct(.init(x: 120, y: 40, w: 40, h: 10), notch: n), 0, accuracy: 0.001)
        XCTAssertEqual(LayoutDump.overlapPct(.init(x: 120, y: 4, w: 40, h: 10), notch: nil), 0, accuracy: 0.001)
    }
}
#endif

final class NotchPresentationTests: XCTestCase {
    private func geometry(notch: Bool) -> NotchGeometry {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        if notch {
            return NotchGeometry(
                screenFrame: frame,
                backingScaleFactor: 2,
                auxLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
                auxRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32),
                safeAreaTop: 32
            )
        }
        return NotchGeometry(screenFrame: frame, backingScaleFactor: 2, auxLeft: nil, auxRight: nil, safeAreaTop: 0)
    }

    func testResolve() {
        XCTAssertEqual(NotchPresentationMode.resolve(hasHardwareNotch: true, showIslandStyle: true), .mergedWithPhysical)
        XCTAssertEqual(NotchPresentationMode.resolve(hasHardwareNotch: true, showIslandStyle: false), .mergedWithPhysical)
        XCTAssertEqual(NotchPresentationMode.resolve(hasHardwareNotch: false, showIslandStyle: true), .ownDynamicIsland)
        XCTAssertEqual(NotchPresentationMode.resolve(hasHardwareNotch: false, showIslandStyle: false), .edgePinned)
    }

    func testGeometryModes() {
        let notched = geometry(notch: true)
        XCTAssertEqual(notched.hardwareNotchRect?.width ?? 0, 185, accuracy: 0.001)
        XCTAssertEqual(notched.presentationMode, .mergedWithPhysical)
        let plain = geometry(notch: false)
        XCTAssertEqual(plain.presentationMode, .ownDynamicIsland)
        XCTAssertEqual(plain.withIslandStyle(false).presentationMode, .edgePinned)
        XCTAssertEqual(plain.withIslandStyle(false).notchRect, plain.notchRect)
    }

    func testStyleRadii() {
        XCTAssertEqual(NotchPresentationStyle.topRadius(base: 6, userFlare: 0), 0)
        XCTAssertEqual(NotchPresentationStyle.topRadius(base: 6, userFlare: 4), 6)
        XCTAssertEqual(NotchPresentationStyle.bottomRadius(mode: .ownDynamicIsland, base: 14, isOpen: false), 22)
        XCTAssertEqual(NotchPresentationStyle.bottomRadius(mode: .ownDynamicIsland, base: 14, isOpen: true), 24)
        XCTAssertEqual(NotchPresentationStyle.bottomRadius(mode: .mergedWithPhysical, base: 14, isOpen: true), 14)
        XCTAssertEqual(NotchPresentationStyle.bottomRadius(mode: .edgePinned, base: 20, isOpen: false), 20)
    }
}

final class NotchSafeAreaTests: XCTestCase {
    func testContentTopAndRange() {
        let s = NotchSafeArea(hasHardwareNotch: true, notchWidth: 185, notchHeight: 32)
        XCTAssertEqual(s.contentTop, 34)
        let r = s.excludedXRange(shapeWidth: 420)
        XCTAssertEqual(r.lowerBound, 117.5, accuracy: 0.001)
        XCTAssertEqual(r.upperBound, 302.5, accuracy: 0.001)
    }

    func testIntersection() {
        let s = NotchSafeArea(hasHardwareNotch: true, notchWidth: 185, notchHeight: 32)
        XCTAssertTrue(s.intersectsNotch(x: 266, y: 21.5, width: 142, shapeWidth: 420))
        XCTAssertFalse(s.intersectsNotch(x: 266, y: 34, width: 142, shapeWidth: 420))
        XCTAssertFalse(s.intersectsNotch(x: 8, y: 10, width: 100, shapeWidth: 420))
    }

    func testFromGeometry() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let g = NotchGeometry(
            screenFrame: frame,
            backingScaleFactor: 2,
            auxLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
            auxRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32),
            safeAreaTop: 32
        )
        let s = NotchSafeArea.from(g)
        XCTAssertTrue(s.hasHardwareNotch)
        XCTAssertEqual(s.notchWidth, 185, accuracy: 0.001)
        XCTAssertEqual(s.contentTop, 34, accuracy: 0.001)
    }
}

final class TriggerRectCalculatorTests: XCTestCase {
    private let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)

    private func notched() -> NotchGeometry {
        NotchGeometry(
            screenFrame: frame,
            backingScaleFactor: 2,
            auxLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
            auxRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32),
            safeAreaTop: 32
        )
    }

    private func plain(island: Bool) -> NotchGeometry {
        NotchGeometry(screenFrame: frame, backingScaleFactor: 2, auxLeft: nil, auxRight: nil, safeAreaTop: 0)
            .withIslandStyle(island)
    }

    func testMergedRect() {
        let r = TriggerRectCalculator.rect(screenFrame: frame, geometry: notched(), liveActivityWing: 0, paddingX: 6, paddingBelow: 4)
        XCTAssertEqual(r.minX, 657.5, accuracy: 0.001)
        XCTAssertEqual(r.width, 197, accuracy: 0.001)
        XCTAssertEqual(r.minY, 946, accuracy: 0.001)
        XCTAssertEqual(r.height, 36, accuracy: 0.001)
        XCTAssertEqual(r.maxY, 982, accuracy: 0.001)
    }

    func testMergedRectWithWings() {
        let r = TriggerRectCalculator.rect(screenFrame: frame, geometry: notched(), liveActivityWing: 36, paddingX: 6, paddingBelow: 4)
        XCTAssertEqual(r.width, 269, accuracy: 0.001)
    }

    func testOwnIslandRect() {
        let r = TriggerRectCalculator.rect(screenFrame: frame, geometry: plain(island: true), liveActivityWing: 0, paddingX: 6, paddingBelow: 4)
        XCTAssertEqual(r.minX, 649.5, accuracy: 0.001)
        XCTAssertEqual(r.width, 213, accuracy: 0.001)
        XCTAssertEqual(r.minY, 943.5, accuracy: 0.001)
        XCTAssertEqual(r.height, 38.5, accuracy: 0.001)
    }

    func testEdgeStrip() {
        let r = TriggerRectCalculator.rect(screenFrame: frame, geometry: plain(island: false), liveActivityWing: 0, paddingX: 6, paddingBelow: 4)
        XCTAssertEqual(r.minX, 656, accuracy: 0.001)
        XCTAssertEqual(r.width, 200, accuracy: 0.001)
        XCTAssertEqual(r.minY, 978, accuracy: 0.001)
        XCTAssertEqual(r.height, 4, accuracy: 0.001)
    }

    func testDwell() {
        XCTAssertEqual(TriggerRectCalculator.dwell(mode: .edgePinned, hasLiveActivity: false), 0.12)
        XCTAssertEqual(TriggerRectCalculator.dwell(mode: .edgePinned, hasLiveActivity: true), 0)
        XCTAssertEqual(TriggerRectCalculator.dwell(mode: .mergedWithPhysical, hasLiveActivity: false), 0)
        XCTAssertEqual(TriggerRectCalculator.dwell(mode: .ownDynamicIsland, hasLiveActivity: false), 0)
    }
}

final class AnimationsPresentationTests: XCTestCase {
    override func tearDown() {
        Animations.presentationMode = .mergedWithPhysical
        super.tearDown()
    }

    func testOpenPlansPerMode() {
        Animations.presentationMode = .mergedWithPhysical
        XCTAssertEqual(Animations.plan(for: .openMetrics, reduceMotion: false), .spring(response: 0.26, dampingFraction: 0.88))
        Animations.presentationMode = .ownDynamicIsland
        XCTAssertEqual(Animations.plan(for: .openMetrics, reduceMotion: false), .spring(response: 0.34, dampingFraction: 0.80))
        Animations.presentationMode = .edgePinned
        XCTAssertEqual(Animations.plan(for: .openMetrics, reduceMotion: false), .timingCurve(c1x: 0.0, c1y: 0.0, c2x: 0.58, c2y: 1.0, duration: 0.28))
    }

    func testClosePlanIsSharedAndReduceMotionIsFade() {
        for mode in [NotchPresentationMode.mergedWithPhysical, .ownDynamicIsland, .edgePinned] {
            Animations.presentationMode = mode
            XCTAssertEqual(Animations.plan(for: .closeMetrics, reduceMotion: false), .spring(response: 0.22, dampingFraction: 1.0))
            XCTAssertEqual(Animations.plan(for: .openMetrics, reduceMotion: true), .crossfade(duration: 0.10))
        }
    }

    func testRevealDelays() {
        XCTAssertEqual(Animations.contentRevealDelay(for: .mergedWithPhysical, reduceMotion: false), 0.092, accuracy: 0.0001)
        XCTAssertEqual(Animations.contentRevealDelay(for: .ownDynamicIsland, reduceMotion: false), 0.096, accuracy: 0.0001)
        XCTAssertEqual(Animations.contentRevealDelay(for: .edgePinned, reduceMotion: false), 0.119, accuracy: 0.0001)
        XCTAssertEqual(Animations.contentRevealDelay(for: .edgePinned, reduceMotion: true), 0)
    }
}

final class TimerLayoutTests: XCTestCase {
    func testWheelMath() {
        XCTAssertEqual(TimerLayout.rowHeight * 3, TimerLayout.wheelHeight)
        XCTAssertEqual(TimerLayout.columnWidth * 3, TimerLayout.wheelsWidth)
        XCTAssertEqual(TimerLayout.selectionBarHeight, 48)
    }

    func testRightColumnRhythm() {
        let total = TimerLayout.segmentedHeight + TimerLayout.rightSpacing + TimerLayout.circleDiameter + TimerLayout.rightSpacing + TimerLayout.soundRowHeight
        XCTAssertEqual(total, TimerLayout.contentHeight)
    }

    func testPanelHeight() {
        XCTAssertEqual(TimerLayout.panelHeight(notchHeight: 32), 32 + 2 + 132 + NookLayout.bottomPadding)
    }

    func testSoundPaging() {
        XCTAssertEqual(TimerSoundCatalog.perPage, 9)
        XCTAssertGreaterThanOrEqual(TimerSoundCatalog.pageCount, 2)
    }
}
