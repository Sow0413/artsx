import SwiftUI
import SurveyCore
import UniformTypeIdentifiers

struct DrawingTabView: View {
    @ObservedObject var field: FieldModel
    @ObservedObject var drawing: DrawingSession
    @State private var importing = false
    @State private var projectName = ""
    @State private var recordName = "起点"
    @State private var radiusDraft = ""
    @State private var eyeDraft = ""
    @State private var stationIntervalDraft = ""
    @State private var stationOriginDraft = ""
    @State private var cautionDraft = ""
    @State private var marginDraft = ""
    @State private var approachDraft = ""
    @State private var repeatDraft = ""

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
        .overlay {
            SafetyWash(level: field.crew.worst)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: drawingTypes) { result in
            switch result {
            case let .success(url):
                guard let data = readSecurityScoped(url) else {
                    drawing.report("ファイルを読めませんでした。")
                    return
                }
                let here = field.workingReading.position
                drawing.importFile(
                    data: data,
                    fileName: url.lastPathComponent,
                    latitude: here?.latitudeDegrees,
                    longitude: here?.longitudeDegrees
                )
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
                reachCenter: reachGraphics?.center,
                reachRadius: reachGraphics?.radius,
                reachRanges: reachGraphics?.ranges ?? [],
                crew: crewGlyphs,
                onTap: { point, tolerance in
                    drawing.takeDrawingTap(point, tolerance: tolerance)
                },
                onFit: { drawing.fit(in: $0) }
            )
            VStack {
                SafetyBanner(crew: field.crew)
                Spacer()
            }
            if drawing.document == nil {
                Text(drawing.project == nil ? "プロジェクトを作って、DXF か SFC を読み込みます。" : "DXF か SFC を読み込むと、ここに図面が出ます。")
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
        .onAppear { syncCabDrafts() }
        .onChange(of: drawing.machineRadiusMeters) { _, _ in syncCabDrafts() }
        .onChange(of: drawing.eyeHeightMeters) { _, _ in syncCabDrafts() }
        .onChange(of: drawing.project?.id) { _, _ in syncCabDrafts() }
        .onChange(of: drawing.stationIntervalMeters) { _, _ in syncCabDrafts() }
        .onChange(of: drawing.stationOrigin) { _, _ in syncCabDrafts() }
    }

    private var stationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("測点")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(SurveyColor.muted)
            HStack {
                TextField("間隔 m", text: $stationIntervalDraft)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                TextField("起点 No.", text: $stationOriginDraft)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                Button("保存") {
                    drawing.setStationInterval(stationIntervalDraft)
                    drawing.setStationOrigin(stationOriginDraft)
                }
                .buttonStyle(SurveyPlainButton())
            }
            Button("測点名の点列を中心線にする") {
                drawing.adoptNamedStations()
            }
            .buttonStyle(SurveyPlainButton())
            if let line = drawing.stationLine {
                Text("\(line.name)　\(line.zone)系　\(String(format: "%.0f", abs(line.lengthMeters)))m　間隔 \(String(format: "%g", line.intervalMeters))m　起点 No.\(line.originStation)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SurveyColor.muted)
            } else {
                Text("図面の線をタップして中心線にするか、座標簿の No. から点列を作ります。")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SurveyColor.muted)
            }
        }
    }

    private var machineSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("作業半径（腕の長さの目安）")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(SurveyColor.muted)
            Picker("機種", selection: presetBinding) {
                Text("手入力").tag(Optional<String>.none)
                ForEach(MachineCatalog.presets) { preset in
                    Text("\(preset.label) 約 \(String(format: "%.0f", preset.radiusMeters))m").tag(Optional(preset.id))
                }
            }
            .pickerStyle(.menu)
            .tint(SurveyColor.text)
            HStack {
                TextField("作業半径 m", text: $radiusDraft)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                Button("保存") { drawing.setMachineRadius(radiusDraft) }
                    .buttonStyle(SurveyPlainButton())
            }
            Text("地図と図面に、現在地を中心にした円を描きます。")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SurveyColor.muted)
        }
    }

    private var eyeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("視線高")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(SurveyColor.muted)
            HStack {
                TextField("視線高 m", text: $eyeDraft)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                Button("保存") { drawing.setEyeHeight(eyeDraft) }
                    .buttonStyle(SurveyPlainButton())
            }
            Picker("基準", selection: datumBinding) {
                ForEach(SightDatum.allCases, id: \.self) { datum in
                    Text(datum.label).tag(datum)
                }
            }
            .pickerStyle(.menu)
            .tint(SurveyColor.text)
            Toggle("端末を目の高さで持つ", isOn: phoneAtEyesBinding)
                .font(.system(size: 15, weight: .semibold))
                .tint(SurveyColor.amber)
            Text(drawing.phoneAtEyes
                ? "下がりは、今の高さから計画高を引いた値です。0.1m。"
                : "端末を\(drawing.sightDatum.label)に置いた高さへ、視線高を足してから計画高を引きます。")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SurveyColor.muted)
        }
    }

    private func syncCabDrafts() {
        radiusDraft = String(format: "%g", drawing.machineRadiusMeters)
        eyeDraft = String(format: "%g", drawing.eyeHeightMeters)
        stationIntervalDraft = String(format: "%g", drawing.stationIntervalMeters)
        stationOriginDraft = String(drawing.stationOrigin)
        cautionDraft = String(format: "%g", drawing.cautionMeters)
        marginDraft = String(format: "%g", drawing.proximityMarginMeters)
        approachDraft = String(format: "%g", drawing.approachLeadMeters)
        repeatDraft = String(format: "%g", drawing.approachRepeatSeconds)
    }

    private var proximitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("接近")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(SurveyColor.muted)
            Picker("この端末", selection: roleBinding) {
                ForEach(CrewRole.allCases, id: \.self) { role in
                    Text(role.label).tag(role)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                TextField("注意 m", text: $cautionDraft)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                Button("保存") { drawing.setCautionMeters(cautionDraft) }
                    .buttonStyle(SurveyPlainButton())
            }
            HStack {
                TextField("半径の余裕 m", text: $marginDraft)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                Button("保存") { drawing.setProximityMargin(marginDraft) }
                    .buttonStyle(SurveyPlainButton())
            }
            HStack {
                TextField("声をかける手前 m", text: $approachDraft)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                Button("保存") { drawing.setApproachLead(approachDraft) }
                    .buttonStyle(SurveyPlainButton())
            }
            HStack {
                TextField("読み上げの間隔 秒", text: $repeatDraft)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                Button("保存") { drawing.setApproachRepeat(repeatDraft) }
                    .buttonStyle(SurveyPlainButton())
            }
            Text("半径＋この距離の手前で、先に声をかけます。人が半径＋余裕に入ると赤。注意の距離以内は黄。\(SafetyNotice.text)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SurveyColor.muted)
        }
    }

    private var roleBinding: Binding<CrewRole> {
        Binding(
            get: { field.crew.role },
            set: { field.crew.setRole($0) }
        )
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
                        field.addProjectRecord(date: todayString(), kind: "下見", name: recordName)
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
                Button("図面を読む") { importing = true }
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
            if let note = drawing.placementNote {
                Text(note)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SurveyColor.yellow)
                    .fixedSize(horizontal: false, vertical: true)
            }
            stationSection
            TextField("計画高 m（床掘底。空なら高さそのもの）", text: designHeightBinding)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)
            machineSection
            proximitySection
            eyeSection
            Picker("都道府県", selection: prefectureBinding) {
                Text("未選択").tag(Optional<String>.none)
                ForEach(PlaneZoneCatalog.prefectures) { prefecture in
                    Text(prefecture.name).tag(Optional(prefecture.name))
                }
            }
            .pickerStyle(.menu)
            .tint(SurveyColor.text)
            Picker("系", selection: zoneBinding) {
                ForEach(drawing.zoneChoices, id: \.self) { number in
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
            if let document = drawing.document, document.has(.background) {
                Toggle("背景を表示", isOn: roleBinding(.background))
                    .font(.system(size: 15, weight: .semibold))
                    .tint(SurveyColor.amber)
                if document.has(.design) {
                    Toggle("設計を表示", isOn: roleBinding(.design))
                        .font(.system(size: 15, weight: .semibold))
                        .tint(SurveyColor.amber)
                }
            }
            if let layers = drawing.document?.layers, !layers.isEmpty {
                DisclosureGroup("レイヤ \(layers.filter(\.isVisible).count)/\(layers.count)") {
                    ForEach(layers) { layer in
                        Toggle(layerTitle(layer), isOn: layerBinding(layer))
                            .font(.system(size: 15, weight: .semibold))
                            .tint(SurveyColor.amber)
                    }
                }
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(SurveyColor.text)
            }
            if drawing.document?.has(.background) == true {
                backgroundSection
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

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("背景と地理院ベクトル")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(SurveyColor.text)
            Text("背景の線を基盤地図の道路縁・建物と比べます。合えばそのまま使えます。ずれていれば、向きと距離を出して合わせます。合わない図面もあります。")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SurveyColor.muted)
            Button(drawing.backgroundBusy ? "照合しています" : "背景を照合") {
                drawing.checkBackground()
            }
            .buttonStyle(SurveyPlainButton())
            .disabled(drawing.backgroundBusy)
            if let verdict = drawing.backgroundVerdict {
                Text(verdict.message)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(verdict.suggestsShift ? SurveyColor.amber : SurveyColor.text)
                if verdict.suggestsShift {
                    Button("このずれで合わせる") { drawing.applyBackgroundAlignment() }
                        .buttonStyle(SurveyPlainButton())
                    Text(AlignmentAccuracy.stakeoutNotice)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SurveyColor.muted)
                }
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
                Text(inspection.snapLabel.map { "タップした\($0)" } ?? "タップした点")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(SurveyColor.muted)
                Text(String(format: "図面 X %.3f　Y %.3f", inspection.drawingX, inspection.drawingY))
                    .font(.system(size: 15, weight: .heavy))
                if let east = inspection.eastingMeters, let north = inspection.northingMeters {
                    Text("\(drawing.zone)系　東 \(StakeoutText.meters(east, precision: stakeoutPrecision))　北 \(StakeoutText.meters(north, precision: stakeoutPrecision))")
                        .font(.system(size: 14, weight: .semibold))
                }
                if let latitude = inspection.latitudeDegrees, let longitude = inspection.longitudeDegrees {
                    Text("\(CoordinateText.latitude(latitude)), \(CoordinateText.longitude(longitude))")
                        .font(.system(size: 14, weight: .semibold))
                }
                if stakeoutPrecision == .centimeters {
                    Text("座標簿で合わせてあるので、cm で出します。")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SurveyColor.muted)
                }
                Button("この線を中心線にする") {
                    drawing.adoptOperatorLine()
                }
                .buttonStyle(SurveyPlainButton())
                Text("追加距離を張り、現在地を No.23+5.0m 左 3.2m のように出します。iPhone の精度で足ります。")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SurveyColor.muted)
                Text("この点がオペの目標です。作業半径の内と外を色で出します。")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SurveyColor.muted)
                if let distance = inspection.distanceMeters, let azimuth = inspection.azimuthDegrees {
                    Text("現在地から \(StakeoutText.meters(distance, precision: stakeoutPrecision))、北から時計回り \(String(format: "%.1f°", azimuth))")
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

    private var designHeightBinding: Binding<String> {
        Binding(
            get: {
                guard let meters = drawing.designHeightMeters else { return "" }
                return String(format: "%g", meters)
            },
            set: { drawing.setDesignHeight($0) }
        )
    }

    private var prefectureBinding: Binding<String?> {
        Binding(
            get: { drawing.project?.prefecture },
            set: { name in
                let here = field.workingReading.position
                drawing.setPrefecture(name, latitude: here?.latitudeDegrees, longitude: here?.longitudeDegrees)
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

    private var stakeoutPrecision: StakeoutPrecision {
        StakeoutPrecision.decide(drawing.stakeoutAccuracy)
    }

    private func roleBinding(_ role: DrawingLayerRole) -> Binding<Bool> {
        Binding(
            get: { drawing.document?.shows(role) ?? false },
            set: { drawing.setRole(role, visible: $0) }
        )
    }

    private func layerTitle(_ layer: DrawingLayer) -> String {
        layer.role == .background ? "\(layer.name)（背景）" : layer.name
    }

    private func layerBinding(_ layer: DrawingLayer) -> Binding<Bool> {
        Binding(
            get: { drawing.document?.layers.first { $0.name == layer.name }?.isVisible ?? layer.isVisible },
            set: { drawing.toggleLayer(layer.name, visible: $0) }
        )
    }

    private var reachGraphics: (center: PlanarPoint, radius: Double, ranges: [ReachRange], rings: [ReachRing])? {
        guard let position = field.workingReading.position, position.isPlottable else { return nil }
        return drawing.reachGraphics(latitude: position.latitudeDegrees, longitude: position.longitudeDegrees)
    }

    private var presetBinding: Binding<String?> {
        Binding(
            get: { drawing.machinePresetID },
            set: { drawing.selectMachinePreset($0) }
        )
    }

    private var datumBinding: Binding<SightDatum> {
        Binding(get: { drawing.sightDatum }, set: { drawing.setSightDatum($0) })
    }

    private var phoneAtEyesBinding: Binding<Bool> {
        Binding(get: { drawing.phoneAtEyes }, set: { drawing.setPhoneAtEyes($0) })
    }

    private var crewGlyphs: [CrewGlyph] {
        guard drawing.document != nil else { return [] }
        let scale = abs(drawing.activeTransform?.scale ?? 1)
        return field.crew.peers.compactMap { peer in
            guard let placed = DrawingPlacement.user(
                latitudeDegrees: peer.latitudeDegrees,
                longitudeDegrees: peer.longitudeDegrees,
                horizontalAccuracyMeters: peer.horizontalAccuracyMeters,
                zone: drawing.zone,
                axis: drawing.axis,
                transform: drawing.activeTransform,
                composesAxis: drawing.activeComposesAxis
            ) else { return nil }
            let level = field.crew.marks.first { $0.id == peer.id }?.level ?? .clear
            return CrewGlyph(
                id: peer.id,
                name: peer.name,
                role: peer.role,
                point: placed.point,
                radius: peer.workRadiusMeters.map { $0 / max(scale, 1e-9) },
                level: level
            )
        }
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
            transform: drawing.activeTransform,
            composesAxis: drawing.activeComposesAxis
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

private var drawingTypes: [UTType] {
    let types = [UTType(filenameExtension: "dxf"), UTType(filenameExtension: "sfc")].compactMap { $0 }
    return types.isEmpty ? [.data] : types
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
