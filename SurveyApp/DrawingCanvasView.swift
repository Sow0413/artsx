import SwiftUI
import SurveyCore

struct DrawingCanvasView: View {
    let document: DrawingDocument?
    @Binding var camera: DrawingCamera
    let user: UserOnDrawing?
    let tone: AccuracyTone
    let accuracyText: String
    let highlight: PlanarPoint?
    let reachCenter: PlanarPoint?
    let reachRadius: Double?
    let reachRanges: [ReachRange]
    var showsMap = false
    var crew: [CrewGlyph] = []
    var onTap: (PlanarPoint, Double) -> Void
    var onLongPress: ((PlanarPoint, Double) -> Void)? = nil
    var onFit: (CGSize) -> Void

    @State private var magnifyBase: Double?
    @State private var rotationBase: Double?
    @State private var dragCenter: (x: Double, y: Double)?
    @Environment(\.surveyOutdoor) private var outdoor

    var body: some View {
        let outdoor = outdoor
        GeometryReader { geo in
            let size = geo.size
            Canvas { context, canvasSize in
                draw(in: &context, size: canvasSize, outdoor: outdoor)
            }
            .gesture(drag)
            .simultaneousGesture(magnify)
            .simultaneousGesture(rotate)
            .contextMenu {
                Button("全体を表示") { camera.fittedID = nil }
                Button("回転を戻す") { camera.rotationDegrees = 0 }
            }
            .onTapGesture { location in
                let tolerance = 22 / max(camera.pointsPerUnit, 1e-9)
                onTap(drawingPoint(from: location, size: size), tolerance)
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45, maximumDistance: 16)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onEnded { value in
                        guard case let .second(true, drag?) = value else { return }
                        let tolerance = 22 / max(camera.pointsPerUnit, 1e-9)
                        onLongPress?(drawingPoint(from: drag.location, size: size), tolerance)
                    }
            )
            .overlay(alignment: .bottomTrailing) {
                zoomButtons
                    .padding(8)
            }
            .background(showsMap ? Color.clear : SurveyColor.background)
            .onAppear { onFit(size) }
            .onChange(of: camera.fittedID) { _, _ in onFit(size) }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if dragCenter == nil {
                    dragCenter = (camera.centerX, camera.centerY)
                }
                guard let dragCenter else { return }
                let shifted = movedCenter(from: dragCenter, translation: value.translation)
                camera.centerX = shifted.x
                camera.centerY = shifted.y
            }
            .onEnded { _ in
                dragCenter = nil
            }
    }

    private var magnify: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if magnifyBase == nil { magnifyBase = camera.pointsPerUnit }
                camera.pointsPerUnit = min(1e6, max(1e-8, (magnifyBase ?? 1) * value))
            }
            .onEnded { _ in magnifyBase = nil }
    }

    private var rotate: some Gesture {
        RotationGesture()
            .onChanged { value in
                if rotationBase == nil { rotationBase = camera.rotationDegrees }
                camera.rotationDegrees = (rotationBase ?? 0) + value.degrees
            }
            .onEnded { _ in rotationBase = nil }
    }

    private var zoomButtons: some View {
        VStack(spacing: 4) {
            canvasButton("＋") { camera.pointsPerUnit *= 1.25 }
            canvasButton("−") { camera.pointsPerUnit /= 1.25 }
            canvasButton("90°") { camera.rotationDegrees += 90 }
        }
    }

    private func canvasButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(SurveyType(title == "90°" ? 13 : 17, .heavy))
                .frame(width: 44, height: 44)
                .background(SurveyColor.card)
                .foregroundStyle(SurveyColor.text)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(SurveyColor.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, outdoor: Bool) {
        guard let document else { return }
        let query = visibleBounds(size: size, document: document)
        let batch = DrawingLOD.batch(document: document, view: query, pointsPerUnit: camera.pointsPerUnit)
        for stroke in batch.strokes {
            guard let first = stroke.points.first else { continue }
            var path = Path()
            path.move(to: screen(first, size: size))
            for point in stroke.points.dropFirst() {
                path.addLine(to: screen(point, size: size))
            }
            let color = featureColor(red: stroke.red, green: stroke.green, blue: stroke.blue, outdoor: outdoor)
            let width = CGFloat(min(DrawingStroke.maximumPoints, max(DrawingStroke.minimumPoints, stroke.width)))
            if showsMap {
                context.stroke(path, with: .color(.white.opacity(0.9)), lineWidth: width + 1.5)
            }
            context.stroke(path, with: .color(color), lineWidth: width)
        }
        for mark in batch.points {
            let origin = screen(mark.point, size: size)
            let rect = CGRect(x: origin.x - 2, y: origin.y - 2, width: 4, height: 4)
            let color = featureColor(red: mark.red, green: mark.green, blue: mark.blue, outdoor: outdoor)
            if showsMap {
                let halo = CGRect(x: origin.x - 3.5, y: origin.y - 3.5, width: 7, height: 7)
                context.fill(Path(ellipseIn: halo), with: .color(.white.opacity(0.9)))
            }
            context.fill(Path(rect), with: .color(color))
        }
        for label in batch.labels where label.height * camera.pointsPerUnit >= 8 {
            let color = featureColor(red: label.red, green: label.green, blue: label.blue, outdoor: outdoor)
            context.draw(
                Text(label.text).font(SurveyType(12, .semibold)).foregroundStyle(color),
                at: screen(label.origin, size: size),
                anchor: .bottomLeading
            )
        }
        for range in reachRanges where range.points.count >= 2 {
            var path = Path()
            path.move(to: screen(range.points[0], size: size))
            for point in range.points.dropFirst() {
                path.addLine(to: screen(point, size: size))
            }
            context.stroke(path, with: .color(reachColor(range.coverage)), lineWidth: 3)
        }
        if let reachCenter, let reachRadius, reachRadius > 0 {
            let center = screen(reachCenter, size: size)
            let pixels = CGFloat(reachRadius * camera.pointsPerUnit)
            let circle = Path(ellipseIn: CGRect(x: center.x - pixels, y: center.y - pixels, width: pixels * 2, height: pixels * 2))
            let coverage = MachineReach.worst(reachRanges.map(\.coverage))
            context.stroke(circle, with: .color(reachColor(coverage)), lineWidth: SurveyColor.stroke)
        }
        if let user {
            let center = screen(user.point, size: size)
            let radius = max(8, CGFloat(user.accuracyRadius * camera.pointsPerUnit))
            let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.stroke(circle, with: .color(tone.mark), lineWidth: SurveyColor.stroke)
            let dot = Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14))
            context.fill(Path(ellipseIn: CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)), with: .color(.white))
            context.fill(dot, with: .color(tone.mark))
            context.draw(
                Text(accuracyText).font(SurveyType(12, .heavy)).foregroundStyle(tone.tint),
                at: CGPoint(x: center.x + 14, y: center.y - 16),
                anchor: .topLeading
            )
        }
        for glyph in crew {
            let center = screen(glyph.point, size: size)
            if glyph.role == .machine, let radius = glyph.radius, radius > 0 {
                let pixels = CGFloat(radius * camera.pointsPerUnit)
                let circle = Path(ellipseIn: CGRect(x: center.x - pixels, y: center.y - pixels, width: pixels * 2, height: pixels * 2))
                context.stroke(circle, with: .color(crewColor(glyph.level)), lineWidth: 2.5)
            }
            let dot = Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12))
            context.fill(dot, with: .color(crewColor(glyph.level)))
            context.draw(
                Text(glyph.name).font(SurveyType(11, .heavy)).foregroundStyle(crewColor(glyph.level)),
                at: CGPoint(x: center.x + 10, y: center.y - 12),
                anchor: .bottomLeading
            )
        }
        if let highlight {
            let center = screen(highlight, size: size)
            let mark = Path(ellipseIn: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16))
            context.stroke(mark, with: .color(reachColor(coverageOfHighlight(highlight))), lineWidth: 3)
        }
    }

    /// 紙の黒（SXF の白）だけ、明るい画面と地図の上では細い黒にする。等高線の灰や赤青はそのまま。
    private func featureColor(red: Double, green: Double, blue: Double, outdoor: Bool) -> Color {
        let paper = red > 0.92 && green > 0.92 && blue > 0.92
        if paper && (outdoor || showsMap) {
            return Color(red: 0.16, green: 0.17, blue: 0.18)
        }
        return Color(red: red, green: green, blue: blue)
    }

    private func coverageOfHighlight(_ point: PlanarPoint) -> ReachCoverage? {
        guard let reachCenter, let reachRadius, reachRadius > 0 else { return nil }
        return MachineReach.call(distanceMeters: point.distance(to: reachCenter), radiusMeters: reachRadius)?.coverage
    }

    private func crewColor(_ level: ProximityLevel) -> Color {
        switch level {
        case .alarm: return SurveyColor.red
        case .caution: return SurveyColor.yellow
        case .clear: return SurveyColor.blue
        }
    }

    private func reachColor(_ coverage: ReachCoverage?) -> Color {
        switch coverage {
        case .inside, .onRadius: return SurveyColor.green
        case .partial: return SurveyColor.yellow
        case .outside: return SurveyColor.red
        case nil: return SurveyColor.amber
        }
    }

    private func visibleBounds(size: CGSize, document: DrawingDocument) -> DrawingBounds {
        let corners = camera.viewCorners(size: size)
        return DrawingBounds(enclosing: corners).padded(max(document.bounds.width, document.bounds.height, 1) * 0.02)
    }

    private func screen(_ point: PlanarPoint, size: CGSize) -> CGPoint {
        camera.screen(point, size: size)
    }

    private func drawingPoint(from location: CGPoint, size: CGSize) -> PlanarPoint {
        camera.drawingPoint(from: location, size: size)
    }

    private func movedCenter(from start: (x: Double, y: Double), translation: CGSize) -> (x: Double, y: Double) {
        camera.movedCenter(from: start, translation: translation)
    }
}

extension DrawingCamera {
    func screen(_ point: PlanarPoint, size: CGSize) -> CGPoint {
        let dx = point.x - centerX
        let dy = point.y - centerY
        let radians = rotationDegrees * .pi / 180
        let rx = dx * cos(radians) - dy * sin(radians)
        let ry = dx * sin(radians) + dy * cos(radians)
        return CGPoint(
            x: size.width / 2 + CGFloat(rx * pointsPerUnit),
            y: size.height / 2 - CGFloat(ry * pointsPerUnit)
        )
    }

    func drawingPoint(from location: CGPoint, size: CGSize) -> PlanarPoint {
        let scale = max(pointsPerUnit, 1e-9)
        let rx = Double(location.x - size.width / 2) / scale
        let ry = -Double(location.y - size.height / 2) / scale
        let radians = rotationDegrees * .pi / 180
        let dx = cos(radians) * rx + sin(radians) * ry
        let dy = -sin(radians) * rx + cos(radians) * ry
        return PlanarPoint(x: centerX + dx, y: centerY + dy)
    }

    func movedCenter(from start: (x: Double, y: Double), translation: CGSize) -> (x: Double, y: Double) {
        let scale = max(pointsPerUnit, 1e-9)
        let rx = -Double(translation.width) / scale
        let ry = Double(translation.height) / scale
        let radians = rotationDegrees * .pi / 180
        let dx = cos(radians) * rx + sin(radians) * ry
        let dy = -sin(radians) * rx + cos(radians) * ry
        return (start.x + dx, start.y + dy)
    }

    func viewCorners(size: CGSize) -> [PlanarPoint] {
        [
            CGPoint(x: 0, y: 0),
            CGPoint(x: size.width, y: 0),
            CGPoint(x: 0, y: size.height),
            CGPoint(x: size.width, y: size.height)
        ].map { drawingPoint(from: $0, size: size) }
    }
}
