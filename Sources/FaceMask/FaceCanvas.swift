import SwiftUI

enum FaceLook: String, CaseIterable {
    case round
    case puppy
    case glasses

    var title: String {
        switch self {
        case .round: return "큰 눈"
        case .puppy: return "강아지"
        case .glasses: return "뿔테"
        }
    }
}

final class FaceLooks: ObservableObject {
    @Published private(set) var current: FaceLook

    init() {
        let raw = UserDefaults.standard.string(forKey: "FaceLook") ?? FaceLook.round.rawValue
        current = FaceLook(rawValue: raw) ?? .round
    }

    func select(_ look: FaceLook) {
        guard look != current else { return }
        current = look
        UserDefaults.standard.set(look.rawValue, forKey: "FaceLook")
    }
}

enum FaceLayout {
    static let width: CGFloat = 300
    static let height: CGFloat = 340
    static let chrome: CGFloat = 60
    static var window: CGSize {
        CGSize(width: width, height: height + chrome)
    }
}

struct FaceCanvas: View {
    var pose: FacePose
    var look: FaceLook = .round

    var body: some View {
        Canvas { context, size in
            switch look {
            case .round:
                drawRound(pose: pose, context: &context, size: size)
            case .puppy:
                drawPuppy(pose: pose, context: &context, size: size)
            case .glasses:
                drawGlasses(pose: pose, context: &context, size: size)
            }
        }
    }
}

struct FacePreview: View {
    var body: some View {
        VStack(spacing: 28) {
            HStack(alignment: .top, spacing: 28) {
                column(.round, .idle, "큰 눈")
                column(.puppy, .idle, "강아지")
                column(.glasses, .idle, "뿔테")
            }
            HStack(alignment: .top, spacing: 28) {
                column(.glasses, .idle, "뿔테")
                column(.glasses, .speaking, "뿔테 말")
                column(.glasses, blinkPose, "뿔테 깜빡")
                column(.glasses, yawnPose, "뿔테 하품")
            }
        }
        .padding(36)
        .background(Color(white: 0.07))
    }

    private var blinkPose: FacePose {
        var pose = FacePose.idle
        pose.eyeOpen = 0.04
        return pose
    }

    private var yawnPose: FacePose {
        var pose = FacePose.idle
        pose.eyeOpen = 0.08
        pose.mouthOpen = 0.95
        pose.mouthCurve = 0.04
        pose.browLift = 0.4
        return pose
    }

    private func column(_ look: FaceLook, _ pose: FacePose, _ title: String) -> some View {
        VStack(spacing: 8) {
            FaceCanvas(pose: pose, look: look)
                .frame(width: FaceLayout.width, height: FaceLayout.height)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

private func drawRound(pose: FacePose, context: inout GraphicsContext, size: CGSize) {
    let inkWidth = max(1.7, size.width * 0.0064)
    let cx = size.width * 0.5
    let bob = pose.bob
    let eyeY = size.height * 0.41 + bob
    let spread = size.width * 0.20
    let browY = eyeY - size.height * 0.20
    let mouthY = size.height * 0.73 + bob
    ink(
        brow(midX: cx - spread, y: browY, lift: pose.browLift, pinch: pose.browPinch, bias: pose.browBias, side: -1, scale: size.width),
        width: inkWidth * 0.72,
        halo: 1.3,
        in: &context
    )
    ink(
        brow(midX: cx + spread, y: browY, lift: pose.browLift, pinch: pose.browPinch, bias: pose.browBias, side: 1, scale: size.width),
        width: inkWidth * 0.72,
        halo: 1.3,
        in: &context
    )
    ink(nose(cx: cx, eyeY: eyeY, mouthY: mouthY), width: inkWidth * 0.78, halo: 1.3, in: &context)
    ink(mouth(cx: cx, y: mouthY, pose: pose, size: size), width: inkWidth * 0.95, halo: 1.5, in: &context)
    ink(blush(center: CGPoint(x: cx - spread, y: eyeY), side: -1, scale: size.width), width: inkWidth * 0.7, halo: 1.15, in: &context)
    ink(blush(center: CGPoint(x: cx + spread, y: eyeY), side: 1, scale: size.width), width: inkWidth * 0.7, halo: 1.15, in: &context)
    driftingZ(cx: cx, mouthY: mouthY, progress: pose.zzz, scale: 1, size: size, in: &context)
    driftingZ(cx: cx + size.width * 0.045, mouthY: mouthY - size.height * 0.03, progress: pose.zzz2, scale: 0.72, size: size, in: &context)
    drawEye(center: CGPoint(x: cx - spread, y: eyeY), pose: pose, size: size, side: -1, inkWidth: inkWidth, in: &context)
    drawEye(center: CGPoint(x: cx + spread, y: eyeY), pose: pose, size: size, side: 1, inkWidth: inkWidth, in: &context)
}

private struct EyeShape {
    var upperLid: Path
    var lowerLid: Path
    var closed: Path
    var temporal: CGPoint
    var upper: CGPoint
    var nasal: CGPoint
    var lower: CGPoint
    var open: CGFloat
    var h: CGFloat
    var w: CGFloat
}

private func brow(
    midX: CGFloat,
    y: CGFloat,
    lift: CGFloat,
    pinch: CGFloat,
    bias: CGFloat,
    side: CGFloat,
    scale: CGFloat
) -> Path {
    let dir: CGFloat = side < 0 ? 1 : -1
    let sideLift = bias * side * scale * 0.04
    let raise = lift * scale * 0.045
    let pinchDrop = max(0, pinch) * scale * 0.038
    let pinchIn = max(0, pinch) * scale * 0.016
    let inner = CGPoint(
        x: midX + dir * scale * 0.055 - dir * pinchIn,
        y: y + scale * 0.012 - raise * 0.25 + pinchDrop - sideLift * 0.08
    )
    let tail = CGPoint(
        x: midX - dir * scale * 0.175,
        y: y + scale * 0.028 - raise * 0.08 - sideLift
    )
    var path = Path()
    path.move(to: inner)
    path.addCurve(
        to: tail,
        control1: CGPoint(
            x: midX + dir * scale * 0.01,
            y: y - scale * 0.03 - raise - sideLift * 0.35 + pinchDrop * 0.12
        ),
        control2: CGPoint(
            x: midX - dir * scale * 0.09,
            y: y - scale * 0.012 - raise * 0.4 - sideLift * 0.7
        )
    )
    return path
}

private func eye(center: CGPoint, pose: FacePose, size: CGSize, side: CGFloat) -> EyeShape {
    let w = size.width * 0.128
    let open = min(1, max(0, pose.eyeOpen))
    let temporal = CGPoint(x: center.x + side * w, y: center.y - 1.5)
    let nasal = CGPoint(x: center.x - side * w * 0.92, y: center.y + 2.2)
    if open < 0.16 {
        var closed = Path()
        closed.move(to: temporal)
        closed.addQuadCurve(to: nasal, control: CGPoint(x: center.x - side * w * 0.04, y: center.y + 8))
        return EyeShape(
            upperLid: Path(),
            lowerLid: Path(),
            closed: closed,
            temporal: temporal,
            upper: center,
            nasal: nasal,
            lower: center,
            open: open,
            h: 0,
            w: w
        )
    }
    let h = size.height * 0.186 * open
    let upper = CGPoint(x: center.x - side * w * 0.02, y: center.y - h * 1.42)
    let lower = CGPoint(x: center.x + side * w * 0.01, y: center.y + h * 1.18)
    var upperLid = Path()
    upperLid.move(to: temporal)
    upperLid.addQuadCurve(to: nasal, control: upper)
    var lowerLid = Path()
    lowerLid.move(to: nasal)
    lowerLid.addQuadCurve(to: temporal, control: lower)
    return EyeShape(
        upperLid: upperLid,
        lowerLid: lowerLid,
        closed: Path(),
        temporal: temporal,
        upper: upper,
        nasal: nasal,
        lower: lower,
        open: open,
        h: h,
        w: w
    )
}

private func drawEye(
    center: CGPoint,
    pose: FacePose,
    size: CGSize,
    side: CGFloat,
    inkWidth: CGFloat,
    in context: inout GraphicsContext
) {
    let shape = eye(center: center, pose: pose, size: size, side: side)
    if shape.open < 0.16 {
        ink(shape.closed, width: inkWidth * 0.95, halo: 1.5, in: &context)
        return
    }
    ink(shape.lowerLid, width: inkWidth * 0.72, halo: 1.3, in: &context)
    iris(center: center, pose: pose, shape: shape, size: size, in: &context)
    ink(shape.upperLid, width: inkWidth * 1.25, halo: 1.6, in: &context)
    ink(upperLashes(shape: shape, side: side), width: inkWidth * 0.78, halo: 1.15, in: &context)
    ink(lowerLashes(shape: shape, side: side), width: inkWidth * 0.62, halo: 1.05, in: &context)
}

private func upperLashes(shape: EyeShape, side: CGFloat) -> Path {
    guard shape.open > 0.34 else { return Path() }
    var path = Path()
    let marks: [(CGFloat, CGFloat, CGFloat)] = [
        (0.00, 0.62, 1.45),
        (0.07, 0.48, 1.05),
        (0.16, 0.36, 0.62),
        (0.28, 0.28, 0.28),
        (0.42, 0.24, 0.08),
        (0.58, 0.2, -0.08),
        (0.74, 0.16, -0.22)
    ]
    let reach = min(1, shape.open / 0.75)
    for (t, length, fan) in marks {
        let origin = pointOnQuad(t, shape.temporal, shape.upper, shape.nasal)
        let ahead = pointOnQuad(min(0.98, t + 0.035), shape.temporal, shape.upper, shape.nasal)
        let normal = outwardNormal(from: origin, to: ahead, side: side, fan: fan)
        let span = shape.w * length * reach
        let tip = CGPoint(x: origin.x + normal.x * span, y: origin.y + normal.y * span)
        let bend = CGPoint(
            x: origin.x + normal.x * span * 0.45 + side * span * 0.38,
            y: origin.y + normal.y * span * 0.42
        )
        path.move(to: origin)
        path.addQuadCurve(to: tip, control: bend)
    }
    return path
}

private func lowerLashes(shape: EyeShape, side: CGFloat) -> Path {
    guard shape.open > 0.62 else { return Path() }
    var path = Path()
    let marks: [(CGFloat, CGFloat)] = [(0.22, 0.16), (0.4, 0.13), (0.58, 0.1)]
    for (t, length) in marks {
        let origin = pointOnQuad(t, shape.temporal, shape.lower, shape.nasal)
        let ahead = pointOnQuad(min(0.98, t + 0.04), shape.temporal, shape.lower, shape.nasal)
        var normal = outwardNormal(from: origin, to: ahead, side: side, fan: 0.8)
        normal.x = -normal.x
        normal.y = -normal.y
        if normal.y < 0 {
            normal.x = -normal.x
            normal.y = -normal.y
        }
        let span = shape.w * length
        path.move(to: origin)
        path.addLine(to: CGPoint(x: origin.x + normal.x * span, y: origin.y + normal.y * span))
    }
    return path
}

private func outwardNormal(from origin: CGPoint, to ahead: CGPoint, side: CGFloat, fan: CGFloat) -> CGPoint {
    var tx = ahead.x - origin.x
    var ty = ahead.y - origin.y
    let span = max(0.001, hypot(tx, ty))
    tx /= span
    ty /= span
    var nx = -ty
    var ny = tx
    if ny > 0 {
        nx = -nx
        ny = -ny
    }
    nx += side * fan
    let normal = max(0.001, hypot(nx, ny))
    return CGPoint(x: nx / normal, y: ny / normal)
}

private func pointOnQuad(_ t: CGFloat, _ a: CGPoint, _ c: CGPoint, _ b: CGPoint) -> CGPoint {
    let u = 1 - t
    return CGPoint(
        x: u * u * a.x + 2 * u * t * c.x + t * t * b.x,
        y: u * u * a.y + 2 * u * t * c.y + t * t * b.y
    )
}

private func iris(center: CGPoint, pose: FacePose, shape: EyeShape, size: CGSize, in context: inout GraphicsContext) {
    guard shape.open > 0.4, shape.h > 4 else { return }
    let lookX = min(1, max(-1, pose.lookX))
    let lookY = min(1, max(-1, pose.lookY))
    let radius = min(shape.w * 0.78, shape.h * 0.5)
    guard radius > 2 else { return }
    let x = center.x + lookX * shape.w * 0.14
    let y = center.y + shape.h * 0.02 - lookY * shape.h * 0.16
    var ring = Path()
    ring.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    ink(ring, width: max(1.35, size.width * 0.0055), halo: 1.35, in: &context)
    var crescent = Path()
    crescent.addArc(
        center: CGPoint(x: x, y: y + radius * 0.38),
        radius: radius * 0.4,
        startAngle: .degrees(48),
        endAngle: .degrees(132),
        clockwise: false
    )
    ink(crescent, width: max(1.45, size.width * 0.0052), halo: 1.15, in: &context)
    gloss(CGPoint(x: x - radius * 0.3, y: y - radius * 0.36), radius: radius * 0.22, in: &context)
    gloss(CGPoint(x: x + radius * 0.16, y: y - radius * 0.2), radius: radius * 0.07, in: &context)
}

private func gloss(_ center: CGPoint, radius: CGFloat, in context: inout GraphicsContext) {
    let halo = radius + 0.7
    context.fill(
        Path(ellipseIn: CGRect(x: center.x - halo, y: center.y - halo, width: halo * 2, height: halo * 2)),
        with: .color(.black.opacity(0.4))
    )
    context.fill(
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
        with: .color(Color(white: 0.98))
    )
}

private func blush(center: CGPoint, side: CGFloat, scale: CGFloat) -> Path {
    let base = CGPoint(x: center.x - side * scale * 0.012, y: center.y + scale * 0.145)
    var path = Path()
    for index in 0..<2 {
        let shift = CGFloat(index) * scale * 0.026
        let start = CGPoint(x: base.x + side * shift, y: base.y + CGFloat(index) * 1.5)
        let end = CGPoint(x: start.x + side * scale * 0.018, y: start.y + scale * 0.04)
        path.move(to: start)
        path.addLine(to: end)
    }
    return path
}

private func nose(cx: CGFloat, eyeY: CGFloat, mouthY: CGFloat) -> Path {
    let span = mouthY - eyeY
    let top = CGPoint(x: cx, y: eyeY + span * 0.2)
    let tip = CGPoint(x: cx + 0.6, y: eyeY + span * 0.36)
    var path = Path()
    path.move(to: top)
    path.addLine(to: tip)
    path.addQuadCurve(
        to: CGPoint(x: cx + 6, y: tip.y + 0.4),
        control: CGPoint(x: cx + 4.5, y: tip.y - 2)
    )
    return path
}

private func mouth(
    cx: CGFloat,
    y: CGFloat,
    pose: FacePose,
    size: CGSize,
    halfScale: CGFloat = 0.068,
    bowHeight: CGFloat = 4.6,
    lowerDrop: CGFloat = 11
) -> Path {
    let half = size.width * halfScale
    let smile = pose.mouthCurve
    let open = max(0, pose.mouthOpen)
    let cornerLift = smile * 10
    let bow = bowHeight * (1 - min(1, open) * 0.7)
    let left = CGPoint(x: cx - half, y: y - cornerLift)
    let right = CGPoint(x: cx + half, y: y - cornerLift)
    let leftPeak = CGPoint(x: cx - half * 0.3, y: y - bow - cornerLift * 0.25)
    let rightPeak = CGPoint(x: cx + half * 0.3, y: y - bow - cornerLift * 0.25)
    var path = Path()
    path.move(to: left)
    path.addQuadCurve(
        to: leftPeak,
        control: CGPoint(x: cx - half * 0.72, y: y - bow * 0.15 - cornerLift * 0.55)
    )
    path.addQuadCurve(
        to: rightPeak,
        control: CGPoint(x: cx, y: y - bow * 0.15 + 3.4 + open * 2.5)
    )
    path.addQuadCurve(
        to: right,
        control: CGPoint(x: cx + half * 0.72, y: y - bow * 0.15 - cornerLift * 0.55)
    )
    path.move(to: left)
    path.addQuadCurve(
        to: right,
        control: CGPoint(x: cx, y: y + lowerDrop + open * 32 - smile * 2)
    )
    if open < 0.2 {
        path.move(to: CGPoint(x: cx - half * 0.62, y: y + 1.4 - cornerLift * 0.15))
        path.addQuadCurve(
            to: CGPoint(x: cx + half * 0.62, y: y + 1.4 - cornerLift * 0.15),
            control: CGPoint(x: cx, y: y + 3.1)
        )
    }
    return path
}

private func drawPuppy(pose: FacePose, context: inout GraphicsContext, size: CGSize) {
    let inkWidth = max(1.6, size.width * 0.0054)
    let cx = size.width * 0.5
    let bob = pose.bob
    let eyeY = size.height * 0.43 + bob
    let spread = size.width * 0.145
    let noseY = eyeY + size.height * 0.115
    let mouthY = noseY + size.height * 0.05
    ink(puppyEar(cx: cx, top: size.height * 0.13 + bob, side: -1, size: size), width: inkWidth * 0.9, halo: 1.35, in: &context)
    ink(puppyEar(cx: cx, top: size.height * 0.13 + bob, side: 1, size: size), width: inkWidth * 0.9, halo: 1.35, in: &context)
    ink(puppyTuft(cx: cx, y: size.height * 0.125 + bob, scale: size.width), width: inkWidth * 0.72, halo: 1.15, in: &context)
    ink(
        puppyBrow(center: CGPoint(x: cx - spread, y: eyeY), lift: pose.browLift, pinch: pose.browPinch, bias: pose.browBias, side: -1, scale: size.width),
        width: inkWidth * 0.7, halo: 1.15, in: &context
    )
    ink(
        puppyBrow(center: CGPoint(x: cx + spread, y: eyeY), lift: pose.browLift, pinch: pose.browPinch, bias: pose.browBias, side: 1, scale: size.width),
        width: inkWidth * 0.7, halo: 1.15, in: &context
    )
    drawPuppyEye(center: CGPoint(x: cx - spread, y: eyeY), pose: pose, size: size, side: -1, inkWidth: inkWidth, in: &context)
    drawPuppyEye(center: CGPoint(x: cx + spread, y: eyeY), pose: pose, size: size, side: 1, inkWidth: inkWidth, in: &context)
    ink(puppyNose(cx: cx, y: noseY, scale: size.width), width: inkWidth * 0.85, halo: 1.25, in: &context)
    ink(puppyMouth(cx: cx, y: mouthY, pose: pose, size: size), width: inkWidth * 0.9, halo: 1.3, in: &context)
    ink(puppyTongue(cx: cx, y: mouthY, pose: pose, size: size), width: inkWidth * 0.85, halo: 1.25, in: &context)
    ink(puppyCheek(at: CGPoint(x: cx - spread * 0.35, y: mouthY - size.height * 0.01), side: -1, scale: size.width), width: inkWidth * 0.6, halo: 1.05, in: &context)
    ink(puppyCheek(at: CGPoint(x: cx + spread * 0.35, y: mouthY - size.height * 0.01), side: 1, scale: size.width), width: inkWidth * 0.6, halo: 1.05, in: &context)
    ink(puppyChin(cx: cx, y: mouthY + size.height * 0.02, side: -1, scale: size.width), width: inkWidth * 0.75, halo: 1.15, in: &context)
    ink(puppyChin(cx: cx, y: mouthY + size.height * 0.02, side: 1, scale: size.width), width: inkWidth * 0.75, halo: 1.15, in: &context)
    driftingZ(cx: cx, mouthY: mouthY, progress: pose.zzz, scale: 1, size: size, in: &context)
    driftingZ(cx: cx + size.width * 0.04, mouthY: mouthY - size.height * 0.04, progress: pose.zzz2, scale: 0.72, size: size, in: &context)
}

private func puppyTuft(cx: CGFloat, y: CGFloat, scale: CGFloat) -> Path {
    var path = Path()
    let peaks: [(CGFloat, CGFloat, CGFloat)] = [
        (-0.1, 0.7, -0.01),
        (-0.035, 1, 0),
        (0.03, 0.9, 0.012),
        (0.09, 0.55, 0.008)
    ]
    for (dx, height, lean) in peaks {
        let base = cx + dx * scale
        path.move(to: CGPoint(x: base - scale * 0.028, y: y))
        path.addQuadCurve(
            to: CGPoint(x: base + scale * 0.03, y: y + scale * 0.008),
            control: CGPoint(x: base + lean * scale, y: y - scale * 0.07 * height)
        )
    }
    path.move(to: CGPoint(x: cx - scale * 0.16, y: y + scale * 0.01))
    path.addQuadCurve(
        to: CGPoint(x: cx - scale * 0.05, y: y - scale * 0.01),
        control: CGPoint(x: cx - scale * 0.1, y: y - scale * 0.03)
    )
    path.move(to: CGPoint(x: cx + scale * 0.16, y: y + scale * 0.01))
    path.addQuadCurve(
        to: CGPoint(x: cx + scale * 0.05, y: y - scale * 0.01),
        control: CGPoint(x: cx + scale * 0.1, y: y - scale * 0.03)
    )
    return path
}

private func puppyEar(cx: CGFloat, top: CGFloat, side: CGFloat, size: CGSize) -> Path {
    let w = size.width
    let h = size.height
    let root = CGPoint(x: cx + side * w * 0.18, y: top + h * 0.02)
    let crown = CGPoint(x: cx + side * w * 0.36, y: top - h * 0.03)
    let outer = CGPoint(x: cx + side * w * 0.47, y: top + h * 0.18)
    let tip = CGPoint(x: cx + side * w * 0.34, y: top + h * 0.42)
    let inner = CGPoint(x: cx + side * w * 0.16, y: top + h * 0.2)
    var path = Path()
    path.move(to: root)
    path.addQuadCurve(to: outer, control: crown)
    path.addQuadCurve(to: tip, control: CGPoint(x: cx + side * w * 0.5, y: top + h * 0.32))
    path.addQuadCurve(to: inner, control: CGPoint(x: cx + side * w * 0.26, y: top + h * 0.44))
    path.addQuadCurve(to: root, control: CGPoint(x: cx + side * w * 0.1, y: top + h * 0.08))
    path.move(to: CGPoint(x: cx + side * w * 0.3, y: top + h * 0.04))
    path.addQuadCurve(
        to: CGPoint(x: cx + side * w * 0.28, y: top + h * 0.28),
        control: CGPoint(x: cx + side * w * 0.4, y: top + h * 0.14)
    )
    path.move(to: CGPoint(x: cx + side * w * 0.22, y: top + h * 0.07))
    path.addQuadCurve(
        to: CGPoint(x: cx + side * w * 0.2, y: top + h * 0.22),
        control: CGPoint(x: cx + side * w * 0.3, y: top + h * 0.12)
    )
    return path
}

private func puppyBrow(
    center: CGPoint,
    lift: CGFloat,
    pinch: CGFloat,
    bias: CGFloat,
    side: CGFloat,
    scale: CGFloat
) -> Path {
    let raise = lift * scale * 0.028
    let sideLift = bias * side * scale * 0.018
    let pinchDrop = max(0, pinch) * scale * 0.02
    let y = center.y - scale * 0.075
    let inner = CGPoint(
        x: center.x - side * scale * 0.01,
        y: y + pinchDrop - raise * 0.35 - sideLift * 0.15
    )
    let outer = CGPoint(
        x: center.x + side * scale * 0.075,
        y: y + scale * 0.012 - raise * 0.15 - sideLift
    )
    var path = Path()
    path.move(to: inner)
    path.addQuadCurve(
        to: outer,
        control: CGPoint(x: center.x + side * scale * 0.03, y: y - scale * 0.018 - raise)
    )
    return path
}

private func drawPuppyEye(
    center: CGPoint,
    pose: FacePose,
    size: CGSize,
    side: CGFloat,
    inkWidth: CGFloat,
    in context: inout GraphicsContext
) {
    let rx = size.width * 0.078
    let open = min(1, max(0, pose.eyeOpen))
    if open < 0.16 {
        var closed = Path()
        closed.move(to: CGPoint(x: center.x - rx, y: center.y))
        closed.addQuadCurve(
            to: CGPoint(x: center.x + rx, y: center.y - 1),
            control: CGPoint(x: center.x, y: center.y + 5)
        )
        ink(closed, width: inkWidth * 0.95, halo: 1.4, in: &context)
        return
    }
    let ry = size.height * 0.068 * open
    var lid = Path()
    lid.addEllipse(in: CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2))
    ink(lid, width: inkWidth * 0.95, halo: 1.4, in: &context)
    ink(puppyLashes(center: center, rx: rx, ry: ry, side: side, open: open), width: inkWidth * 0.58, halo: 1.0, in: &context)
    let lookX = min(1, max(-1, pose.lookX))
    let lookY = min(1, max(-1, pose.lookY))
    let radius = min(rx * 0.48, ry * 0.62)
    guard radius > 1.8 else { return }
    let x = center.x + lookX * rx * 0.18
    let y = center.y - lookY * ry * 0.16
    var ring = Path()
    ring.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    ink(ring, width: max(1.2, size.width * 0.004), halo: 1.15, in: &context)
    gloss(CGPoint(x: x - radius * 0.32, y: y - radius * 0.34), radius: radius * 0.28, in: &context)
}

private func puppyLashes(center: CGPoint, rx: CGFloat, ry: CGFloat, side: CGFloat, open: CGFloat) -> Path {
    var path = Path()
    let marks: [(CGFloat, CGFloat)] = [(-0.15, 0.55), (0.15, 0.7), (0.42, 0.9), (0.7, 1)]
    for (along, weight) in marks {
        let x = center.x + side * rx * along
        let y = center.y - ry * (0.72 + (1 - abs(along)) * 0.18)
        let length = rx * 0.28 * weight * min(1, open / 0.7)
        path.move(to: CGPoint(x: x, y: y))
        path.addQuadCurve(
            to: CGPoint(x: x + side * length * 0.85, y: y - length),
            control: CGPoint(x: x + side * length * 0.2, y: y - length * 0.35)
        )
    }
    return path
}

private func puppyNose(cx: CGFloat, y: CGFloat, scale: CGFloat) -> Path {
    let rw = scale * 0.05
    let rh = scale * 0.034
    var path = Path()
    path.move(to: CGPoint(x: cx, y: y - rh))
    path.addQuadCurve(to: CGPoint(x: cx - rw, y: y + rh * 0.15), control: CGPoint(x: cx - rw * 0.95, y: y - rh * 0.85))
    path.addQuadCurve(to: CGPoint(x: cx, y: y + rh), control: CGPoint(x: cx - rw * 0.35, y: y + rh * 1.05))
    path.addQuadCurve(to: CGPoint(x: cx + rw, y: y + rh * 0.15), control: CGPoint(x: cx + rw * 0.35, y: y + rh * 1.05))
    path.addQuadCurve(to: CGPoint(x: cx, y: y - rh), control: CGPoint(x: cx + rw * 0.95, y: y - rh * 0.85))
    path.move(to: CGPoint(x: cx, y: y - rh * 0.35))
    path.addLine(to: CGPoint(x: cx, y: y + rh * 0.72))
    path.move(to: CGPoint(x: cx - rw * 0.08, y: y + rh * 0.2))
    path.addQuadCurve(
        to: CGPoint(x: cx - rw * 0.62, y: y + rh * 0.28),
        control: CGPoint(x: cx - rw * 0.4, y: y + rh * 0.7)
    )
    path.move(to: CGPoint(x: cx + rw * 0.08, y: y + rh * 0.2))
    path.addQuadCurve(
        to: CGPoint(x: cx + rw * 0.62, y: y + rh * 0.28),
        control: CGPoint(x: cx + rw * 0.4, y: y + rh * 0.7)
    )
    return path
}

private func puppyMouth(cx: CGFloat, y: CGFloat, pose: FacePose, size: CGSize) -> Path {
    let smile = pose.mouthCurve
    let open = max(0, pose.mouthOpen)
    let half = size.width * (0.12 + max(0, smile) * 0.015)
    let lift = smile * 8
    let gap = size.width * 0.034
    var path = Path()
    path.move(to: CGPoint(x: cx - half, y: y - lift))
    path.addQuadCurve(
        to: CGPoint(x: cx - gap, y: y + 1),
        control: CGPoint(x: cx - half * 0.42, y: y + 11 + smile * 5 + open * 3)
    )
    path.move(to: CGPoint(x: cx + half, y: y - lift))
    path.addQuadCurve(
        to: CGPoint(x: cx + gap, y: y + 1),
        control: CGPoint(x: cx + half * 0.42, y: y + 11 + smile * 5 + open * 3)
    )
    return path
}

private func puppyTongue(cx: CGFloat, y: CGFloat, pose: FacePose, size: CGSize) -> Path {
    let open = max(0, pose.mouthOpen)
    let len = size.height * (0.085 + open * 0.05)
    let half = size.width * 0.034
    var path = Path()
    path.move(to: CGPoint(x: cx - half, y: y + 1))
    path.addLine(to: CGPoint(x: cx - half * 0.85, y: y + len * 0.48))
    path.addQuadCurve(
        to: CGPoint(x: cx + half * 0.85, y: y + len * 0.48),
        control: CGPoint(x: cx, y: y + len)
    )
    path.addLine(to: CGPoint(x: cx + half, y: y + 1))
    path.move(to: CGPoint(x: cx, y: y + 3))
    path.addQuadCurve(
        to: CGPoint(x: cx, y: y + len * 0.7),
        control: CGPoint(x: cx + half * 0.15, y: y + len * 0.35)
    )
    return path
}

private func puppyCheek(at origin: CGPoint, side: CGFloat, scale: CGFloat) -> Path {
    var path = Path()
    for index in 0..<3 {
        let drop = CGFloat(index) * scale * 0.016
        let start = CGPoint(x: origin.x, y: origin.y + drop)
        let end = CGPoint(x: origin.x + side * scale * 0.032, y: start.y + scale * 0.01)
        path.move(to: start)
        path.addLine(to: end)
    }
    return path
}

private func puppyChin(cx: CGFloat, y: CGFloat, side: CGFloat, scale: CGFloat) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: cx + side * scale * 0.05, y: y + scale * 0.02))
    path.addQuadCurve(
        to: CGPoint(x: cx + side * scale * 0.2, y: y + scale * 0.01),
        control: CGPoint(x: cx + side * scale * 0.16, y: y + scale * 0.07)
    )
    path.move(to: CGPoint(x: cx + side * scale * 0.09, y: y + scale * 0.015))
    path.addQuadCurve(
        to: CGPoint(x: cx + side * scale * 0.17, y: y - scale * 0.005),
        control: CGPoint(x: cx + side * scale * 0.15, y: y + scale * 0.045)
    )
    return path
}

private func drawGlasses(pose: FacePose, context: inout GraphicsContext, size: CGSize) {
    let inkWidth = max(1.7, size.width * 0.006)
    let cx = size.width * 0.5
    let bob = pose.bob
    let eyeY = size.height * 0.40 + bob
    let spread = size.width * 0.195
    let mouthY = size.height * 0.75 + bob
    let lensH = size.height * 0.25
    let browY = eyeY - lensH * 0.5 - size.height * 0.05
    ink(
        glassesBrow(midX: cx - spread, y: browY, lift: pose.browLift, pinch: pose.browPinch, bias: pose.browBias, side: -1, scale: size.width),
        width: inkWidth * 1.15, halo: 1.35, in: &context
    )
    ink(
        glassesBrow(midX: cx + spread, y: browY, lift: pose.browLift, pinch: pose.browPinch, bias: pose.browBias, side: 1, scale: size.width),
        width: inkWidth * 1.15, halo: 1.35, in: &context
    )
    drawGlassesEye(center: CGPoint(x: cx - spread, y: eyeY), pose: pose, size: size, side: -1, inkWidth: inkWidth, in: &context)
    drawGlassesEye(center: CGPoint(x: cx + spread, y: eyeY), pose: pose, size: size, side: 1, inkWidth: inkWidth, in: &context)
    ink(glassesFrames(cx: cx, eyeY: eyeY, spread: spread, lensH: lensH, size: size), width: inkWidth * 3.4, halo: 1.35, in: &context)
    ink(glassesNose(cx: cx, top: eyeY + lensH * 0.5 + size.height * 0.035, mouthY: mouthY), width: inkWidth * 0.85, halo: 1.25, in: &context)
    ink(
        mouth(cx: cx, y: mouthY, pose: pose, size: size, halfScale: 0.086, bowHeight: 5.4, lowerDrop: 13),
        width: inkWidth * 0.95, halo: 1.5, in: &context
    )
    driftingZ(cx: cx + size.width * 0.22, mouthY: mouthY, progress: pose.zzz, scale: 0.85, size: size, in: &context)
    driftingZ(cx: cx + size.width * 0.27, mouthY: mouthY - size.height * 0.03, progress: pose.zzz2, scale: 0.6, size: size, in: &context)
}

private func glassesBrow(
    midX: CGFloat,
    y: CGFloat,
    lift: CGFloat,
    pinch: CGFloat,
    bias: CGFloat,
    side: CGFloat,
    scale: CGFloat
) -> Path {
    let raise = lift * scale * 0.028
    let sideLift = bias * side * scale * 0.02
    let pinchDrop = max(0, pinch) * scale * 0.02
    let inner = CGPoint(
        x: midX - side * scale * 0.015,
        y: y + pinchDrop - raise * 0.2 - sideLift * 0.08
    )
    let outer = CGPoint(
        x: midX + side * scale * 0.105,
        y: y + scale * 0.01 - raise * 0.05 - sideLift
    )
    var path = Path()
    path.move(to: inner)
    path.addQuadCurve(
        to: outer,
        control: CGPoint(x: midX + side * scale * 0.04, y: y - scale * 0.012 - raise)
    )
    return path
}

private func glassesFrames(cx: CGFloat, eyeY: CGFloat, spread: CGFloat, lensH: CGFloat, size: CGSize) -> Path {
    let lensW = size.width * 0.3
    let corner = min(lensW, lensH) * 0.14
    var path = Path()
    for side: CGFloat in [-1, 1] {
        let origin = CGPoint(x: cx + side * spread - lensW / 2, y: eyeY - lensH / 2)
        path.addRoundedRect(
            in: CGRect(x: origin.x, y: origin.y, width: lensW, height: lensH),
            cornerSize: CGSize(width: corner, height: corner)
        )
        let hinge = CGPoint(x: cx + side * (spread + lensW / 2), y: eyeY - lensH * 0.16)
        path.move(to: hinge)
        path.addLine(to: CGPoint(x: hinge.x + side * size.width * 0.05, y: hinge.y + size.height * 0.008))
    }
    let bridgeY = eyeY + lensH * 0.04
    path.move(to: CGPoint(x: cx - spread + lensW / 2, y: bridgeY))
    path.addQuadCurve(
        to: CGPoint(x: cx + spread - lensW / 2, y: bridgeY),
        control: CGPoint(x: cx, y: bridgeY + lensH * 0.16)
    )
    return path
}

private func drawGlassesEye(
    center: CGPoint,
    pose: FacePose,
    size: CGSize,
    side: CGFloat,
    inkWidth: CGFloat,
    in context: inout GraphicsContext
) {
    let w = size.width * 0.09
    let open = min(1, max(0, pose.eyeOpen))
    let temporal = CGPoint(x: center.x + side * w, y: center.y - 1)
    let nasal = CGPoint(x: center.x - side * w * 0.9, y: center.y + 2)
    if open < 0.16 {
        var closed = Path()
        closed.move(to: temporal)
        closed.addQuadCurve(to: nasal, control: CGPoint(x: center.x, y: center.y + 4))
        ink(closed, width: inkWidth * 0.95, halo: 1.3, in: &context)
        return
    }
    let h = size.height * 0.07 * open
    let upper = CGPoint(x: center.x, y: center.y - h * 1.4)
    let lower = CGPoint(x: center.x, y: center.y + h * 1.12)
    var upperLid = Path()
    upperLid.move(to: temporal)
    upperLid.addQuadCurve(to: nasal, control: upper)
    var lowerLid = Path()
    lowerLid.move(to: nasal)
    lowerLid.addQuadCurve(to: temporal, control: lower)
    ink(lowerLid, width: inkWidth * 0.72, halo: 1.15, in: &context)
    let lookX = min(1, max(-1, pose.lookX))
    let lookY = min(1, max(-1, pose.lookY))
    let radius = min(w * 0.72, h * 0.95)
    if radius > 1.6 {
        let x = center.x + lookX * w * 0.16
        let y = center.y - lookY * h * 0.1
        var ring = Path()
        ring.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        ink(ring, width: max(1.2, size.width * 0.004), halo: 1.05, in: &context)
        gloss(CGPoint(x: x - radius * 0.32, y: y - radius * 0.32), radius: radius * 0.24, in: &context)
    }
    ink(upperLid, width: inkWidth * 1.05, halo: 1.35, in: &context)
    if open > 0.45 {
        var lashes = Path()
        for (t, length) in [(0.14, 0.18), (0.26, 0.13), (0.38, 0.09)] as [(CGFloat, CGFloat)] {
            let origin = pointOnQuad(t, temporal, upper, nasal)
            let ahead = pointOnQuad(min(0.96, t + 0.04), temporal, upper, nasal)
            let normal = outwardNormal(from: origin, to: ahead, side: side, fan: 0.7)
            let span = w * length
            lashes.move(to: origin)
            lashes.addLine(to: CGPoint(x: origin.x + normal.x * span, y: origin.y + normal.y * span))
        }
        ink(lashes, width: inkWidth * 0.62, halo: 1.05, in: &context)
    }
}

private func glassesNose(cx: CGFloat, top: CGFloat, mouthY: CGFloat) -> Path {
    let tipY = top + (mouthY - top) * 0.38
    var path = Path()
    path.move(to: CGPoint(x: cx, y: top))
    path.addLine(to: CGPoint(x: cx - 0.5, y: tipY))
    path.move(to: CGPoint(x: cx - 8, y: tipY - 1))
    path.addQuadCurve(to: CGPoint(x: cx - 1, y: tipY + 4), control: CGPoint(x: cx - 7, y: tipY + 5))
    path.move(to: CGPoint(x: cx + 1, y: tipY - 1))
    path.addQuadCurve(to: CGPoint(x: cx + 8, y: tipY + 3), control: CGPoint(x: cx + 7, y: tipY + 5))
    return path
}

private func driftingZ(
    cx: CGFloat,
    mouthY: CGFloat,
    progress: CGFloat,
    scale: CGFloat,
    size: CGSize,
    in context: inout GraphicsContext
) {
    guard progress > 0, progress < 1 else { return }
    let rise = progress * size.height * 0.18
    let alpha = sin(progress * .pi)
    let origin = CGPoint(
        x: cx + size.width * 0.14,
        y: mouthY - size.height * 0.06 - rise
    )
    ink(
        zed(origin: origin, size: size.width * 0.05 * scale),
        width: max(1.7, size.width * 0.007),
        alpha: alpha,
        in: &context
    )
}

private func zed(origin: CGPoint, size: CGFloat) -> Path {
    let w = size
    let h = size * 0.78
    var path = Path()
    path.move(to: CGPoint(x: origin.x, y: origin.y))
    path.addLine(to: CGPoint(x: origin.x + w, y: origin.y))
    path.addLine(to: CGPoint(x: origin.x, y: origin.y + h))
    path.addLine(to: CGPoint(x: origin.x + w, y: origin.y + h))
    return path
}

private func ink(_ path: Path, width: CGFloat, alpha: CGFloat = 1, halo: CGFloat = 2.2, in context: inout GraphicsContext) {
    let clamped = min(1, max(0, alpha))
    let shade = StrokeStyle(lineWidth: width + halo, lineCap: .round, lineJoin: .round)
    let core = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    context.stroke(path, with: .color(.black.opacity(0.55 * clamped)), style: shade)
    context.stroke(path, with: .color(Color(white: 0.97).opacity(clamped)), style: core)
}
