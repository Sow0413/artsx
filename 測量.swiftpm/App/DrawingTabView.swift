import SwiftUI
import SurveyCore
import UniformTypeIdentifiers

struct DrawingTabView: View {
    @ObservedObject var field: FieldModel
    @ObservedObject var drawing: DrawingSession
    @State private var importing = false
    @State private var projectName = ""
    @State private var recordName = "起点"

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= 720 {
                HStack(spacing: 0) {
                    canvas.frame(maxWidth: .infinity, maxHeight: .infinity)
                    controls.frame(width: min(380, geo.size.width * 0.4))
                }
            } else {
                VStack(spacing: 0) {
                    canvas.frame(height: max(260, geo.size.height * 0.46))
                    controls
                }
            }
        }
        .background(SurveyColor.background)
        .fileImporter(isPresented: $importing, allowedContentTypes: [dxfType]) { result in
            switch result {
            case let .success(url):
                guard let data = readSecurityScoped(url) else {
                    drawing.report("ファイルを読めませんでした。")
                    return
                }
                drawing.importFile(data: data, fileName: url.lastPathComponent)
            case .failure:
                drawing.report("ファイルを読めませんでした。")
            }
        }
    }

    private var canvas: some View {
        ZStack {
            DrawingCanvasView(
                document: drawing.document,
                camera: $drawing.camera,
                user: userOnDrawing,
                tone: field.badge.tone,
                accuracyText: accuracyText,
                highlight: highlight,
                onTap: { point, tolerance in
                    drawing.takeDrawingTap(point, tolerance: tolerance)
                },
                onFit: { drawing.fit(in: $0) }
            )
            if drawing.document == nil {
                Text(drawing.project == nil ? "プロジェクトを作って、DXF を読み込みます。" : "DXF を読み込むと、ここに図面が出ます。")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .multilineTextAlignment(.center)
                    .padding(24)
            }
        }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                projectSection
                if let message = drawing.message {
                    Text(message)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SurveyColor.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let warning = drawing.warning?.message {
                    Text(warning)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(SurveyColor.amber)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if drawing.project != nil {
                    drawingSection
                    alignmentSection
                    inspectionSection
                }
            }
            .padding(12)
        }
        .background(SurveyColor.bar)
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("プロジェクト")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(SurveyColor.muted)
            if drawing.projects.isEmpty {
                Text("まだありません。")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SurveyColor.text)
            } else {
                Picker("プロジェクト", selection: projectBinding) {
                    Text("選ぶ").tag(Optional<String>.none)
                    ForEach(drawing.projects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(SurveyColor.text)
            }
            HStack {
                TextField("新しい名前", text: $projectName)
                    .textFieldStyle(.roundedBorder)
                Button("作る") {
                    drawing.createProject(named: projectName)
                    projectName = ""
                }
                .buttonStyle(SurveyPlainButton())
            }
            if drawing.project != nil {
                HStack {
                    TextField("記録の名前", text: $recordName)
                        .textFieldStyle(.roundedBorder)
                    Button("下見を記録") {
                        drawing.addFieldRecord(date: todayString(), kind: "下見", name: recordName)
                    }
                    .buttonStyle(SurveyPlainButton())
                }
            }
        }
    }

    private var drawingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(drawing.fileName ?? "図面なし")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(SurveyColor.text)
                    .lineLimit(1)
                Spacer()
                Button("DXF を読む") { importing = true }
                    .buttonStyle(SurveyPlainButton())
            }
            if let document = drawing.document, !document.unsupportedSummary.isEmpty {
                Text("読めない要素: \(document.unsupportedSummary)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SurveyColor.yellow)
            }
            if let unit = drawing.document?.unitWarning {
                Text(unit)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SurveyColor.yellow)
            }
            if drawing.overlayCapped {
                Text("線が多すぎるので、地図への重ねは途中までです。図面の画面は、見えている範囲だけ描きます。")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SurveyColor.muted)
            }
            Picker("系", selection: zoneBinding) {
                ForEach(1...19, id: \.self) { number in
                    Text("\(number)系").tag(number)
                }
            }
            .pickerStyle(.menu)
            .tint(SurveyColor.text)
            Picker("軸", selection: axisBinding) {
                ForEach(DrawingAxis.allCases, id: \.self) { axis in
                    Text(axis.label).tag(axis)
                }
            }
            .pickerStyle(.menu)
            .tint(SurveyColor.text)
            if let layers = drawing.document?.layers, !layers.isEmpty {
                DisclosureGroup("レイヤ \(layers.filter(\.isVisible).count)/\(layers.count)") {
                    ForEach(layers) { layer in
                        Toggle(layer.name, isOn: layerBinding(layer))
                            .font(.system(size: 15, weight: .semibold))
                            .tint(SurveyColor.amber)
                    }
                }
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(SurveyColor.text)
            }
            Button("図面全体") {
                drawing.showWholeDrawing()
            }
            .buttonStyle(SurveyPlainButton())
            if let suggestion = drawing.suggestion {
                suggestionBlock(suggestion)
            } else if let warning = drawing.warning, !warning.candidates.isEmpty, warning.message != nil {
                candidateButtons(warning.candidates, title: "近くに載る系", applyAxis: true)
            }
        }
    }

    private var alignmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("地図に合わせる")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(SurveyColor.text)
            Text("図面の点と、地図・現在地・座標簿の点を2組以上対応づけます。3組以上は点ごとの残差を出します。")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SurveyColor.muted)
            Toggle("縮尺を 1 に固定（図面の 1 が 1 m のとき）", isOn: lockBinding)
                .font(.system(size: 14, weight: .semibold))
                .tint(SurveyColor.amber)
            if drawing.pick == .drawingVertex {
                Text("図面の点をタップしてください。")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(SurveyColor.amber)
            }
            if drawing.pending != nil {
                Text("対応する場所を選んでください。")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(SurveyColor.amber)
            }
            HStack {
                Button(drawing.pick == .drawingVertex ? "点の選択をやめる" : "図面の点") {
                    if drawing.pick == .drawingVertex {
                        drawing.cancelPick()
                    } else {
                        drawing.beginVertexPick()
                    }
                }
                .buttonStyle(SurveyPlainButton())
                Button("地図") { field.beginDrawingMapPick() }
                    .buttonStyle(SurveyPlainButton())
                Button("現在地") { useCurrentPosition() }
                    .buttonStyle(SurveyPlainButton())
            }
            if !field.controlPoints.isEmpty, drawing.pending != nil {
                Text("座標簿")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(SurveyColor.muted)
                ForEach(nearestControls) { point in
                    Button(point.name) {
                        drawing.addTarget(
                            kind: .coordinateBook,
                            latitude: point.latitudeDegrees,
                            longitude: point.longitudeDegrees,
                            label: point.name
                        )
                    }
                    .buttonStyle(SurveyPlainButton())
                }
            }
            ForEach(Array(drawing.pairs.enumerated()), id: \.element.id) { index, pair in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(index + 1). \(pair.label)（\(kindLabel(pair.kind))）")
                            .font(.system(size: 14, weight: .heavy))
                        Text(String(format: "図面 X %.3f  Y %.3f", pair.drawingX, pair.drawingY))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SurveyColor.muted)
                        if drawing.pairs.count >= 3, let residual = drawing.fit?.residualsMeters[safe: index] {
                            Text("残差 \(formatMeters(residual))")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(residual > 1 ? SurveyColor.yellow : SurveyColor.text)
                        }
                    }
                    Spacer()
                    Button("外す") { drawing.removePair(pair.id) }
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(SurveyColor.red)
                }
            }
            if let fit = drawing.fit, drawing.pairs.count >= 2 {
                Text("残差の二乗平均 \(formatMeters(fit.rmsMeters))　縮尺 \(String(format: "%.5f", fit.transform.scale))　回転 \(String(format: "%.2f°", fit.transform.rotationDegrees))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SurveyColor.text)
            }
            if drawing.pairs.count >= 2, drawing.accuracy == .mapGrade {
                Text(AlignmentAccuracy.stakeoutNotice)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(SurveyColor.amber)
                Text("この合わせの札は \(AlignmentAccuracy.mapGrade.rawValue) です。")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SurveyColor.muted)
            }
            HStack {
                TextField("合わせの名前", text: $drawing.alignmentName)
                    .textFieldStyle(.roundedBorder)
                Button("保存") { drawing.saveAlignment() }
                    .buttonStyle(SurveyPlainButton())
            }
            if !drawing.alignments.isEmpty {
                Text("保存した合わせ")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(SurveyColor.muted)
                ForEach(drawing.alignments) { record in
                    Button("\(record.name) 版\(record.version)　\(record.accuracyTag.rawValue)") {
                        drawing.use(record)
                    }
                    .buttonStyle(SurveyPlainButton())
                }
            }
        }
    }

    private var inspectionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let inspection = drawing.inspection {
                Text("タップした点")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(SurveyColor.muted)
                Text(String(format: "図面 X %.3f　Y %.3f", inspection.drawingX, inspection.drawingY))
                    .font(.system(size: 15, weight: .heavy))
                if let east = inspection.eastingMeters, let north = inspection.northingMeters {
                    Text(String(format: "%d系　東 %.3f m　北 %.3f m", drawing.zone, east, north))
                        .font(.system(size: 14, weight: .semibold))
                }
                if let latitude = inspection.latitudeDegrees, let longitude = inspection.longitudeDegrees {
                    Text("\(CoordinateText.latitude(latitude)), \(CoordinateText.longitude(longitude))")
                        .font(.system(size: 14, weight: .semibold))
                }
                if let distance = inspection.distanceMeters, let azimuth = inspection.azimuthDegrees {
                    Text("現在地から \(formatMeters(distance))、北から時計回り \(String(format: "%.1f°", azimuth))")
                        .font(.system(size: 15, weight: .heavy))
                } else {
                    Text("現在地が無いので、距離と方向は出せません。")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SurveyColor.muted)
                }
            }
        }
        .foregroundStyle(SurveyColor.text)
    }

    private func suggestionBlock(_ suggestion: ZoneSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if suggestion.matchesDrawingNumbers, let best = suggestion.fromDrawingNumbers.first {
                Text("対応点の数値は \(best.zone)系（\(best.axis.label)）に載っています。ずれ \(formatMeters(best.rmsMeters))。")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(SurveyColor.text)
                candidateButtons(suggestion.fromDrawingNumbers, title: "数値の合う系", applyAxis: true)
            } else {
                Text("図面の数値だけでは系が決まりません。対応点の場所から合いそうな系を出します。")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SurveyColor.text)
                candidateButtons(suggestion.forThisPlace, title: "この場所の系", applyAxis: false)
            }
        }
    }

    private func candidateButtons(_ candidates: [ZoneCandidate], title: String, applyAxis: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(SurveyColor.muted)
            ForEach(Array(candidates.prefix(3))) { candidate in
                Button(applyAxis
                    ? "\(candidate.zone)系　\(candidate.axis.label)　\(formatMeters(candidate.distanceMeters))"
                    : "\(candidate.zone)系　原点まで \(formatMeters(candidate.distanceMeters))"
                ) {
                    drawing.setZone(candidate.zone)
                    if applyAxis {
                        drawing.setAxis(candidate.axis)
                    }
                }
                .buttonStyle(SurveyPlainButton())
            }
        }
    }

    private var projectBinding: Binding<String?> {
        Binding(
            get: { drawing.project?.id },
            set: { id in
                guard let id, let project = drawing.projects.first(where: { $0.id == id }) else { return }
                drawing.select(project)
            }
        )
    }

    private var zoneBinding: Binding<Int> {
        Binding(get: { drawing.zone }, set: { drawing.setZone($0) })
    }

    private var axisBinding: Binding<DrawingAxis> {
        Binding(get: { drawing.axis }, set: { drawing.setAxis($0) })
    }

    private var lockBinding: Binding<Bool> {
        Binding(get: { drawing.lockScale }, set: { drawing.setLockScale($0) })
    }

    private func layerBinding(_ layer: DrawingLayer) -> Binding<Bool> {
        Binding(
            get: { drawing.document?.layers.first { $0.name == layer.name }?.isVisible ?? layer.isVisible },
            set: { drawing.toggleLayer(layer.name, visible: $0) }
        )
    }

    private var userOnDrawing: UserOnDrawing? {
        guard drawing.document != nil,
              let position = field.workingReading.position,
              position.isPlottable,
              position.hasValidHorizontalAccuracy else { return nil }
        return DrawingPlacement.user(
            latitudeDegrees: position.latitudeDegrees,
            longitudeDegrees: position.longitudeDegrees,
            horizontalAccuracyMeters: position.horizontalAccuracyMeters,
            zone: drawing.zone,
            axis: drawing.axis,
            transform: drawing.activeTransform
        )
    }

    private var accuracyText: String {
        guard let position = field.workingReading.position, position.hasValidHorizontalAccuracy else { return "精度なし" }
        return CoordinateText.accuracyMeters(position.horizontalAccuracyMeters)
    }

    private var highlight: PlanarPoint? {
        if let pending = drawing.pending { return pending }
        if let inspection = drawing.inspection {
            return PlanarPoint(x: inspection.drawingX, y: inspection.drawingY)
        }
        return nil
    }

    private var nearestControls: [ControlPoint] {
        guard let position = field.workingReading.position else { return Array(field.controlPoints.prefix(6)) }
        return field.controlPoints
            .sorted { lhs, rhs in
                abs(lhs.latitudeDegrees - position.latitudeDegrees) + abs(lhs.longitudeDegrees - position.longitudeDegrees)
                    < abs(rhs.latitudeDegrees - position.latitudeDegrees) + abs(rhs.longitudeDegrees - position.longitudeDegrees)
            }
            .prefix(6)
            .map { $0 }
    }

    private func useCurrentPosition() {
        guard let position = field.workingReading.position, position.isPlottable else {
            drawing.report("現在地がありません。")
            return
        }
        drawing.addTarget(
            kind: .gnss,
            latitude: position.latitudeDegrees,
            longitude: position.longitudeDegrees,
            label: "現在地"
        )
    }

    private func kindLabel(_ kind: AlignmentTargetKind) -> String {
        switch kind {
        case .map: return "地図"
        case .gnss: return "現在地"
        case .coordinateBook: return "座標簿"
        }
    }

    private func formatMeters(_ meters: Double) -> String {
        if abs(meters) >= 1000 { return String(format: "%.2f km", meters / 1000) }
        if abs(meters) >= 100 { return String(format: "%.0f m", meters) }
        return String(format: "%.2f m", meters)
    }

    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func readSecurityScoped(_ url: URL) -> Data? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }
}

private struct SurveyPlainButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .heavy))
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(SurveyColor.card)
            .foregroundStyle(SurveyColor.text)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private let dxfType = UTType(filenameExtension: "dxf") ?? .data

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
