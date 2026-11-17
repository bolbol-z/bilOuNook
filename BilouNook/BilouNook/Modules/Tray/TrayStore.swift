import Foundation

@MainActor
@Observable
final class TrayStore {
    struct TrayItem: Identifiable, Equatable {
        let id: UUID
        let url: URL
        let displayName: String
        let isDirectory: Bool

        var shareItems: [URL] { [url] }
    }

    static let shared = TrayStore()

    private(set) var items: [TrayItem] = []
    private(set) var selection: Set<UUID> = []
    private(set) var rejectedCount: Int = 0
    private(set) var isAdding = false
    private(set) var ingestTotal: Int = 0
    private(set) var ingestDone: Int = 0

    var count: Int { items.count }
    var badgeCount: Int { items.count }

    func add(urls: [URL]) throws -> Int {
        let staged = try stage(urls: unique(urls))
        items.append(contentsOf: staged)
        return staged.count
    }

    func beginIngest(count: Int) { ingestTotal += count }
    func completeIngestItem() {
        ingestDone += 1
        if ingestDone >= ingestTotal { ingestTotal = 0; ingestDone = 0 }
    }

    /// Filters out anything already in the tray.
    private func unique(_ urls: [URL]) -> [URL] {
        let known = Set(items.map { $0.url.resolvingSymlinksInPath().standardizedFileURL })
        var seen = known
        return urls.compactMap { url in
            let canonical = url.resolvingSymlinksInPath().standardizedFileURL
            guard seen.insert(canonical).inserted else { return nil }
            return url
        }
    }

    /// Validates each URL and takes a security scope on it. No bytes are
    /// copied: the app is not sandboxed and can field these URLs for AirDrop
    /// for the lifetime of the process.
    func stage(urls: [URL]) throws -> [TrayItem] {
        var staged: [TrayItem] = []
        var rejected = 0
        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else {
                rejected += 1
                continue
            }
            // Balanced in `discard`. Plain references stay valid for the
            // process lifetime because the app is not sandboxed.
            _ = url.startAccessingSecurityScopedResource()
            staged.append(TrayItem(
                id: UUID(),
                url: url,
                displayName: url.lastPathComponent,
                isDirectory: isDirectory(url)
            ))
        }
        rejectedCount += rejected
        return staged
    }

    func remove(id: UUID) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        selection.remove(id)
        discard(item)
    }

    func clear() throws {
        for item in items { discard(item) }
        items = []
        selection = []
        ingestTotal = 0
        ingestDone = 0
    }

    func toggleSelection(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func effectiveSelection() -> [TrayItem] {
        let selected = items.filter { selection.contains($0.id) }
        return selected.isEmpty ? items : selected
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }

    /// Security scopes are process-wide, so a plain reference keeps working
    /// for our lifetime; we release it when the user removes the file.
    private func discard(_ item: TrayItem) {
        item.url.stopAccessingSecurityScopedResource()
    }
}
