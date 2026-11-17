#if DEBUG
import Foundation
import QuartzCore

enum MotionTraceDirection: String {
    case open
    case close
}

struct MotionShapeSample {
    let time: CFTimeInterval
    let width: CGFloat
    let height: CGFloat
    var mainThreadSeconds: Double
}

struct MotionContentSample {
    let time: CFTimeInterval
    let progress: Double
    let tabs: Double
    let media: Double
    let calendar: Double
    var mainThreadSeconds: Double
}

struct MotionTrace {
    let cycle: Int
    let direction: MotionTraceDirection
    var pointerTime: CFTimeInterval?
    var shapes: [MotionShapeSample] = []
    var contents: [MotionContentSample] = []
}

final class MotionRecorder {
    static let shared = MotionRecorder()

    private var current: MotionTrace?
    private(set) var isMeasuring = false

    func setMeasuring(_ measuring: Bool) {
        isMeasuring = measuring
    }

    func begin(cycle: Int, direction: MotionTraceDirection) {
        current = MotionTrace(cycle: cycle, direction: direction)
    }

    func end() -> MotionTrace? {
        let trace = current
        current = nil
        return trace
    }

    func recordPointer(at time: CFTimeInterval) {
        guard current?.pointerTime == nil else { return }
        current?.pointerTime = time
    }

    func recordShape(width: CGFloat, height: CGFloat, mainThreadSeconds: Double) {
        guard var trace = current else { return }
        trace.shapes.append(
            MotionShapeSample(
                time: CACurrentMediaTime(),
                width: width,
                height: height,
                mainThreadSeconds: mainThreadSeconds
            )
        )
        current = trace
    }

    func recordShapeMainThread(_ seconds: Double) {
        guard var trace = current, !trace.shapes.isEmpty else { return }
        trace.shapes[trace.shapes.count - 1].mainThreadSeconds += seconds
        current = trace
    }

    func recordContent(
        progress: Double,
        tabs: Double,
        media: Double,
        calendar: Double,
        mainThreadSeconds: Double = 0
    ) {
        guard var trace = current else { return }
        trace.contents.append(
            MotionContentSample(
                time: CACurrentMediaTime(),
                progress: progress,
                tabs: tabs,
                media: media,
                calendar: calendar,
                mainThreadSeconds: mainThreadSeconds
            )
        )
        current = trace
    }
}
#endif
