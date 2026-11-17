import SwiftUI

enum NotchMotionTransition: Equatable {
    case openMetrics
    case closeMetrics
    case contentShow
    case contentHide
    case liveActivity
    case moduleChange
    case moduleContent
}

enum NotchMotionPlan: Equatable {
    case spring(response: Double, dampingFraction: Double)
    case interpolatingSpring(mass: Double, stiffness: Double, damping: Double, initialVelocity: Double)
    case timingCurve(c1x: Double, c1y: Double, c2x: Double, c2y: Double, duration: Double)
    case easeIn(duration: Double)
    case easeInOut(duration: Double)
    case crossfade(duration: Double)
}

enum InteractionMotion {
    static let controlPress = Animations.scaled(.spring(response: 0.18, dampingFraction: 0.8))
    static let hoverBrighten: Double = 0.12
    static let scrubberFade = Animations.scaled(.easeOut(duration: 0.15))
    static let artworkPause = Animations.scaled(.spring(response: 0.3, dampingFraction: 0.85))
    static let trackChange = Animations.scaled(.easeInOut(duration: 0.2))
    static let calendarDayHighlight = Animations.scaled(.spring(response: 0.3, dampingFraction: 0.75))
    static let calendarStripScrollResponse: Double = 0.28
    static let calendarStripScrollDampingFraction: Double = 0.9
    static let calendarStripScroll = Animations.scaled(
        .spring(
            response: calendarStripScrollResponse,
            dampingFraction: calendarStripScrollDampingFraction
        )
    )
    /// The same spring as `calendarStripScroll`, for `SpringKeyframe` which
    /// cannot take an `Animation`.
    static let calendarStripScrollSpring = Spring(
        response: calendarStripScrollResponse,
        dampingRatio: calendarStripScrollDampingFraction
    )
    static let calendarHeaderSwap = Animations.scaled(.easeOut(duration: 0.12))
    static let calendarEventsReveal = Animations.scaled(.easeOut(duration: 0.18))

    static func respectingReduceMotion(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: Animations.reduceMotionDuration) : animation
    }
}

enum NookContentProgress {
    static let tabsStart: Double = 0.05
    static let tabsWidth: Double = 0.30
    static let mediaStart: Double = 0.15
    static let mediaWidth: Double = 0.40
    static let calendarStart: Double = 0.22
    static let calendarWidth: Double = 0.40
    static let revealOffset: CGFloat = 4

    static func smoothstep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    static func tabs(_ progress: Double) -> Double {
        smoothstep((progress - tabsStart) / tabsWidth)
    }

    static func media(_ progress: Double) -> Double {
        smoothstep((progress - mediaStart) / mediaWidth)
    }

    static func calendar(_ progress: Double) -> Double {
        smoothstep((progress - calendarStart) / calendarWidth)
    }

    static func offset(opacity: Double, reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 0 : revealOffset * (1 - min(max(opacity, 0), 1))
    }

    static func artworkScale(opacity: Double, reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 1 : 0.96 + 0.04 * min(max(opacity, 0), 1)
    }
}

enum CalendarAnimations {
    static let dayHighlight = InteractionMotion.calendarDayHighlight
    static let stripScroll = InteractionMotion.calendarStripScroll
    static let headerSwap = InteractionMotion.calendarHeaderSwap
    static let headerSwapDuration: TimeInterval = 0.12
    static let eventsReveal = InteractionMotion.calendarEventsReveal
    static let eventsRevealDuration: TimeInterval = 0.18
    static let eventsOffset: CGFloat = 4

    static func respectingReduceMotion(_ animation: Animation, reduceMotion: Bool) -> Animation {
        InteractionMotion.respectingReduceMotion(animation, reduceMotion: reduceMotion)
    }
}

enum Animations {
    static let contentShowDelay: TimeInterval = 0.05
    static let contentHideDuration: TimeInterval = 0.12
    /// Content is unmounted only after the close spring has settled, so view teardown never lands mid-animation.
    static let contentUnmountDelay: TimeInterval = 0.5
    static let contentBlurEnabled = false
    static let tabPill = scaled(.spring(response: 0.28, dampingFraction: 0.85))
    static let clickThroughDelay: TimeInterval = 0.2
    static let reduceMotionDuration: TimeInterval = 0.10
    static var presentationMode: NotchPresentationMode = .mergedWithPhysical

    #if DEBUG
    static var timeScale: Double = 1.0
    #endif

    static func effectiveTimeScale(_ debugScale: Double) -> Double {
        #if DEBUG
        return max(debugScale, 1.0)
        #else
        return 1.0
        #endif
    }

    static func plan(for transition: NotchMotionTransition, reduceMotion: Bool) -> NotchMotionPlan {
        if reduceMotion {
            return .crossfade(duration: reduceMotionDuration)
        }
        switch transition {
        case .openMetrics:
            switch presentationMode {
            case .mergedWithPhysical: return .spring(response: 0.26, dampingFraction: 0.88)
            case .ownDynamicIsland: return .spring(response: 0.34, dampingFraction: 0.80)
            case .edgePinned: return .timingCurve(c1x: 0.0, c1y: 0.0, c2x: 0.58, c2y: 1.0, duration: 0.28)
            }
        case .moduleChange:
            return .spring(response: 0.28, dampingFraction: 0.9)
        case .closeMetrics: return .spring(response: 0.22, dampingFraction: 1.0)
        case .contentShow:
            return .spring(response: 0.32, dampingFraction: 0.9)
        case .contentHide:
            return .easeIn(duration: contentHideDuration)
        case .liveActivity:
            return .spring(response: 0.30, dampingFraction: 0.86)
        case .moduleContent:
            return .spring(response: 0.18, dampingFraction: 0.95)
        }
    }

    static func animation(for transition: NotchMotionTransition, reduceMotion: Bool = false) -> Animation {
        animation(for: plan(for: transition, reduceMotion: reduceMotion))
    }

    static func animation(for plan: NotchMotionPlan) -> Animation {
        switch plan {
        case .spring(let response, let dampingFraction):
            return scaled(.spring(response: response, dampingFraction: dampingFraction))
        case .interpolatingSpring(let mass, let stiffness, let damping, let initialVelocity):
            return scaled(.interpolatingSpring(mass: mass, stiffness: stiffness, damping: damping, initialVelocity: initialVelocity))
        case .timingCurve(let c1x, let c1y, let c2x, let c2y, let duration):
            return scaled(.timingCurve(c1x, c1y, c2x, c2y, duration: duration))
        case .easeIn(let duration):
            return scaled(.easeIn(duration: duration))
        case .easeInOut(let duration):
            return scaled(.easeInOut(duration: duration))
        case .crossfade(let duration):
            return .easeInOut(duration: duration)
        }
    }

    static func scaled(_ animation: Animation) -> Animation {
        #if DEBUG
        let scale = effectiveTimeScale(timeScale)
        guard scale != 1.0 else { return animation }
        return animation.speed(1.0 / scale)
        #else
        return animation
        #endif
    }
}

extension Animations {
    static let tabSwitch = Animation.timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.35)
}


extension Animations {
    static let islandHide = Animation.easeOut(duration: 0.25)
}


extension Animations {
    static let islandContent = Animation.easeOut(duration: 0.25)
    static let islandResize = Animation.spring(response: 0.30, dampingFraction: 0.86)
}

extension Animations {
    static func contentRevealDelay(for mode: NotchPresentationMode, reduceMotion: Bool) -> TimeInterval {
        if reduceMotion { return 0 }
        switch mode {
        case .mergedWithPhysical: return 0.092
        case .ownDynamicIsland: return 0.096
        case .edgePinned: return 0.119
        }
    }
}
