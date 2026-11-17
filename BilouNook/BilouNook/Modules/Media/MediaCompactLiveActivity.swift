import AppKit
import SwiftUI

struct MediaCompactLiveActivity: View {
    @State private var service = NowPlayingService.shared
    @StateObject private var settings = SettingsStore.shared

    var body: some View {
        if settings.mediaCompactEnabled, service.liveActivityState.isPlaying {
            MediaCompactContent(state: service.liveActivityState)
                .equatable()
        }
    }
}

private struct MediaCompactContent: View, Equatable {
    let state: NowPlayingLiveActivityState

    var body: some View {
        GeometryReader { geometry in
            let availableHeight = max(1, geometry.size.height)
            let artworkSize = min(20, max(4, availableHeight - 6))
            let equalizerHeight = min(14, max(2, availableHeight - 8))

            HStack(spacing: 8) {
                ArtworkCrossfade(identity: state.artworkIdentity) {
                    ArtworkThumbnailView(
                        artwork: state.artwork,
                        identity: state.artworkIdentity,
                        displaySize: artworkSize,
                        cornerRadius: min(4, artworkSize / 4)
                    )
                }
                .layoutProbe("island.media.artwork")
                Spacer(minLength: 0)
                EqualizerView(isPlaying: state.isPlaying, height: equalizerHeight)
                    .layoutProbe("island.media.equalizer")
            }
            .padding(.horizontal, 12)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black)
        }
    }
}

struct IslandArtwork: View {
    let size: CGFloat
    @State private var image: NSImage?
    var body: some View {
        let snap: NowPlayingSnapshot? = NowPlayingService.shared.snapshot
        let identity = (snap?.trackIdentity ?? "") + "#\(snap?.artwork?.count ?? 0)"
        ZStack {
            if let image { Image(nsImage: image).resizable().scaledToFill() } else { Color.white.opacity(0.12) }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .task(id: identity) {
            let data = snap?.artwork
            let px = size * 3
            image = await Task.detached(priority: .userInitiated) { IslandArtwork.thumbnail(data, max: px) }.value
        }
    }
    nonisolated static func thumbnail(_ data: Data?, max: CGFloat) -> NSImage? {
        guard let data, let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(max)]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

struct TimerRing: View {
    var size: CGFloat = 16
    var body: some View {
        let t = TimerService.shared
        let accent = TimerPalette.accent(for: t)
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 2)
            Circle().trim(from: 0, to: CGFloat(max(0, min(1, 1 - t.progress))).finiteOrZero)
                .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

struct TimerWing: View {
    var body: some View {
        let t = TimerService.shared
        let accent = TimerPalette.accent(for: t)
        let urgent = t.state == .finished || (t.mode == .timer && t.state == .running && t.displaySeconds < 10)
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !urgent)) { ctx in
            let k = 0.5 * (sin(2 * Double.pi * ctx.date.timeIntervalSinceReferenceDate / 1.5) + 1)
            Text(TimerFormat.island(t.displaySeconds))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(t.state == .finished ? TimerPalette.red : Color.white)
                .opacity(t.state == .paused ? 0.55 : 1)
                .padding(.horizontal, 3)
                .frame(height: 16)
                .background(Capsule().fill(TimerPalette.red.opacity(urgent ? 0.06 + 0.16 * k : 0)))
                .overlay(alignment: .bottom) {
                    Capsule().fill(accent)
                        .frame(width: (24 * CGFloat(max(0, min(1, 1 - t.progress)))).finiteOrZero, height: 1.5)
                        .offset(y: 3)
                }
                .layoutProbe("island.timerText")
        }
    }
}

struct AirDropWing: View {
    var body: some View {
        let phase = AirDropTransfer.shared.phase
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: phase != .sending)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            VStack(spacing: 3) {
                Group {
                    switch phase {
                    case .sent:
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(TimerPalette.green)
                    case .failed:
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(TimerPalette.red)
                    default:
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle().fill(Color.white).frame(width: 3, height: 3)
                                    .opacity(0.35 + 0.65 * 0.5 * (sin(2 * Double.pi * (t / 1.2 - Double(i) * 0.16)) + 1))
                            }
                        }
                    }
                }
                .frame(height: 10)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    GeometryReader { geo in
                        let w = max(0, geo.size.width)
                        if phase == .sending {
                            let seg = w * 0.4
                            Capsule().fill(TimerPalette.blue).frame(width: seg)
                                .offset(x: (((t / 1.2).truncatingRemainder(dividingBy: 1)) * (w + seg) - seg).finiteOrZero)
                        } else {
                            Capsule().fill(phase == .failed ? TimerPalette.red : TimerPalette.blue).frame(width: w)
                        }
                    }
                }
                .frame(width: 24, height: 2)
                .clipShape(Capsule())
            }
        }
        .layoutProbe("island.airdrop")
    }
}

struct IslandLeftWing: View {
    let mode: IslandMode
    var body: some View {
        Group {
            switch mode {
            case .split: IslandArtwork(size: 20).layoutProbe("island.artwork")
            case .timer: TimerRing(size: 16).layoutProbe("island.ring")
            case .airdrop: AirDropGlyph(color: TimerPalette.blue).frame(width: 15, height: 15).layoutProbe("island.airdrop")
            case .storage: Image(systemName: "doc.fill").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.9))
            default: EmptyView()
            }
        }
        .padding(.leading, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .offset(y: -4)))
    }
}

struct IslandRightWing: View {
    let mode: IslandMode
    var body: some View {
        Group {
            switch mode {
            case .split, .timer: TimerWing()
            case .airdrop: AirDropWing()
            case .storage:
                Text("\(TrayStore.shared.items.count)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.white)
            default: EmptyView()
            }
        }
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -4)),
                                removal: .opacity.combined(with: .offset(x: 20))))
    }
}

struct IslandView: View {
    var body: some View {
        let mode = IslandModel.shared.mode
        Group {
            switch mode {
            case .none:
                Color.clear
            case .media:
                MediaCompactLiveActivity().layoutProbe("island.mediaPill")
            default:
                HStack(spacing: 0) {
                    IslandLeftWing(mode: mode)
                        .frame(width: 36)
                        .layoutProbe("island.left")
                    Spacer(minLength: 0)
                    IslandRightWing(mode: mode)
                        .frame(width: 36)
                        .layoutProbe("island.right")
                }
            }
        }
        .animation(Animations.islandContent, value: mode)
        .layoutProbe("island.root")
    }
}
