import AppKit
import SwiftUI

struct EqualizerView: View {
    let isPlaying: Bool
    let height: CGFloat

    var body: some View {
        EqualizerBars(isPlaying: isPlaying).frame(width: 18, height: height)
        .frame(width: 22, height: height)
    }
}

struct EqualizerBars: NSViewRepresentable {
    var isPlaying: Bool
    func makeNSView(context: Context) -> EqualizerLayerView {
        let v = EqualizerLayerView()
        v.update(isPlaying: isPlaying)
        return v
    }
    func updateNSView(_ v: EqualizerLayerView, context: Context) { v.update(isPlaying: isPlaying) }
}

final class EqualizerLayerView: NSView {
    private let bars: [CALayer] = (0..<4).map { _ in CALayer() }
    private var playing = false
    private let barWidth: CGFloat = 3
    private let gap: CGFloat = 2
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        for b in bars {
            b.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
            b.cornerRadius = 1.5
            b.anchorPoint = CGPoint(x: 0.5, y: 0)
            layer?.addSublayer(b)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
    override func layout() {
        super.layout()
        let h = max(bounds.height, 1)
        for (i, b) in bars.enumerated() {
            b.bounds = CGRect(x: 0, y: 0, width: barWidth, height: h)
            b.position = CGPoint(x: CGFloat(i) * (barWidth + gap) + barWidth / 2, y: 0)
        }
        apply()
    }
    func update(isPlaying: Bool) {
        guard isPlaying != playing else { return }
        playing = isPlaying
        apply()
    }
    private func apply() {
        let durations: [Double] = [0.42, 0.58, 0.50, 0.66]
        for (i, b) in bars.enumerated() {
            b.removeAllAnimations()
            if playing {
                let a = CABasicAnimation(keyPath: "transform.scale.y")
                a.fromValue = 0.25
                a.toValue = 1.0
                a.duration = durations[i]
                a.autoreverses = true
                a.repeatCount = .infinity
                a.timeOffset = Double(i) * 0.13
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                b.add(a, forKey: "eq")
            } else {
                b.transform = CATransform3DMakeScale(1, 0.25, 1)
            }
        }
    }
}
