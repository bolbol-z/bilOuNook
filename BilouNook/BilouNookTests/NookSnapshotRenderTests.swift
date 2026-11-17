import AppKit
import SwiftUI
import XCTest

#if DEBUG
@MainActor
final class NookSnapshotRenderTests: XCTestCase {
    private let panelSize = NSSize(width: 600, height: 240)
    private let pageSize = CGSize(width: 420, height: 118)

    func testTopBandFramesMatchSpecAtMinimumWidth() {
        let geometry = NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            backingScaleFactor: 2,
            auxLeft: CGRect(x: 0, y: 924, width: 646, height: 32),
            auxRight: CGRect(x: 825, y: 924, width: 645, height: 32),
            safeAreaTop: 32
        )
        let layout = ModuleTabLayout(
            pillWidths: [TabPillMetrics.width(title: "Nook")],
            shapeWidth: 300,
            geometry: geometry
        )

        XCTAssertTrue(layout.usesIconFallback)
        XCTAssertEqual(layout.pillFrames, [CGRect(x: 9, y: 6, width: 20, height: 20)])
        XCTAssertEqual(layout.gearFrame, CGRect(x: 268, y: 6, width: 20, height: 20))
    }

    func testRenderNookShellPhysicalAndNoNotch() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("build/screens")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for scenario in ["physical-notch", "no-notch"] {
            let data = try render(showHardwareNotch: scenario == "physical-notch")
            let url = output.appendingPathComponent("nook-shell-\(scenario).png")
            try data.write(to: url)
            XCTAssertGreaterThan(data.count, 4_000, url.lastPathComponent)
            print("[NOOK SHELL] \(url.path)")
        }
    }

    private func render(showHardwareNotch: Bool) throws -> Data {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false

        let registry = ModuleRegistry(modules: [NookModule()])
        let root = NotchRootView(
            panel: panel,
            previewMetrics: NotchMetrics(w: pageSize.width, h: pageSize.height, t: 6, b: 20),
            previewShowContent: true,
            registry: registry
        )
        .frame(width: panelSize.width, height: panelSize.height)
        .overlay {
            NookSnapshotOverlay(showHardwareNotch: showHardwareNotch)
        }

        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: panelSize)
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
}

private struct NookSnapshotOverlay: View {
    let showHardwareNotch: Bool

    var body: some View {
        Canvas { context, size in
            var grid = Path()
            for x in stride(from: 0, through: size.width, by: 10) {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0, through: size.height, by: 10) {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(.white.opacity(0.10)), lineWidth: 0.5)

            if showHardwareNotch {
                let frame = CGRect(x: (size.width - 179) / 2, y: 0, width: 179, height: 32)
                let notch = Path(frame)
                context.fill(notch, with: .color(Color(red: 1, green: 0, blue: 1).opacity(0.35)))
                context.stroke(notch, with: .color(Color(red: 1, green: 0, blue: 1).opacity(0.9)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

private enum SnapshotError: Error {
    case renderFailed
    case encodingFailed
}
#endif
