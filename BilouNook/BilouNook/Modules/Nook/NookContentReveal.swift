import SwiftUI

private struct NookRevealProgressKey: EnvironmentKey {
    static let defaultValue: Double = 1
}

private struct NookArtworkRevealScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var nookRevealProgress: Double {
        get { self[NookRevealProgressKey.self] }
        set { self[NookRevealProgressKey.self] = newValue }
    }

    var nookArtworkRevealScale: CGFloat {
        get { self[NookArtworkRevealScaleKey.self] }
        set { self[NookArtworkRevealScaleKey.self] = newValue }
    }
}

struct NookContentRevealHost<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double
    private let isOpen: Bool
    private let content: Content

    init(isOpen: Bool, @ViewBuilder content: () -> Content) {
        _progress = State(initialValue: isOpen ? 0 : 1)
        self.isOpen = isOpen
        self.content = content()
    }

    var body: some View {
        content
            .modifier(NookRevealProgressModifier(progress: progress))
            .onAppear {
                guard isOpen else { return }
                DispatchQueue.main.async {
                    reveal()
                }
            }
            .onChange(of: isOpen) { _, open in
                guard open else { return }
                reveal()
            }
    }

    private func reveal() {
        withAnimation(revealAnimation) {
            progress = 1
        }
    }

    private var revealAnimation: Animation {
        if reduceMotion {
            return .easeInOut(duration: Animations.reduceMotionDuration)
        }
        return Animations.animation(for: .openMetrics)
    }
}

private struct NookRevealProgressModifier: AnimatableModifier {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .environment(\.nookRevealProgress, progress)
            .blur(radius: Animations.contentBlurEnabled ? CGFloat(2 * (1 - progress)) : 0)
    }
}
