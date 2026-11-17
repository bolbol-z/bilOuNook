import XCTest

@MainActor
final class TrayStoreTests: XCTestCase {
    private var store: TrayStore!
    private var workingDir: URL!

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrayStoreTests-\(UUID().uuidString)")
        workingDir = root.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDir, withIntermediateDirectories: true)
        store = TrayStore()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workingDir.deletingLastPathComponent())
        store = nil
        workingDir = nil
    }

    // MARK: - Ingestion

    func testAddExistingFilesCreatesTrayItems() throws {
        let files = try createFiles(names: ["one.txt", "two.png", "three.csv"])

        let added = try store.add(urls: files)

        XCTAssertEqual(added, 3)
        XCTAssertEqual(store.items.map(\.displayName), ["one.txt", "two.png", "three.csv"])
        XCTAssertTrue(store.items.allSatisfy { !$0.isDirectory })
        XCTAssertEqual(store.rejectedCount, 0)
    }

    func testAddMoreThanFourItemsIsNotLimited() throws {
        let names = (1...10).map { "file-\($0).txt" }
        let files = try createFiles(names: names)

        let added = try store.add(urls: files)

        XCTAssertEqual(added, 10)
        XCTAssertEqual(store.items.count, 10)
        // The badge must always reflect reality.
        XCTAssertEqual(store.badgeCount, store.items.count)
    }

    func testMissingFileIsRejectedAndRestArrive() throws {
        let files = try createFiles(names: ["present.txt"])
        let missing = workingDir.appendingPathComponent("missing.txt")

        let added = try store.add(urls: [files[0], missing])

        XCTAssertEqual(added, 1)
        XCTAssertEqual(store.items.map(\.displayName), ["present.txt"])
        XCTAssertEqual(store.rejectedCount, 1)
    }

    func testDirectoriesAreAccepted() throws {
        let folder = workingDir.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let added = try store.add(urls: [folder])

        XCTAssertEqual(added, 1)
        XCTAssertEqual(store.items.first?.isDirectory, true)
    }

    func testDuplicateUrlsAreNotAddedTwice() throws {
        let file = try createFiles(names: ["same.txt"])[0]

        let first = try store.add(urls: [file, file])
        let second = try store.add(urls: [file])

        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 0)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.badgeCount, 1)
    }

    @MainActor func testIngestProgressBeginAndComplete() {
        let s = TrayStore()
        s.beginIngest(count: 3)
        XCTAssertEqual(s.ingestTotal, 3); XCTAssertEqual(s.ingestDone, 0)
        s.completeIngestItem(); s.completeIngestItem()
        XCTAssertEqual(s.ingestTotal, 3); XCTAssertEqual(s.ingestDone, 2)
        s.completeIngestItem()
        XCTAssertEqual(s.ingestTotal, 0); XCTAssertEqual(s.ingestDone, 0)
    }

    @MainActor func testAddDoesNotTouchIngestCounters() throws {
        let s = TrayStore()
        s.beginIngest(count: 1)
        let file = try createFiles(names: ["one.txt"])[0]
        _ = try s.add(urls: [file])
        XCTAssertEqual(s.ingestTotal, 1)
        XCTAssertEqual(s.ingestDone, 0)
    }

    // MARK: - Selection and removal

    func testToggleSelection() throws {
        let files = try createFiles(names: ["one.txt", "two.txt"])
        try store.add(urls: files)
        let first = try XCTUnwrap(store.items.first)

        store.toggleSelection(first.id)
        XCTAssertTrue(store.selection.contains(first.id))
        store.toggleSelection(first.id)
        XCTAssertFalse(store.selection.contains(first.id))
    }

    func testRemoveDropsSelectionAndCount() throws {
        let files = try createFiles(names: ["one.txt", "two.txt"])
        try store.add(urls: files)
        let ids = store.items.map(\.id)
        store.toggleSelection(ids[0])

        try store.remove(id: ids[0])

        XCTAssertEqual(store.items.count, 1)
        XCTAssertFalse(store.selection.contains(ids[0]))
        XCTAssertEqual(store.badgeCount, 1)
    }

    func testClearRemovesEverythingFirstSelectionsToo() throws {
        let files = try createFiles(names: ["one.txt", "two.txt", "three.txt"])
        try store.add(urls: files)
        store.toggleSelection(store.items[0].id)
        store.toggleSelection(store.items[1].id)

        try store.clear()

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.selection.isEmpty)
        XCTAssertEqual(store.badgeCount, 0)
    }

    // MARK: - Security-scoped staging

    func testSecurityScopedSourceIsSharedByReference() throws {
        // The app is not sandboxed, so we reference the source in place and
        // simply keep the security scope held for the process lifetime.
        let source = try createFiles(names: ["safari-export.png"])[0]
        let staged = try store.stage(urls: [source])

        XCTAssertEqual(staged.count, 1)
        XCTAssertEqual(staged[0].url, source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged[0].url.path))

        try store.remove(id: staged[0].id)

        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "the original file must survive")
    }

    func testPlainFilesAreReferencedNotCopied() throws {
        // Ordinary files with no sandbox requirement are referenced in place.
        let source = try createFiles(names: ["desktop.txt"])[0]
        let staged = try store.stage(urls: [source])

        XCTAssertEqual(staged.count, 1)
        XCTAssertEqual(staged[0].url, source)

        try store.clear()
        // The original file must survive.
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    // MARK: - Helpers

    private func createFiles(names: [String]) throws -> [URL] {
        try names.map { name in
            let url = workingDir.appendingPathComponent(name)
            try "fixture".data(using: .utf8)!.write(to: url, options: .atomic)
            return url
        }
    }
}
