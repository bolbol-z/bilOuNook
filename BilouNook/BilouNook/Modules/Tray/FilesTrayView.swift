import AppKit
import SwiftUI

/// Memoizes file-type icons keyed by canonical URL; cleared on remove/clear.
private enum FileIconCache {
    private static var icons: [URL: NSImage] = [:]

    static func icon(for url: URL) -> NSImage {
        let key = url.resolvingSymlinksInPath().standardizedFileURL
        if let cached = icons[key] { return cached }
        let image = NSWorkspace.shared.icon(forFile: key.path)
        icons[key] = image
        return image
    }

    static func remove(_ url: URL) {
        icons.removeValue(forKey: url.resolvingSymlinksInPath().standardizedFileURL)
    }

    static func removeAll() {
        icons.removeAll()
    }
}

/// Files tray + AirDrop, reproducing the reference layout:
/// an external design reference (not included in this repository).
///
/// The 420pt page keeps the existing expanded-view geometry. The dashed
/// left panel receives dropped files, the blue right panel is the share
/// button. Both panels are permanently mounted so a file drag over the
/// open notch always has a visible destination.
struct FilesTrayView: View {
    private let preferredWidth: CGFloat = 420
    private let panelHeight: CGFloat = 61
    private let trayWidth: CGFloat = 250
    private let cornerRadius: CGFloat = 16

    @State private var isTargeted = false
    @State private var hoverTray = false
    @State private var hoverShare = false
    @State private var dndHighlight = false
    @State private var dndPulse = false
    @State private var dndPulseTask: Task<Void, Never>?
    @State private var showIngestBar = false
    @State private var addedFiles: Int? = nil
    @State private var successVisible = false
    @State private var successTask: Task<Void, Never>?
    @State private var dropTick = 0
    @State private var airDropOff = false
    @State private var airDropOffTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let store = TrayStore.shared

    private var notchHeight: CGFloat {
        NotchGeometryCache.shared.current.geometry.notchRect.height
    }

    private var notchState: NotchState { NotchState.shared }

    var body: some View {
        HStack(spacing: 6) {
            trayPanel
                .layoutProbe("files.tray")
            airDropPanel
                .layoutProbe("files.airdrop")
        }
        .padding(.horizontal, 8)
        .frame(height: panelHeight)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, NookLayout.rowTop(notchHeight: notchHeight))
        .frame(maxHeight: .infinity, alignment: .top)
        .frame(width: preferredWidth, height: preferredHeight, alignment: .top)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .onChange(of: notchState.phase) { _, phase in
            if phase != .open {
                successTask?.cancel()
                dndPulseTask?.cancel()
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { dndHighlight = false; dndPulse = false }
            }
        }
        .onDisappear {
            successTask?.cancel()
            dndPulseTask?.cancel()
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { dndHighlight = false; dndPulse = false }
        }
        .onChange(of: isTargeted) { _, targeted in
            dndPulseTask?.cancel()
            if targeted {
                withAnimation(.easeOut(duration: 0.15)) { dndHighlight = true }
                guard !reduceMotion else { return }
                dndPulseTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) { dndPulse = true }
                }
            } else {
                withAnimation(.easeIn(duration: 0.12)) { dndHighlight = false; dndPulse = false }
            }
        }
        .animation(
            isTargeted
                ? (reduceMotion ? .easeInOut(duration: 0.15) : .easeOut(duration: 0.15))
                : .easeIn(duration: 0.12),
            value: isTargeted
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: hoverTray)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: hoverShare)
    }

    private var preferredHeight: CGFloat {
        NotchGeometryCache.shared.current.geometry.notchRect.height + 2 + NookLayout.rowHeight + NookLayout.bottomPadding
    }

    // MARK: - Tray panel

    private var trayPanel: some View {
        DropZoneChrome(highlight: dndHighlight, pulse: dndPulse) {
            ZStack(alignment: .topTrailing) {
            if let added = addedFiles {
                successContent(added: added)
            } else if store.items.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(dndHighlight ? Color(red: 0, green: 0.4784, blue: 1.0) : Color(red: 0.5569, green: 0.5569, blue: 0.5765))
                        .scaleEffect(reduceMotion ? 1.0 : (dndHighlight ? 1.08 : 1.0))
                        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .interpolatingSpring(mass: 1, stiffness: 220, damping: 23.73, initialVelocity: 0), value: dndHighlight)
                    Text(dndHighlight ? "Release to add" : "Drop files here")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(dndHighlight ? Color(red: 0, green: 0.4784, blue: 1.0) : Color(red: 0.5569, green: 0.5569, blue: 0.5765))
                        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .easeOut(duration: 0.15), value: dndHighlight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Image(systemName: "tray.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.7))
                        Text("Files Tray")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.8))
                        Text(caption)
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineLimit(1)
                    }
                    .frame(width: 52, alignment: .leading)
                    .padding(.leading, 10)

                    scrollContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 2)
                }
                .frame(height: panelHeight)
            }

            if store.count > 0, hoverTray {
                ClearTrayButton(action: clearTray)
                    .padding(.top, 5)
                    .padding(.trailing, 6)
                    .transition(.opacity)
            }
            }
        }
        .frame(width: trayWidth, height: panelHeight)
        .overlay(alignment: .bottom) {
            if showIngestBar { ingestBar }
        }
        .frame(width: trayWidth, height: panelHeight)
        .onHover { hoverTray = $0 }
        .animation(
            isTargeted
                ? (reduceMotion ? .easeInOut(duration: 0.15) : .easeOut(duration: 0.15))
                : .easeIn(duration: 0.12),
            value: isTargeted
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Files Tray, \(store.count) items")
        .accessibilityHint("Drop files here to add them")
        .modifier(DropBounce(trigger: dropTick, enabled: !reduceMotion))
    }

    private func successContent(added: Int) -> some View {
        VStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(red: 0.2039, green: 0.7804, blue: 0.3490))
                    .opacity(successVisible ? 1 : 0)
                    .scaleEffect(successVisible ? 1.0 : 0.8)
                    .animation(
                        reduceMotion ? .easeInOut(duration: 0.15) : .easeOut(duration: 0.2),
                        value: successVisible
                    )
                Text("Added \(added) file\(added == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .opacity(successVisible ? 1 : 0)
                    .animation(
                        reduceMotion ? .easeInOut(duration: 0.15) : .easeOut(duration: 0.2),
                        value: successVisible
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var ingestBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                Capsule()
                    .fill(Color(red: 0.2039, green: 0.7804, blue: 0.3490))
                    .frame(height: 3)
                    .frame(width: geometry.size.width * min(1, max(0, CGFloat(store.ingestDone) / CGFloat(max(store.ingestTotal, 1)))).finiteOrZero)
                    .animation(.linear(duration: 0.1), value: store.ingestDone)
            }
        }
    }

    private var caption: String {
        if store.count == 0 { return "Empty" }
        if store.selection.count > 0 { return "\(store.selection.count) selected" }
        return "\(store.count) item\(store.count == 1 ? "" : "s")"
    }

    @ViewBuilder
    private var scrollContent: some View {
        if store.items.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.3))
                Text("Drop files here")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .padding(.trailing, 10)
        } else if store.items.count > 4 {
            stackContent
        } else {
            chipsContent
        }
    }

    private var chipsContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(store.items) { item in
                    FileChip(item: item, isSelected: store.selection.contains(item.id)) {
                        toggleSelection(item)
                    } onRemove: {
                        removeItem(item)
                    }
                    .overlay(
                        TrayDragHandle(
                            urls: { dragURLs(for: item) },
                            onClick: { toggleSelection(item) },
                            onDragBegan: { NotchHold.shared.hold(seconds: 60) },
                            onDragEnded: { _ in NotchHold.shared.release() }
                        )
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 5+ files: a compact stacked preview with a badge carrying the true
    /// count, followed by every stored file in a horizontal scroll so no
    /// file is ever unreachable.
    private var stackContent: some View {
        HStack(spacing: 5) {
            StackedPreview(items: store.items)
                .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(store.count) files in tray")
            .accessibilityHint("Scroll to see every file")
            .overlay(
                TrayDragHandle(
                    urls: { store.effectiveSelection().map(\.url) },
                    onClick: { },
                    onDragBegan: { NotchHold.shared.hold(seconds: 60) },
                    onDragEnded: { _ in NotchHold.shared.release() }
                )
            )

            chipsContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let hasFile = providers.contains { provider in
            provider.hasItemConformingToTypeIdentifier("public.file-url")
        }
        guard hasFile else { return false }

        store.beginIngest(count: providers.count)
        var collected: [URL] = []
        let group = DispatchGroup()
        for provider in providers where provider.hasItemConformingToTypeIdentifier("public.file-url") {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
                defer { group.leave() }
                if let url = item as? URL { collected.append(url) }
                else if let data = item as? Data,
                        let url = URL(dataRepresentation: data, relativeTo: nil) {
                    collected.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            MainActor.assumeIsolated {
                let added = (try? store.add(urls: collected)) ?? 0
                store.completeIngestItem()
                FileDropMonitor.shared.reset()
                if added > 0 {
                    isTargeted = false
                    dropTick += 1
                    startDropSuccess(added: added)
                }
            }
        }
        return true
    }

    private func toggleSelection(_ item: TrayStore.TrayItem) {
        store.toggleSelection(item.id)
    }

    private func dragURLs(for item: TrayStore.TrayItem) -> [URL] {
        if store.selection.contains(item.id) { return store.effectiveSelection().map(\.url) }
        return [item.url]
    }

    private func removeItem(_ item: TrayStore.TrayItem) {
        try? store.remove(id: item.id)
        FileIconCache.remove(item.url)
    }

    private func clearTray() {
        try? store.clear()
        FileIconCache.removeAll()
    }

    // MARK: - AirDrop panel

    private var airDropPanel: some View {
        Button(action: presentShare) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(red: 0, green: 0.4784, blue: 1.0).opacity(0.12))
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        hoverShare
                            ? Color(red: 0, green: 0.4784, blue: 0.6)
                            : Color(red: 0, green: 0.4784, blue: 0.35),
                        lineWidth: 1
                    )

                VStack(spacing: 4) {
                    AirDropGlyph(color: Color(red: 0, green: 0.4784, blue: 1.0)).frame(width: 24, height: 24)
                    Text("AirDrop")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                    Text(dropCaption)
                        .font(.system(size: 6.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .frame(width: 142, height: panelHeight)
        }
        .buttonStyle(.plain)
        .frame(width: 142, height: panelHeight)
        .onHover { hoverShare = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: hoverShare)
        .scaleEffect(reduceMotion ? 1.0 : (hoverShare ? 0.97 : 1.0))
        .animation(reduceMotion ? nil : InteractionMotion.controlPress, value: hoverShare)
        .disabled(store.items.isEmpty)
        .opacity(store.items.isEmpty ? 0.45 : 1)
        .accessibilityLabel(store.items.isEmpty ? "AirDrop sharing" : "Share \(max(store.selection.count, 1)) files via AirDrop")
        .accessibilityHint("Sends the selected files via AirDrop")
    }

    private var dropCaption: String {
        if airDropOff { return "AirDrop is off" }
        if store.items.isEmpty { return "Add files first" }
        if store.selection.isEmpty { return "All files" }
        return "\(store.selection.count) selected"
    }

    private func presentShare() {
        let urls = store.effectiveSelection().map(\.url)
        if TrayAirDropPresenter.shared.send(urls) { return }
        airDropOff = true
        cancelAirDropOffTask()
        airDropOffTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            airDropOff = false
        }
    }

    // MARK: - Drag and drop animations

    private func cancelSuccessTask() {
        successTask?.cancel()
        successTask = nil
    }

    private func cancelAirDropOffTask() {
        airDropOffTask?.cancel()
        airDropOffTask = nil
    }

    private func startDropSuccess(added: Int) {
        successTask?.cancel()
        addedFiles = added
        successVisible = false
        successTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .easeOut(duration: 0.20)) { successVisible = true }
            try? await Task.sleep(nanoseconds: 1_350_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) { successVisible = false }
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            addedFiles = nil
        }
    }
}

// MARK: - Cells and subviews

private struct FileChip: View {
    let item: TrayStore.TrayItem
    let isSelected: Bool
    let onToggle: () -> Void
    let onRemove: () -> Void

    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onToggle) {
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.92))
                        .frame(width: 33, height: 33)
                        .overlay {
                            Image(nsImage: FileIconCache.icon(for: item.url))
                                .resizable()
                                .scaledToFit()
                                .padding(3)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color(nsColor: .systemBlue) : Color.clear, lineWidth: 1.5)
                        )
                    Text(item.displayName)
                        .font(.system(size: 6.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 46)
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 3)
                .background(isSelected ? Color(nsColor: .systemBlue).opacity(0.13) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.displayName), file")
            .accessibilityHint(isSelected ? "Deselect" : "Select for sharing")

            if hovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white, Color.black.opacity(0.75))
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
                .accessibilityLabel("Remove \(item.displayName)")
            }
        }
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: hovered)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: isSelected)
    }
}

private struct StackedPreview: View {
    let items: [TrayStore.TrayItem]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                stackIcon(offset: 7, systemImage: "doc.fill")
                stackIcon(offset: 0, systemImage: "doc.fill")
                stackIcon(offset: -7, systemImage: "doc.on.doc.fill")
            }
            Badge(text: "\(items.count)")
                .offset(x: 3, y: -3)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(items.count) files")
    }

    private func stackIcon(offset: CGFloat, systemImage: String) -> some View {
        let view = RoundedRectangle(cornerRadius: 4)
            .fill(Color.white.opacity(offset == 0 ? 0.95 : 0.75))
            .frame(width: 24, height: 30)
            .shadow(color: .black.opacity(0.4), radius: 1.5, y: 0.5)
            .overlay {
                Image(systemName: systemImage)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color(red: 0.19, green: 0.51, blue: 0.83))
                    .padding(6)
            }
            .offset(x: offset, y: offset / 2)
        return view
    }
}

private struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Color(red: 0.047, green: 0.518, blue: 1.0))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }
}

private struct ClearTrayButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.2706, blue: 0.2275))
                .padding(5)
                .background(Color.black.opacity(0.55))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel("Clear tray")
        .accessibilityHint("Removes every file from the tray")
        .help("Clear tray")
    }
}


struct AirDropGlyph: View {
    var color: Color
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let lw = s * 0.09
            ZStack {
                Circle().fill(color).frame(width: s * 0.22, height: s * 0.22)
                Circle().trim(from: 0.125, to: 0.875)
                    .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                    .frame(width: s * 0.54, height: s * 0.54)
                    .rotationEffect(.degrees(90))
                Circle().trim(from: 0.125, to: 0.875)
                    .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                    .frame(width: s - lw, height: s - lw)
                    .rotationEffect(.degrees(90))
            }
            .frame(width: s, height: s)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

private struct DropBounce: ViewModifier {
    let trigger: Int
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.keyframeAnimator(initialValue: CGFloat(1.0), trigger: trigger) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack(\.self) {
                    CubicKeyframe(0.95, duration: 0.10)
                    CubicKeyframe(1.02, duration: 0.14)
                    CubicKeyframe(1.0, duration: 0.11)
                }
            }
        } else {
            content
        }
    }
}

struct DropZoneChrome<Content: View>: View {
    var highlight: Bool
    var pulse: Bool
    var content: () -> Content
    private let blue = Color(red: 0, green: 0.4784, blue: 1.0)
    private let idleBorder = Color(red: 0.2275, green: 0.2275, blue: 0.2353)
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        content()
            .background(
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                    .overlay(shape.fill(blue.opacity(highlight ? 0.08 : 0)))
            )
            .overlay(shape.strokeBorder(highlight ? blue : idleBorder, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .shadow(color: blue.opacity(highlight ? (pulse ? 0.30 : 0.10) : 0), radius: 12)
    }
}



struct TrayDragHandle: NSViewRepresentable {
    var urls: () -> [URL]
    var onClick: () -> Void
    var onDragBegan: () -> Void
    var onDragEnded: (NSDragOperation) -> Void

    func makeNSView(context: Context) -> DragHandleView {
        let v = DragHandleView()
        v.configure(urls: urls, onClick: onClick, onDragBegan: onDragBegan, onDragEnded: onDragEnded)
        return v
    }
    func updateNSView(_ v: DragHandleView, context: Context) {
        v.configure(urls: urls, onClick: onClick, onDragBegan: onDragBegan, onDragEnded: onDragEnded)
    }
}

final class DragHandleView: NSView, NSDraggingSource {
    private var urlsProvider: () -> [URL] = { [] }
    private var clickAction: () -> Void = {}
    private var beganAction: () -> Void = {}
    private var endedAction: (NSDragOperation) -> Void = { _ in }
    private var downPoint: NSPoint?
    private var dragStarted = false

    func configure(urls: @escaping () -> [URL], onClick: @escaping () -> Void,
                   onDragBegan: @escaping () -> Void, onDragEnded: @escaping (NSDragOperation) -> Void) {
        urlsProvider = urls; clickAction = onClick; beganAction = onDragBegan; endedAction = onDragEnded
    }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downPoint = convert(event.locationInWindow, from: nil)
        dragStarted = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard !dragStarted, let down = downPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard hypot(p.x - down.x, p.y - down.y) >= 4 else { return }
        dragStarted = true
        beginDrag(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        if !dragStarted { clickAction() }
        downPoint = nil
        dragStarted = false
    }

    private func beginDrag(with event: NSEvent) {
        let urls = urlsProvider()
        guard !urls.isEmpty else { return }
        beganAction()
        let items: [NSDraggingItem] = urls.enumerated().map { i, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let img = DragImage.make(icon: NSWorkspace.shared.icon(forFile: url.path), name: url.lastPathComponent)
            let o = CGFloat(min(i, 3)) * 6
            item.setDraggingFrame(NSRect(x: bounds.midX - img.size.width / 2 + o, y: bounds.midY - img.size.height / 2 - o, width: img.size.width, height: img.size.height), contents: img)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        endedAction(operation)
    }
}

enum DragImage {
    static func make(icon: NSImage, name: String) -> NSImage {
        let text = NSAttributedString(string: name, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white])
        let textW = min(ceil(text.size().width), 120)
        let size = NSSize(width: 8 + 28 + 6 + textW + 12 + 40, height: 36 + 40)
        return NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.rotate(by: -3 * .pi / 180)
            ctx.translateBy(x: -rect.midX, y: -rect.midY)
            let card = NSRect(x: 20, y: 20, width: rect.width - 40, height: 36)
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
            shadow.shadowBlurRadius = 15
            shadow.shadowOffset = NSSize(width: 0, height: -10)
            shadow.set()
            NSColor(calibratedRed: 0.1098, green: 0.1098, blue: 0.1176, alpha: 0.8).setFill()
            NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10).fill()
            icon.draw(in: NSRect(x: card.minX + 8, y: card.minY + 4, width: 28, height: 28))
            text.draw(with: NSRect(x: card.minX + 8 + 28 + 6, y: card.minY + 10, width: textW, height: 16), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            ctx.restoreGState()
            return true
        }
    }
}
