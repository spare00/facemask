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
            let inkWidth = max(2.4, size.width * 0.01)
            let cx = size.width * 0.5
            let bob = pose.bob
            let eyeY = size.height * 0.40 + bob
            let spread = size.width * 0.17
            let browY = eyeY - size.height * 0.09
            let mouthY = size.height * 0.70 + bob

            ink(
                brow(midX: cx - spread, y: browY, lift: pose.browLift, pinch: pose.browPinch, bias: pose.browBias, side: -1),
                width: inkWidth * 0.92,
                in: &context
            )
            ink(
                brow(midX: cx + spread, y: browY, lift: pose.browLift, pinch: pose.browPinch, bias: pose.browBias, side: 1),
                width: inkWidth * 0.92,
                in: &context
            )
            ink(nose(cx: cx, eyeY: eyeY, mouthY: mouthY), width: inkWidth * 0.9, in: &context)
            ink(mouth(cx: cx, y: mouthY, pose: pose, size: size), width: inkWidth, in: &context)
            driftingZ(cx: cx, mouthY: mouthY, progress: pose.zzz, scale: 1, size: size, in: &context)
            driftingZ(cx: cx + size.width * 0.045, mouthY: mouthY - size.height * 0.03, progress: pose.zzz2, scale: 0.72, size: size, in: &context)

            let leftEye = CGPoint(x: cx - spread, y: eyeY)
            let rightEye = CGPoint(x: cx + spread, y: eyeY)
            ink(eye(center: leftEye, pose: pose, size: size, outerSign: -1), width: inkWidth, in: &context)
            ink(eye(center: rightEye, pose: pose, size: size, outerSign: 1), width: inkWidth, in: &context)
            pupil(center: leftEye, pose: pose, size: size, in: &context)
            pupil(center: rightEye, pose: pose, size: size, in: &context)
        }
    }
}

struct FacePreview: View {
    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            column(.idle, "대기")
            column(.thinking, "생각 중")
            column(.speaking, "말하는 중")
            column(blinkPose, "깜빡임")
        }
        .padding(36)
        .background(Color(white: 0.46))
    }

    private var blinkPose: FacePose {
        var pose = FacePose.idle
        pose.eyeOpen = 0.04
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
    let raise = lift * 14
    let pinchDrop = max(0, pinch) * 11
    let pinchIn = max(0, pinch) * 5
    let outer = CGPoint(x: midX - dir * 30, y: y + 6 - raise * 0.28 - sideLift)
    let inner = CGPoint(
        x: midX + dir * 24 - dir * pinchIn,
        y: y - raise + pinchDrop - sideLift * 0.25
    )
    let control = CGPoint(
        x: midX - dir * 2,
        y: y - 7 - raise * 0.85 + pinchDrop * 0.25 - sideLift * 0.75
    )
    var path = Path()
    path.move(to: outer)
    path.addQuadCurve(to: inner, control: control)
    return path
}

private func eye(center: CGPoint, pose: FacePose, size: CGSize, outerSign: CGFloat) -> Path {
    let w = size.width * 0.092
    let open = min(1, max(0, pose.eyeOpen))
    let outer = CGPoint(x: center.x - outerSign * w, y: center.y - 1.5)
    let inner = CGPoint(x: center.x + outerSign * w, y: center.y + 1.5)
    var path = Path()
    path.move(to: outer)
    if open < 0.16 {
        path.addLine(to: inner)
        return path
    }
    let h = size.height * 0.05 * open
    path.addQuadCurve(to: inner, control: CGPoint(x: center.x, y: center.y - h))
    path.addQuadCurve(to: outer, control: CGPoint(x: center.x, y: center.y + h * 0.72))
    return path
}

private func pupil(center: CGPoint, pose: FacePose, size: CGSize, in context: inout GraphicsContext) {
    guard pose.eyeOpen > 0.38 else { return }
    let w = size.width * 0.092
    let h = size.height * 0.05 * pose.eyeOpen
    let lookX = min(1, max(-1, pose.lookX))
    let lookY = min(1, max(-1, pose.lookY))
    let x = center.x + lookX * w * 0.42
    let y = center.y - lookY * h * 0.68
    let r = size.width * 0.015
    let halo = CGRect(x: x - r - 1.1, y: y - r - 1.1, width: (r + 1.1) * 2, height: (r + 1.1) * 2)
    let core = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
    context.fill(Path(ellipseIn: halo), with: .color(.black.opacity(0.58)))
    context.fill(Path(ellipseIn: core), with: .color(Color(white: 0.97)))
}

private func nose(cx: CGFloat, eyeY: CGFloat, mouthY: CGFloat) -> Path {
    let top = CGPoint(x: cx, y: eyeY + 16)
    let bend = CGPoint(x: cx - 2, y: mouthY - 52)
    let tip = CGPoint(x: cx + 16, y: mouthY - 44)
    var path = Path()
    path.move(to: top)
    path.addQuadCurve(to: bend, control: CGPoint(x: cx - 7, y: eyeY + 36))
    path.addQuadCurve(to: tip, control: CGPoint(x: cx + 1, y: mouthY - 36))
    return path
}

private func mouth(cx: CGFloat, y: CGFloat, pose: FacePose, size: CGSize) -> Path {
    let half = size.width * 0.15
    let smile = pose.mouthCurve
    let open = max(0, pose.mouthOpen)
    let left = CGPoint(x: cx - half, y: y - smile * 14)
    let right = CGPoint(x: cx + half, y: y - smile * 14)
    var path = Path()
    path.move(to: left)
    path.addQuadCurve(
        to: right,
        control: CGPoint(x: cx, y: y + smile * 16 - open * 16)
    )
    if open > 0.08 {
        path.addQuadCurve(
            to: left,
            control: CGPoint(x: cx, y: y + smile * 4 + open * 34)
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

private func ink(_ path: Path, width: CGFloat, alpha: CGFloat = 1, in context: inout GraphicsContext) {
    let clamped = min(1, max(0, alpha))
    let halo = StrokeStyle(lineWidth: width + 2.4, lineCap: .round, lineJoin: .round)
    let core = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    context.stroke(path, with: .color(.black.opacity(0.58 * clamped)), style: halo)
    context.stroke(path, with: .color(Color(white: 0.97).opacity(clamped)), style: core)
}
