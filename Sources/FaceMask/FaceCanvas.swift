import SwiftUI

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

    var body: some View {
        Canvas { context, size in
            let inkWidth = max(2.05, size.width * 0.0082)
            let cx = size.width * 0.5
            let bob = pose.bob
            let eyeY = size.height * 0.37 + bob
            let spread = size.width * 0.156
            let browY = eyeY - size.height * 0.122
            let mouthY = size.height * 0.63 + bob

            ink(
                brow(midX: cx - spread, y: browY, lift: pose.browLift, pinch: pose.browPinch, bias: pose.browBias, side: -1),
                width: inkWidth * 0.62,
                halo: 1.5,
                in: &context
            )
            ink(
                brow(midX: cx + spread, y: browY, lift: pose.browLift, pinch: pose.browPinch, bias: pose.browBias, side: 1),
                width: inkWidth * 0.62,
                halo: 1.5,
                in: &context
            )
            ink(nose(cx: cx, eyeY: eyeY, mouthY: mouthY), width: inkWidth * 0.68, halo: 1.5, in: &context)
            ink(mouth(cx: cx, y: mouthY, pose: pose, size: size), width: inkWidth * 0.9, halo: 1.8, in: &context)
            driftingZ(cx: cx, mouthY: mouthY, progress: pose.zzz, scale: 1, size: size, in: &context)
            driftingZ(cx: cx + size.width * 0.045, mouthY: mouthY - size.height * 0.03, progress: pose.zzz2, scale: 0.72, size: size, in: &context)

            let leftEye = CGPoint(x: cx - spread, y: eyeY)
            let rightEye = CGPoint(x: cx + spread, y: eyeY)
            let left = eye(center: leftEye, pose: pose, size: size, side: -1)
            let right = eye(center: rightEye, pose: pose, size: size, side: 1)
            ink(left.outline, width: inkWidth * 0.92, halo: 1.8, in: &context)
            ink(right.outline, width: inkWidth * 0.92, halo: 1.8, in: &context)
            ink(lashes(shape: left, side: -1, scale: size.width), width: inkWidth * 0.46, halo: 1.05, in: &context)
            ink(lashes(shape: right, side: 1, scale: size.width), width: inkWidth * 0.46, halo: 1.05, in: &context)
            iris(center: leftEye, pose: pose, shape: left, size: size, in: &context)
            iris(center: rightEye, pose: pose, shape: right, size: size, in: &context)
        }
    }
}

struct FacePreview: View {
    var body: some View {
        VStack(spacing: 28) {
            HStack(alignment: .top, spacing: 28) {
                column(.idle, "대기")
                column(.thinking, "생각 중")
                column(.speaking, "말하는 중")
                column(blinkPose, "깜빡임")
            }
            HStack(alignment: .top, spacing: 28) {
                column(yawnPose, "하품")
                column(sleepPose, "잠")
                column(skepticPose, "의심")
                column(concernPose, "걱정")
            }
        }
        .padding(36)
        .background(Color(white: 0.46))
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

    private var sleepPose: FacePose {
        var pose = FacePose.idle
        pose.eyeOpen = 0.045
        pose.mouthOpen = 0.08
        pose.mouthCurve = 0.06
        pose.browLift = -0.16
        pose.browPinch = 0.06
        pose.zzz = 0.45
        return pose
    }

    private var skepticPose: FacePose {
        var pose = FacePose.idle
        pose.browLift = 0.16
        pose.browPinch = 0.08
        pose.browBias = 0.95
        pose.mouthCurve = 0.05
        return pose
    }

    private var concernPose: FacePose {
        var pose = FacePose.idle
        pose.browLift = -0.12
        pose.browPinch = 0.92
        pose.mouthCurve = -0.16
        return pose
    }

    private func column(_ pose: FacePose, _ title: String) -> some View {
        VStack(spacing: 8) {
            FaceCanvas(pose: pose)
                .frame(width: FaceLayout.width, height: FaceLayout.height)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.black)
        }
    }
}

private struct EyeShape {
    var outline: Path
    var temporal: CGPoint
    var upper: CGPoint
    var nasal: CGPoint
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
    side: CGFloat
) -> Path {
    let dir: CGFloat = side < 0 ? 1 : -1
    let sideLift = bias * side * 12
    let raise = lift * 13
    let pinchDrop = max(0, pinch) * 11
    let pinchIn = max(0, pinch) * 5
    let inner = CGPoint(
        x: midX + dir * 14 - dir * pinchIn,
        y: y + 5 - raise * 0.28 + pinchDrop - sideLift * 0.1
    )
    let tail = CGPoint(
        x: midX - dir * 38,
        y: y + 8 - raise * 0.1 - sideLift * 0.9
    )
    var path = Path()
    path.move(to: inner)
    path.addCurve(
        to: tail,
        control1: CGPoint(
            x: midX + dir * 1,
            y: y - 9 - raise - sideLift * 0.4 + pinchDrop * 0.15
        ),
        control2: CGPoint(
            x: midX - dir * 22,
            y: y - 4 - raise * 0.45 - sideLift * 0.75
        )
    )
    return path
}

private func eye(center: CGPoint, pose: FacePose, size: CGSize, side: CGFloat) -> EyeShape {
    let w = size.width * 0.108
    let open = min(1, max(0, pose.eyeOpen))
    let tilt: CGFloat = 3.6
    let temporal = CGPoint(x: center.x + side * w, y: center.y - tilt)
    let nasal = CGPoint(x: center.x - side * w * 0.86, y: center.y + tilt * 0.12)
    var path = Path()
    path.move(to: temporal)
    if open < 0.16 {
        path.addQuadCurve(to: nasal, control: CGPoint(x: center.x - side * w * 0.05, y: center.y + 6))
        return EyeShape(outline: path, temporal: temporal, upper: center, nasal: nasal, open: open, h: 0, w: w)
    }
    let h = size.height * 0.072 * open
    let upper = CGPoint(x: center.x - side * w * 0.08, y: center.y - h * 1.16)
    let lower = CGPoint(x: center.x + side * w * 0.04, y: center.y + h * 0.34)
    path.addQuadCurve(to: nasal, control: upper)
    path.addQuadCurve(to: temporal, control: lower)
    return EyeShape(outline: path, temporal: temporal, upper: upper, nasal: nasal, open: open, h: h, w: w)
}

private func lashes(shape: EyeShape, side: CGFloat, scale: CGFloat) -> Path {
    guard shape.open > 0.34 else { return Path() }
    var path = Path()
    let marks: [(CGFloat, CGFloat)] = [(0.04, 1), (0.2, 0.72), (0.38, 0.48), (0.56, 0.28)]
    for (t, weight) in marks {
        let origin = pointOnQuad(t, shape.temporal, shape.upper, shape.nasal)
        let ahead = pointOnQuad(min(0.98, t + 0.04), shape.temporal, shape.upper, shape.nasal)
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
        nx += side * (0.45 + (1 - t) * 1.15)
        let normal = max(0.001, hypot(nx, ny))
        nx /= normal
        ny /= normal
        let length = scale * 0.032 * weight * min(1, shape.open / 0.78)
        let tip = CGPoint(x: origin.x + nx * length, y: origin.y + ny * length)
        let bend = CGPoint(
            x: origin.x + nx * length * 0.48 + side * length * 0.42,
            y: origin.y + ny * length * 0.4
        )
        path.move(to: origin)
        path.addQuadCurve(to: tip, control: bend)
    }
    return path
}

private func pointOnQuad(_ t: CGFloat, _ a: CGPoint, _ c: CGPoint, _ b: CGPoint) -> CGPoint {
    let u = 1 - t
    return CGPoint(
        x: u * u * a.x + 2 * u * t * c.x + t * t * b.x,
        y: u * u * a.y + 2 * u * t * c.y + t * t * b.y
    )
}

private func iris(center: CGPoint, pose: FacePose, shape: EyeShape, size: CGSize, in context: inout GraphicsContext) {
    guard shape.open > 0.36, shape.h > 2 else { return }
    let lookX = min(1, max(-1, pose.lookX))
    let lookY = min(1, max(-1, pose.lookY))
    let x = center.x + lookX * shape.w * 0.2
    let y = center.y - lookY * shape.h * 0.28 + shape.h * 0.04
    let radius = min(size.width * 0.02, shape.h * 0.56)
    guard radius > 1.3 else { return }
    var ring = Path()
    ring.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    ink(ring, width: max(1.15, size.width * 0.0042), halo: 1.25, in: &context)
    let pupil = radius * 0.4
    let haloR = pupil + 0.9
    context.fill(
        Path(ellipseIn: CGRect(x: x - haloR, y: y - haloR, width: haloR * 2, height: haloR * 2)),
        with: .color(.black.opacity(0.55))
    )
    context.fill(
        Path(ellipseIn: CGRect(x: x - pupil, y: y - pupil, width: pupil * 2, height: pupil * 2)),
        with: .color(Color(white: 0.97))
    )
    let glint = radius * 0.16
    let gx = x - radius * 0.42
    let gy = y - radius * 0.4
    context.fill(
        Path(ellipseIn: CGRect(x: gx - glint, y: gy - glint, width: glint * 2, height: glint * 2)),
        with: .color(Color(white: 0.97))
    )
}

private func nose(cx: CGFloat, eyeY: CGFloat, mouthY: CGFloat) -> Path {
    let span = mouthY - eyeY
    let top = CGPoint(x: cx, y: eyeY + span * 0.26)
    let tip = CGPoint(x: cx + 1, y: eyeY + span * 0.46)
    var path = Path()
    path.move(to: top)
    path.addQuadCurve(to: tip, control: CGPoint(x: cx - 1.5, y: eyeY + span * 0.37))
    path.addQuadCurve(
        to: CGPoint(x: cx - 4, y: tip.y + 2.5),
        control: CGPoint(x: cx + 3, y: tip.y + 4)
    )
    return path
}

private func mouth(cx: CGFloat, y: CGFloat, pose: FacePose, size: CGSize) -> Path {
    let half = size.width * 0.08
    let smile = pose.mouthCurve
    let open = max(0, pose.mouthOpen)
    let cornerLift = smile * 10
    let bow = 4.6 * (1 - min(1, open) * 0.7)
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
        control: CGPoint(x: cx, y: y + 11 + open * 32 - smile * 2)
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
