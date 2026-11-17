import AppKit
import SwiftUI
import XCTest

@MainActor
final class FilesTraySnapshotTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var store: TrayStore!
    private var originalItems: [TrayStore.TrayItem] = []
    private var originalSelection: Set<UUID> = []

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FilesTraySnapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        store = TrayStore.shared
        originalItems = store.items
        originalSelection = store.selection
        try store.clear()
    }

    override func tearDownWithError() throws {
        try store.clear()
        try? FileManager.default.removeItem(at: temporaryDirectory)
        for item in originalItems {
            _ = try? store.add(urls: [item.url])
        }
        for id in originalSelection {
            store.toggleSelection(id)
        }
        temporaryDirectory = nil
    }

    func testRenderTrayAndAirDropEmpty() throws {
        let view = FilesTrayView()
        _ = try render("files-tray-empty", view: view)
    }

    func testRenderTrayAndAirDropWithTwoFiles() throws {
        let png = try createFile(named: "screenshot-2026.png")
        let zip = try createFile(named: "archive.zip")
        _ = try store.add(urls: [png, zip])

        let view = FilesTrayView()
        _ = try render("files-tray-two", view: view)
    }

    func testRenderTrayAndAirDropWithThreeItems() throws {
        let files = try [
            createFile(named: "report-2026.pdf"),
            createFile(named: "notes.md"),
            createFile(named: "receipt.jpg"),
        ]
        _ = try store.add(urls: files)

        let view = FilesTrayView()
        _ = try render("files-tray-three", view: view)
    }

    func testRenderTrayAndAirDropWithFiveItemsShowsStackedPreview() throws {
        let files = try [
            createFile(named: "one.txt"),
            createFile(named: "two.png"),
            createFile(named: "three.csv"),
            createFile(named: "four.pdf"),
            createFile(named: "five.key"),
        ]
        _ = try store.add(urls: files)

        let view = FilesTrayView()
        _ = try render("files-tray-five", view: view)
    }

    func testRenderTrayAndAirDropWithSixFilesSelected() throws {
        let files = try [
            createFile(named: "report-2026.pdf"),
            createFile(named: "notes.md"),
            createFile(named: "receipt.jpg"),
            createFile(named: "invoice.pdf"),
            createFile(named: "photo.png"),
            createFile(named: "deck.key"),
        ]
        _ = try store.add(urls: files)
        store.toggleSelection(store.items[1].id)
        store.toggleSelection(store.items[3].id)

        let view = FilesTrayView()
        _ = try render("files-tray-six-selected", view: view)
    }

    func testRenderFullNotchWithFilesTab() throws {
        _ = NSApplication.shared
        let png = try createFile(named: "invoice-2026.pdf")
        let zip = try createFile(named: "archive.zip")
        _ = try store.add(urls: [png, zip])

        let registry = ModuleRegistry(modules: [NookModule(), TrayModule()])
        registry.select(id: "files")

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 118),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false

        let root = NotchRootView(
            panel: panel,
            previewMetrics: NotchMetrics(w: 420, h: 118, t: 6, b: 20),
            previewShowContent: true,
            registry: registry
        )
        .frame(width: 420, height: 118)
        .overlay {
            SimpleSnapshotOverlay()
                .frame(width: 420, height: 118)
                .allowsHitTesting(false)
        }

        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 118)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw SnapshotError.renderFailed
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.encodingFailed
        }
        let output = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("build/screens")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let url = output.appendingPathComponent("files-tray-full-notch-files-tab.png")
        try png.write(to: url)
        print("[FILES TRAY] \(url.path)")
        XCTAssertGreaterThan(png.count, 2_000, url.lastPathComponent)
    }

    private func createFile(named name: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        try "fixture".data(using: .utf8)!.write(to: url)
        return url
    }

    private func render(_ name: String, view: some View) throws -> Data {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("build/screens/")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let geometry = NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            backingScaleFactor: 2,
            auxLeft: CGRect(x: 0, y: 924, width: 646, height: 32),
            auxRight: CGRect(x: 825, y: 924, width: 645, height: 32),
            safeAreaTop: 32
        )
        let preview = NotchMetrics(w: 420, h: notchHeight(for: geometry) + 86, t: 6, b: 20)

        let root = ZStack(alignment: .top) {
            NotchShape(width: 420, height: preview.h, topCornerRadius: 6, bottomCornerRadius: 20)
                .fill(Color.black)
            view
                .frame(width: 420, height: 75)
                .padding(.top, 34)
        }
        .frame(width: 420, height: preview.h)
        .overlay(
            SimpleSnapshotOverlay()
                .frame(width: 420, height: preview.h)
                .allowsHitTesting(false)
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: preview.h),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 420, height: preview.h)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw SnapshotError.renderFailed
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.encodingFailed
        }
        let url = output.appendingPathComponent("files-tray-\(name).png")
        try png.write(to: url)
        print("[FILES TRAY] \(url.path)")
        XCTAssertGreaterThan(png.count, 2_000, url.lastPathComponent)
        return png
    }

    private func notchHeight(for geometry: NotchGeometry) -> CGFloat {
        geometry.notchRect.height
    }

    @MainActor func testAirDropGlyphRendersBlue() {
        let r = ImageRenderer(content: AirDropGlyph(color: Color(red: 0, green: 0.4784, blue: 1.0)).frame(width: 24, height: 24))
        r.scale = 2
        guard let cg = r.cgImage else { return XCTFail("no image") }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: Int(w * h * 4))
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var blue = 0
        for i in stride(from: 0, to: px.count, by: 4) where px[i + 3] > 200 && px[i + 2] > 200 && px[i] < 60 { blue += 1 }
        XCTAssertGreaterThan(blue, 40)
    }

    func testDragImageRendersGhost() {
        let img = DragImage.make(icon: NSImage(size: NSSize(width: 16, height: 16)), name: "report-final-v2.pdf")
        XCTAssertGreaterThan(img.size.width, 80)
        XCTAssertEqual(img.size.height, 76)
    }
}

private enum SnapshotError: Error {
    case renderFailed
    case encodingFailed
}

private struct SimpleSnapshotOverlay: View {
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

            let notch = CGRect(x: (size.width - 179) / 2, y: 0, width: 179, height: 32)
            context.fill(Path(notch), with: .color(Color(red: 1, green: 0, blue: 1).opacity(0.35)))
            context.stroke(Path(notch), with: .color(Color(red: 1, green: 0, blue: 1).opacity(0.9)), lineWidth: 1)
        }
    }
}
