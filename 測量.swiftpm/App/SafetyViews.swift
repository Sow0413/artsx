import SwiftUI
import SurveyCore
#if canImport(PhotosUI)
import PhotosUI
#endif

struct CrewGlyph: Equatable {
    var id: String
    var name: String
    var role: CrewRole
    var point: PlanarPoint
    var radius: Double?
    var level: ProximityLevel
}

struct SafetyBanner: View {
    @ObservedObject var crew: CrewController
    var onHiyari: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(crew.notice)
                    .font(.system(size: 13, weight: .heavy))
                Text(crew.statusLine)
                    .font(.system(size: crew.worst == .clear ? 15 : 22, weight: .black))
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onHiyari {
                Button("ヒヤリ", action: onHiyari)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(crew.worst == .alarm ? Color.black.opacity(0.35) : SurveyColor.red)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("ヒヤリ")
            }
        }
        .foregroundStyle(crew.worst == .alarm ? Color.white : SurveyColor.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(fill)
        .accessibilityElement(children: .contain)
    }

    private var fill: Color {
        switch crew.worst {
        case .alarm: return SurveyColor.red
        case .caution: return SurveyColor.yellow
        case .clear: return SurveyColor.card.opacity(0.94)
        }
    }
}

struct SafetyWash: View {
    var level: ProximityLevel

    var body: some View {
        fill
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var fill: Color {
        switch level {
        case .alarm: return SurveyColor.red.opacity(0.33)
        case .caution: return SurveyColor.yellow.opacity(0.2)
        case .clear: return Color.clear
        }
    }
}

struct ThreatRim: View {
    var cues: [ThreatCue]
    var fall: FallCue?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ForEach(Array(cues.enumerated()), id: \.element.id) { index, cue in
                let point = rim(cue.relativeDegrees + Double(index) * 8, in: size)
                let length = 28 + CGFloat(cue.closeness) * 48
                ThreatArrow(closeness: cue.closeness)
                    .frame(width: length, height: length)
                    .rotationEffect(.degrees(cue.relativeDegrees))
                    .position(point)
            }
            if let fall {
                let point = rim(fall.relativeDegrees, in: size)
                ThreatArrow(closeness: 1)
                    .frame(width: 96, height: 96)
                    .rotationEffect(.degrees(fall.relativeDegrees))
                    .position(point)
                    .accessibilityLabel(fall.speech)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func rim(_ degrees: Double, in size: CGSize) -> CGPoint {
        let turn = degrees * .pi / 180
        let inset: CGFloat = 34
        return CGPoint(
            x: size.width / 2 + CGFloat(sin(turn)) * (size.width / 2 - inset),
            y: size.height / 2 - CGFloat(cos(turn)) * (size.height / 2 - inset)
        )
    }
}

struct ThreatArrow: View {
    var closeness: Double

    var body: some View {
        let red = 0.45 + closeness * 0.55
        let green = 0.75 * (1 - closeness)
        CrewChevron()
            .fill(Color(red: red, green: green, blue: 0.08))
            .overlay(CrewChevron().stroke(Color.white, lineWidth: 2))
    }
}

struct CrewChevron: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + 2))
        path.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.maxY - 2))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + 2, y: rect.maxY - 2))
        path.closeSubpath()
        return path
    }
}

struct CrewRadar: View {
    var marks: [CrewMark]
    var selfRole: CrewRole
    var selfRadius: Double
    var cautionMeters: Double
    var facingDegrees: Double?

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let farthest = marks.map { self.span($0.eastMeters, $0.northMeters) + ($0.workRadiusMeters ?? 0) }.max() ?? 0
            let spanMeters = max(cautionMeters, selfRole == .machine ? selfRadius : 0, farthest, 20)
            let scale = (min(size.width, size.height) * 0.42) / spanMeters
            func place(_ east: Double, _ north: Double) -> CGPoint {
                let turned = self.screen(east: east, north: north)
                return CGPoint(x: center.x + CGFloat(turned.right * scale), y: center.y - CGFloat(turned.forward * scale))
            }
            func ring(_ meters: Double, color: Color) {
                let pixels = CGFloat(meters * scale)
                let rect = CGRect(x: center.x - pixels, y: center.y - pixels, width: pixels * 2, height: pixels * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 2)
            }
            ring(cautionMeters, color: SurveyColor.yellow.opacity(0.9))
            if selfRole == .machine {
                ring(selfRadius, color: SurveyColor.amber)
            }
            for mark in marks {
                let origin = place(mark.eastMeters, mark.northMeters)
                if mark.role == .machine, let radius = mark.workRadiusMeters, radius > 0 {
                    let pixels = CGFloat(radius * scale)
                    let rect = CGRect(x: origin.x - pixels, y: origin.y - pixels, width: pixels * 2, height: pixels * 2)
                    context.stroke(Path(ellipseIn: rect), with: .color(color(mark.level)), lineWidth: 2)
                }
                let dot = CGRect(x: origin.x - 6, y: origin.y - 6, width: 12, height: 12)
                context.fill(Path(ellipseIn: dot), with: .color(color(mark.level)))
            }
            let me = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: me), with: .color(Color.white))
        }
        .frame(height: 72)
        .accessibilityLabel("相手の方向。上は\(facingDegrees == nil ? "北" : "前")。\(SafetyNotice.text)")
    }

    private func screen(east: Double, north: Double) -> (right: Double, forward: Double) {
        guard let facingDegrees else { return (east, north) }
        let turn = facingDegrees * .pi / 180
        let cosine = cos(turn)
        let sine = sin(turn)
        return (east * cosine - north * sine, north * cosine + east * sine)
    }

    private func span(_ east: Double, _ north: Double) -> Double {
        (east * east + north * north).squareRoot()
    }

    private func color(_ level: ProximityLevel) -> Color {
        switch level {
        case .alarm: return SurveyColor.red
        case .caution: return SurveyColor.yellow
        case .clear: return SurveyColor.blue
        }
    }
}

struct IncidentTray: View {
    @ObservedObject var field: FieldModel
    #if canImport(PhotosUI)
    @State private var photo: PhotosPickerItem?
    #endif

    var body: some View {
        if field.incidentOpen || field.incidentNote != nil {
            VStack(alignment: .leading, spacing: 6) {
                if let note = field.incidentNote {
                    Text(note)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(SurveyColor.amber)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                if field.incidentOpen {
                    HStack(spacing: 8) {
                        photoControl
                        Button(field.incidentRecordingMemo ? "録音中" : "音声メモ") {
                            field.toggleIncidentMemo()
                        }
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(field.incidentRecordingMemo ? SurveyColor.red : SurveyColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var photoControl: some View {
        #if canImport(PhotosUI)
        PhotosPicker(selection: $photo, matching: .images) {
            Text("写真")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(SurveyColor.card)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run { field.attachIncidentPhoto(data) }
                }
            }
        }
        #else
        EmptyView()
        #endif
    }
}
