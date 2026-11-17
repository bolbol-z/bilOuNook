#if DEBUG
import AppKit

enum DebugTools {
    static func install(
        appDelegate: AppDelegate,
        panel: NSPanel,
        state: NotchState,
        mouseMonitor: MouseMonitor,
        gestureMonitor: GestureMonitor,
        watchdog: Watchdog
    ) {
        _ = appDelegate
        _ = panel
        _ = mouseMonitor
        _ = gestureMonitor
        _ = watchdog
        HotKeyManager.shared.register()
        AnimationLabWindow.shared.state = state
    }
}
#endif

#if DEBUG
enum LayoutDump {
    struct Rect: Codable { var x: Double; var y: Double; var w: Double; var h: Double }
    struct Frame: Codable {
        var name: String
        var rect: Rect
        var dxFromScreenCenter: Double
        var overlapWithHardwareNotchPct: Double
        var fullyHidden: Bool
    }
    struct Output: Codable {
        var timestamp: String
        var label: String
        var state: [String: String]
        var screen: [String: Double]
        var hardwareNotch: Rect?
        var panel: Rect?
        var frames: [Frame]
    }

    static func overlapPct(_ r: Rect, notch: Rect?) -> Double {
        guard let n = notch, r.w > 0, r.h > 0 else { return 0 }
        let ix = max(0, min(r.x + r.w, n.x + n.w) - max(r.x, n.x))
        let iy = max(0, min(r.y + r.h, n.y + n.h) - max(r.y, n.y))
        return (ix * iy) / (r.w * r.h) * 100
    }

    @MainActor private static var counter = 0
    @MainActor private static var lastSignature = ""

    @MainActor static func captureCurrent(force: Bool = true) {
        var s: [String: String] = [:]
        s["phase"] = "\(NotchState.shared.phase)"
        s["activeModule"] = "\(String(describing: ModuleRegistry.shared.activeModuleID))"
        s["islandMode"] = "\(IslandModel.shared.mode)"
        s["timerState"] = "\(TimerService.shared.state)"
        s["timerMode"] = TimerService.shared.mode.rawValue
        s["timerPhase"] = "\(TimerService.shared.phase)"
        s["airdrop"] = "\(AirDropTransfer.shared.phase)"
        s["trayCount"] = "\(TrayStore.shared.items.count)"
        s["mediaPlaying"] = "\(NowPlayingService.shared.liveActivityState.isPlaying)"
        s["reduceMotion"] = "\(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)"
        counter += 1
        capture(label: "cap\(counter)-\(s["phase"] ?? "")-\(s["islandMode"] ?? "")", state: s, force: force)
    }

    @MainActor static func capture(label: String, state: [String: String], force: Bool) {
        guard let panel = NSApp.windows.first(where: { $0 is NotchPanel }),
              let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let sf = screen.frame
        let scale = Double(screen.backingScaleFactor)
        let topInset = Double(screen.safeAreaInsets.top)
        var notch: Rect?
        var scr: [String: Double] = ["width": Double(sf.width), "height": Double(sf.height), "scale": scale, "safeTop": topInset]
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea, topInset > 0 {
            let nw = Double(sf.width - l.width - r.width)
            scr["auxLeftWidth"] = Double(l.width); scr["auxRightWidth"] = Double(r.width); scr["notchWidth"] = nw
            notch = Rect(x: Double(sf.width) / 2 - nw / 2, y: 0, w: nw, h: topInset)
        }
        let px = Double(panel.frame.minX - sf.minX)
        let py = Double(sf.maxY - panel.frame.maxY)
        let panelRect = Rect(x: px, y: py, w: Double(panel.frame.width), h: Double(panel.frame.height))
        let probes = LayoutProbeStore.shared.all()
        let frames: [Frame] = probes.keys.sorted().compactMap { name in
            guard let g = probes[name], g.width.isFinite, g.height.isFinite else { return nil }
            let r = Rect(x: px + Double(g.minX), y: py + Double(g.minY), w: Double(g.width), h: Double(g.height))
            let pct = overlapPct(r, notch: notch)
            return Frame(name: name, rect: r, dxFromScreenCenter: r.x + r.w / 2 - Double(sf.width) / 2,
                         overlapWithHardwareNotchPct: pct, fullyHidden: pct >= 99.5)
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let signature = String(describing: [state.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }, frames.map { "\($0.name):\(Int($0.rect.x * 2)):\(Int($0.rect.y * 2)):\(Int($0.rect.w * 2)):\(Int($0.rect.h * 2))" }])
        if !force && signature == lastSignature { return }
        lastSignature = signature
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = df.string(from: Date())
        let out = Output(timestamp: stamp, label: label, state: state, screen: scr, hardwareNotch: notch, panel: panelRect, frames: frames)
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/BilouNook/analysis", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = "\(stamp)-\(label)"
        if let data = try? enc.encode(out) { try? data.write(to: dir.appendingPathComponent(base + ".json")) }
        guard let cv = panel.contentView, let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) else { return }
        cv.cacheDisplay(in: cv.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: dir.appendingPathComponent(base + "-raw.png")) }
        let size = cv.bounds.size
        let raw = NSImage(size: size); raw.addRepresentation(rep)
        let overlay = NSImage(size: size, flipped: false) { rect in
            NSColor(white: 0.45, alpha: 1).setFill(); rect.fill()
            raw.draw(in: rect)
            let H = rect.height
            if let n = notch {
                let r = NSRect(x: n.x - px, y: H - ((n.y - py) + n.h), width: n.w, height: n.h)
                NSColor.red.withAlphaComponent(0.35).setFill(); r.fill()
                NSColor.red.setStroke(); NSBezierPath(rect: r).stroke()
            }
            for (i, f) in frames.enumerated() {
                let r = NSRect(x: f.rect.x - px, y: H - ((f.rect.y - py) + f.rect.h), width: f.rect.w, height: f.rect.h)
                let c = NSColor(hue: CGFloat(i % 12) / 12, saturation: 0.9, brightness: 1, alpha: 1)
                c.setStroke(); let p = NSBezierPath(rect: r); p.lineWidth = 0.75; p.stroke()
                NSString(string: f.name).draw(at: NSPoint(x: r.minX + 1, y: r.maxY - 8),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 5), .foregroundColor: c])
            }
            return true
        }
        if let tiff = overlay.tiffRepresentation, let r2 = NSBitmapImageRep(data: tiff),
           let png = r2.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent(base + "-overlay.png"))
        }
    }
}
#endif
