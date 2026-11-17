import AppKit
import SwiftUI
import XCTest

#if DEBUG
@MainActor
final class MediaWidgetSnapshotTests: XCTestCase {
    private struct Scenario {
        let name: String
        let snapshot: NowPlayingSnapshot?
        let hovered: Bool

        init(name: String, snapshot: NowPlayingSnapshot?, hovered: Bool = false) {
            self.name = name
            self.snapshot = snapshot
            self.hovered = hovered
        }
    }

    func testRenderMediaWidgetStatesToScreens() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("build/screens")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let now = Date()
        let artwork = makeArtwork()
        let scenarios = [
            Scenario(
                name: "playing",
                snapshot: snapshot(
                    title: "Midnight City",
                    artist: "M83",
                    album: "Hurry Up, We're Dreaming",
                    artwork: artwork,
                    isPlaying: true,
                    elapsed: 84,
                    duration: 244,
                    now: now
                )
            ),
            Scenario(
                name: "paused",
                snapshot: snapshot(
                    title: "Midnight City",
                    artist: "M83",
                    album: "Hurry Up, We're Dreaming",
                    artwork: artwork,
                    isPlaying: false,
                    elapsed: 84,
                    duration: 244,
                    now: now
                )
            ),
            Scenario(
                name: "long-title",
                snapshot: snapshot(
                    title: "The Longest Song Title In The Entire World (Extended Midnight Mix)",
                    artist: "The Very Long Artist Name Orchestra",
                    album: "An Album With A Considerably Long Name",
                    artwork: artwork,
                    isPlaying: true,
                    elapsed: 40,
                    duration: 300,
                    now: now
                )
            ),
            Scenario(
                name: "no-album",
                snapshot: snapshot(
                    title: "No Album Here",
                    artist: "Single Artist",
                    album: "",
                    artwork: artwork,
                    isPlaying: true,
                    elapsed: 12,
                    duration: 180,
                    now: now
                )
            ),
            Scenario(name: "empty", snapshot: nil),
            Scenario(
                name: "hovered-with-scrubber",
                snapshot: snapshot(
                    title: "Midnight City",
                    artist: "M83",
                    album: "Hurry Up, We're Dreaming",
                    artwork: artwork,
                    isPlaying: true,
                    elapsed: 84,
                    duration: 244,
                    now: now
                ),
                hovered: true
            ),
        ]

        for scenario in scenarios {
            let service = NowPlayingService(providers: [], timerEnabled: false)
            service.setSnapshotForTesting(scenario.snapshot)
            let data = try render(service: service, hovered: scenario.hovered)
            let url = output.appendingPathComponent("media-widget-\(scenario.name).png")
            try data.write(to: url)
            XCTAssertGreaterThan(data.count, 3_000, url.lastPathComponent)
            print("[MEDIA WIDGET] \(url.path)")
        }
    }

    private func snapshot(
        title: String,
        artist: String,
        album: String,
        artwork: Data?,
        isPlaying: Bool,
        elapsed: TimeInterval,
        duration: TimeInterval,
        now: Date
    ) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            title: title,
            artist: artist,
            album: album,
            artwork: artwork,
            artworkMimeType: "image/png",
            isPlaying: isPlaying,
            elapsed: elapsed,
            duration: duration,
            bundleIdentifier: "com.apple.Music",
            parentApplicationBundleIdentifier: "com.apple.Music",
            updatedAt: now
        )
    }

    private func render(service: NowPlayingService, hovered: Bool) throws -> Data {
        let widget = MediaWidgetView(hoverOverride: hovered)
            .environment(\.nowPlayingService, service)
            .environment(\.mediaSourceAppOverride, sourceApp())
            .frame(width: MediaWidgetMetrics.width, height: MediaWidgetMetrics.height)
            .background(Color.black)
            .overlay {
                MediaWidgetSnapshotOverlay(showsScrubber: hovered)
            }

        let host = NSHostingView(rootView: widget)
        host.frame = NSRect(
            origin: .zero,
            size: NSSize(width: MediaWidgetMetrics.width, height: MediaWidgetMetrics.height)
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
        return png
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
        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }
}

private struct MediaWidgetSnapshotOverlay: View {
    let showsScrubber: Bool

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

            outline(MediaWidgetMetrics.artworkFrame, in: &context, color: Color(red: 1, green: 0, blue: 1))
            outline(MediaWidgetMetrics.textColumnFrame, in: &context, color: Color(red: 0, green: 1, blue: 1))
            outline(MediaWidgetMetrics.titleFrame, in: &context, color: .green)
            outline(MediaWidgetMetrics.albumFrame, in: &context, color: .green)
            outline(MediaWidgetMetrics.artistFrame, in: &context, color: .green)
            outline(MediaWidgetMetrics.controlsFrame, in: &context, color: .yellow)
            for frame in MediaWidgetMetrics.controlFrames {
                outline(frame, in: &context, color: .orange)
            }
            if showsScrubber {
                outline(MediaWidgetMetrics.scrubberTrackFrame, in: &context, color: .red)
                outline(MediaWidgetMetrics.scrubberHitFrame, in: &context, color: .red.opacity(0.6))
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
