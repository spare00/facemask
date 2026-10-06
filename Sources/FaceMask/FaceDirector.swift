import Combine
import Foundation
import SwiftUI

enum FaceMode: Int, CaseIterable {
    case idle
    case thinking
    case speaking

    var title: String {
        switch self {
        case .idle: return "대기"
        case .thinking: return "생각 중"
        case .speaking: return "말하는 중"
        }
    }
}

struct BrowPose: Equatable {
    /// Positive raises both brows. Negative lowers them.
    var lift: CGFloat
    /// Pulls the inner ends down and inward.
    var pinch: CGFloat
    /// Positive raises the viewer's right brow and lowers the left.
    var bias: CGFloat
}

enum FaceEmotion: Int, CaseIterable {
    case calm
    case curious
    case surprised
    case skeptical
    case concerned

    var title: String {
        switch self {
        case .calm: return "평온"
        case .curious: return "궁금"
        case .surprised: return "놀람"
        case .skeptical: return "의심"
        case .concerned: return "걱정"
        }
    }

    static func parse(_ raw: String) -> FaceEmotion? {
        var text = raw.lowercased().replacingOccurrences(of: "*", with: "")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["emotion:", "감정:", "feeling:"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        text = text.trimmingCharacters(in: CharacterSet.punctuationCharacters)
        switch text {
        case "calm", "평온", "neutral": return .calm
        case "curious", "궁금", "curiosity": return .curious
        case "surprised", "놀람", "surprise": return .surprised
        case "skeptical", "의심", "doubt", "skeptic": return .skeptical
        case "concerned", "걱정", "worry", "worried": return .concerned
        default: return nil
        }
    }

    var brows: BrowPose {
        switch self {
        case .calm:
            return BrowPose(lift: 0.08, pinch: 0, bias: 0)
        case .curious:
            return BrowPose(lift: 0.62, pinch: 0.04, bias: 0)
        case .surprised:
            return BrowPose(lift: 1.0, pinch: 0, bias: 0)
        case .skeptical:
            return BrowPose(lift: 0.16, pinch: 0.08, bias: 0.95)
        case .concerned:
            return BrowPose(lift: -0.12, pinch: 0.92, bias: 0)
        }
    }
}

struct FacePose: Equatable {
    var eyeOpen: CGFloat
    var browLift: CGFloat
    var browPinch: CGFloat = 0
    var browBias: CGFloat = 0
    /// Positive lifts the corners into a smile.
    var mouthCurve: CGFloat
    var mouthOpen: CGFloat
    /// Positive looks right.
    var lookX: CGFloat
    /// Positive looks up. Canvas Y grows downward.
    var lookY: CGFloat
    var bob: CGFloat = 0

    static let idle = FacePose(
        eyeOpen: 0.90,
        browLift: 0.10,
        mouthCurve: 0.30,
        mouthOpen: 0,
        lookX: 0.06,
        lookY: 0.02
    )

    static let thinking = FacePose(
        eyeOpen: 0.56,
        browLift: 0.95,
        mouthCurve: -0.16,
        mouthOpen: 0,
        lookX: -0.62,
        lookY: 0.74
    )

    static let speaking = FacePose(
        eyeOpen: 0.94,
        browLift: 0.30,
        mouthCurve: 0.38,
        mouthOpen: 0.72,
        lookX: 0.04,
        lookY: -0.02
    )
}

final class FaceDirector: ObservableObject {
    @Published private(set) var pose: FacePose = .idle
    private(set) var mode: FaceMode = .idle
    /// Nil follows the current mode. A value holds that expression for a later model binding.
    private(set) var emotion: FaceEmotion?

    var onModeChange: ((FaceMode) -> Void)?
    var onEmotionChange: ((FaceEmotion?) -> Void)?

    private var base: FacePose = .idle
    private var started = Date()
    private var lastTick = Date()
    private var timer: Timer?

    private var blink: CGFloat = 0
    private var blinkStage: BlinkStage = .waiting
    private var stageStart = Date()
    private var nextBlink = Date()
    private var queuedDoubleBlink = false

    private var gaze = CGPoint(x: 0.04, y: 0.02)
    private var gazeTarget = CGPoint(x: 0.04, y: 0.02)
    private var nextSaccade = Date()

    private var brow = FaceEmotion.calm.brows
    private var browTarget = FaceEmotion.calm.brows
    private var nextBrow = Date()

    func start() {
        started = Date()
        lastTick = started
        nextBlink = started.addingTimeInterval(1.6)
        nextSaccade = started.addingTimeInterval(0.8)
        nextBrow = started.addingTimeInterval(1.1)
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cycle() {
        let next: FaceMode
        switch mode {
        case .idle: next = .thinking
        case .thinking: next = .speaking
        case .speaking: next = .idle
        }
        setMode(next)
    }

    func setMode(_ mode: FaceMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        nextSaccade = Date()
        if emotion == nil {
            nextBrow = Date()
        }
        onModeChange?(mode)
    }

    func setEmotion(_ emotion: FaceEmotion?) {
        guard emotion != self.emotion else { return }
        self.emotion = emotion
        nextBrow = Date()
        onEmotionChange?(emotion)
    }

    private func tick() {
        let now = Date()
        let dt = min(0.05, now.timeIntervalSince(lastTick))
        lastTick = now
        updateBlink(now)
        updateGaze(now, dt: dt)
        updateBrows(now, dt: dt)

        let target = targetPose(at: now.timeIntervalSince(started))
        base = approach(base, target, dt: dt)
        var shown = base
        shown.eyeOpen *= (1 - blink)
        shown.lookX = gaze.x
        shown.lookY = gaze.y
        shown.browLift = brow.lift
        shown.browPinch = brow.pinch
        shown.browBias = brow.bias
        if mode == .speaking, emotion == nil {
            shown.browLift += max(0, shown.mouthOpen - 0.35) * 0.2
        }
        pose = shown
    }

    private func targetPose(at time: TimeInterval) -> FacePose {
        switch mode {
        case .idle:
            var pose = FacePose.idle
            pose.bob = sin(time * 1.45) * 2
            return pose
        case .thinking:
            var pose = FacePose.thinking
            pose.bob = sin(time * 1.2) * 1.2
            return pose
        case .speaking:
            var pose = FacePose.speaking
            let wave = sin(time * 14) * 0.5 + sin(time * 9.1) * 0.28
            pose.mouthOpen = min(1, max(0.12, 0.46 + wave * 0.42))
            pose.mouthCurve = 0.34 + sin(time * 8) * 0.05
            pose.bob = sin(time * 1.45) * 1.4
            return pose
        }
    }

    private func approach(_ current: FacePose, _ target: FacePose, dt: TimeInterval) -> FacePose {
        let k = CGFloat(1 - exp(-dt * 10))
        func mix(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
            from + (to - from) * k
        }
        return FacePose(
            eyeOpen: mix(current.eyeOpen, target.eyeOpen),
            browLift: mix(current.browLift, target.browLift),
            browPinch: mix(current.browPinch, target.browPinch),
            browBias: mix(current.browBias, target.browBias),
            mouthCurve: mix(current.mouthCurve, target.mouthCurve),
            mouthOpen: mix(current.mouthOpen, target.mouthOpen),
            lookX: mix(current.lookX, target.lookX),
            lookY: mix(current.lookY, target.lookY),
            bob: mix(current.bob, target.bob)
        )
    }

    private func updateGaze(_ now: Date, dt: TimeInterval) {
        if now >= nextSaccade {
            let pick = pickGaze()
            gazeTarget = pick.point
            nextSaccade = now.addingTimeInterval(pick.hold)
        }
        let k = CGFloat(1 - exp(-dt * 14))
        gaze.x += (gazeTarget.x - gaze.x) * k
        gaze.y += (gazeTarget.y - gaze.y) * k
    }

    private func pickGaze() -> (point: CGPoint, hold: TimeInterval) {
        for _ in 0..<3 {
            let pick = gazeCandidate()
            let dx = pick.point.x - gaze.x
            let dy = pick.point.y - gaze.y
            if hypot(dx, dy) > 0.2 { return pick }
        }
        return gazeCandidate()
    }

    private func gazeCandidate() -> (point: CGPoint, hold: TimeInterval) {
        switch mode {
        case .idle:
            let roll = Double.random(in: 0...1)
            if roll < 0.5 {
                return (
                    CGPoint(
                        x: CGFloat.random(in: -0.14...0.14),
                        y: CGFloat.random(in: -0.08...0.12)
                    ),
                    Double.random(in: 1.5...3.0)
                )
            }
            if roll < 0.78 {
                let side: CGFloat = Bool.random() ? 1 : -1
                return (
                    CGPoint(
                        x: side * CGFloat.random(in: 0.48...0.78),
                        y: CGFloat.random(in: -0.1...0.22)
                    ),
                    Double.random(in: 0.55...1.15)
                )
            }
            if roll < 0.92 {
                return (
                    CGPoint(
                        x: CGFloat.random(in: -0.22...0.22),
                        y: CGFloat.random(in: 0.38...0.62)
                    ),
                    Double.random(in: 0.6...1.2)
                )
            }
            return (
                CGPoint(
                    x: CGFloat.random(in: -0.3...0.3),
                    y: CGFloat.random(in: -0.32 ... -0.1)
                ),
                Double.random(in: 0.5...0.95)
            )
        case .thinking:
            return (
                CGPoint(
                    x: -0.42 + CGFloat.random(in: -0.28...0.22),
                    y: 0.5 + CGFloat.random(in: -0.12...0.22)
                ),
                Double.random(in: 0.7...1.5)
            )
        case .speaking:
            return (
                CGPoint(
                    x: CGFloat.random(in: -0.32...0.32),
                    y: CGFloat.random(in: -0.16...0.24)
                ),
                Double.random(in: 0.75...1.6)
            )
        }
    }

    private func updateBrows(_ now: Date, dt: TimeInterval) {
        if now >= nextBrow {
            let pick = pickBrow()
            browTarget = pick.pose
            nextBrow = now.addingTimeInterval(pick.hold)
        }
        let k = CGFloat(1 - exp(-dt * 5))
        brow = mixBrow(brow, browTarget, k)
    }

    private func pickBrow() -> (pose: BrowPose, hold: TimeInterval) {
        if let emotion {
            return (emotion.brows, 60)
        }
        for _ in 0..<3 {
            let pick = browCandidate()
            let distance = abs(pick.pose.lift - brow.lift)
                + abs(pick.pose.pinch - brow.pinch)
                + abs(pick.pose.bias - brow.bias)
            if distance > 0.35 { return pick }
        }
        return browCandidate()
    }

    private func browCandidate() -> (pose: BrowPose, hold: TimeInterval) {
        let emotion: FaceEmotion
        let hold: TimeInterval
        switch mode {
        case .idle:
            let roll = Double.random(in: 0...1)
            if roll < 0.52 {
                emotion = .calm
                hold = Double.random(in: 1.8...3.2)
            } else if roll < 0.78 {
                emotion = .curious
                hold = Double.random(in: 1.1...1.9)
            } else if roll < 0.92 {
                emotion = .skeptical
                hold = Double.random(in: 0.85...1.5)
            } else {
                emotion = .concerned
                hold = Double.random(in: 0.9...1.5)
            }
        case .thinking:
            let roll = Double.random(in: 0...1)
            if roll < 0.4 {
                emotion = .curious
                hold = Double.random(in: 1.0...1.8)
            } else if roll < 0.72 {
                emotion = .concerned
                hold = Double.random(in: 1.0...1.7)
            } else if roll < 0.88 {
                emotion = .surprised
                hold = Double.random(in: 0.7...1.2)
            } else {
                emotion = .skeptical
                hold = Double.random(in: 0.8...1.4)
            }
        case .speaking:
            let roll = Double.random(in: 0...1)
            if roll < 0.55 {
                emotion = .calm
                hold = Double.random(in: 0.9...1.6)
            } else if roll < 0.85 {
                emotion = .curious
                hold = Double.random(in: 0.8...1.4)
            } else {
                emotion = .surprised
                hold = Double.random(in: 0.55...1.0)
            }
        }
        var brows = emotion.brows
        if emotion == .skeptical, Bool.random() {
            brows.bias = -brows.bias
        }
        return (brows, hold)
    }

    private func mixBrow(_ from: BrowPose, _ to: BrowPose, _ k: CGFloat) -> BrowPose {
        BrowPose(
            lift: from.lift + (to.lift - from.lift) * k,
            pinch: from.pinch + (to.pinch - from.pinch) * k,
            bias: from.bias + (to.bias - from.bias) * k
        )
    }

    private func updateBlink(_ now: Date) {
        switch blinkStage {
        case .waiting:
            if now >= nextBlink {
                blinkStage = .closing
                stageStart = now
            }
        case .closing:
            let u = unit(now, duration: 0.07)
            blink = ease(u)
            if u >= 1 {
                blink = 1
                blinkStage = .holding
                stageStart = now
            }
        case .holding:
            blink = 1
            if now.timeIntervalSince(stageStart) >= 0.04 {
                blinkStage = .opening
                stageStart = now
            }
        case .opening:
            let u = unit(now, duration: 0.11)
            blink = 1 - ease(u)
            if u >= 1 {
                blink = 0
                blinkStage = .waiting
                if queuedDoubleBlink {
                    queuedDoubleBlink = false
                    nextBlink = now.addingTimeInterval(Double.random(in: 2.4...5.4))
                } else if Double.random(in: 0...1) < 0.18 {
                    queuedDoubleBlink = true
                    nextBlink = now.addingTimeInterval(0.14)
                } else {
                    nextBlink = now.addingTimeInterval(Double.random(in: 2.4...5.4))
                }
            }
        }
    }

    private func unit(_ now: Date, duration: TimeInterval) -> CGFloat {
        min(1, CGFloat(now.timeIntervalSince(stageStart) / duration))
    }

    private func ease(_ u: CGFloat) -> CGFloat {
        u * u * (3 - 2 * u)
    }
}

private enum BlinkStage {
    case waiting
    case closing
    case holding
    case opening
}
