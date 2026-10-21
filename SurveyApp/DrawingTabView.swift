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
    @State private var impactDraft = ""
    @State private var stillDraft = ""
    @State private var fallNote = ""
    @State private var showsAlign = false
    @State private var showsSetup = false

    var body: some View {
        board
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SurveyColor.background)
        .overlay {
            ZStack {
                if field.extras.proximity {
                    SafetyWash(level: field.crew.worst)
                }
                if field.extras.fall {
                    ThreatRim(cues: [], fall: field.crew.fallCue)
                }
                if field.extras.pushToTalk {
                    TalkRim(pointer: field.talkPointer)
                }
                if field.extras.sos {
                    SOSRim(pointer: field.sosPointer)
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: surveyImportTypes()) { result in
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
        .sheet(isPresented: $showsAlign) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        alignmentSection
                        inspectionSection
                    }
                    .padding(16)
                }
                .background(SurveyColor.background)
                .navigationTitle("合わせ")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("閉じる") { showsAlign = false }
                            .font(SurveyType(17, .heavy))
                    }
                }
            }
            .modifier(SurveyScheme())
        }
        .sheet(isPresented: $showsSetup) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        stationSection
                        machineSection
                        eyeSection
                        zoneBlock
                        layerBlock
                        if drawing.document?.has(.background) == true {
                            backgroundSection
                        }
                        if field.extras.proximity {
                            proximitySection
                        }
                        if field.extras.fall {
                            fallSection
                        }
                    }
                    .padding(16)
                }
                .background(SurveyColor.background)
                .navigationTitle("数値")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("閉じる") { showsSetup = false }
                            .font(SurveyType(17, .heavy))
                    }
                }
            }
            .modifier(SurveyScheme())
            .onAppear { syncCabDrafts() }
        }
        .sheet(isPresented: Binding(
            get: { drawing.pendingIntake != nil },
            set: { if !$0 { drawing.pendingIntake = nil } }
        )) {
            HeightMapSheet(drawing: drawing, columnCount: drawing.pendingIntake?.columnCount ?? 2)
        }
    }

    private var projectBar: some View {
        HStack(spacing: 8) {
            Button {
                field.showsProjects = true
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(drawing.project?.name ?? "現場")
                        .font(SurveyType(18, .heavy))
                        .lineLimit(1)
                    if let file = drawing.fileName {
                        Text(file)
                            .font(SurveyType(13, .semibold))
                            .foregroundStyle(SurveyColor.muted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .foregroundStyle(SurveyColor.text)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("現場")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(SurveyColor.bar)
    }

    private var actionBar: some View {
        let step = FieldFlow.drawingStep(drawing)
        let showsEarlier = drawing.project != nil || drawing.document != nil || drawing.pdfData != nil
        return VStack(spacing: 8) {
            if showsEarlier {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if step != .importFile, drawing.project != nil {
                        actionButton("取り込む") { importing = true }
                    }
                    if step != .align, drawing.document != nil {
                        actionButton("2点合わせ") {
                            FieldFlow.perform(.align, field: field, fromMenu: false)
                        }
                    }
                    if step != .arbitrary, drawing.canPlaceArbitrary || drawing.placingArbitrary {
                        Button {
                            drawing.placingArbitrary.toggle()
                        } label: {
                            Text("任意点")
                                .font(SurveyType(16, .heavy))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(drawing.placingArbitrary ? SurveyColor.blue : SurveyColor.card)
                                .foregroundStyle(drawing.placingArbitrary ? SurveyColor.onAccent : SurveyColor.text)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    if drawing.document != nil || drawing.pdfData != nil {
                        actionButton("全体") { drawing.showWholeDrawing() }
                    }
                    if drawing.project != nil {
                        actionButton("数値") { showsSetup = true }
                    }
                }
                .padding(.horizontal, 12)
            }
            }
            if let step {
                Button(FieldFlow.title(step, field: field)) {
                    if step == .importFile {
                        importing = true
                    } else {
                        FieldFlow.perform(step, field: field, fromMenu: false)
                    }
                }
                .buttonStyle(FlowNextButton())
                .padding(.horizontal, 12)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 24)
        .background(SurveyColor.bar)
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(SurveyType(16, .heavy))
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(SurveyColor.card)
            .foregroundStyle(SurveyColor.text)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .buttonStyle(.plain)
    }

    @ViewBuilder
    private var board: some View {
        if drawing.document == nil, drawing.pdfData == nil {
            emptyBoard
        } else {
            VStack(spacing: 0) {
                projectBar
                if let message = drawing.message, !message.isEmpty {
                    Text(message)
                        .font(SurveyType(16, .heavy))
                        .foregroundStyle(SurveyColor.amber)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                canvas.frame(maxWidth: .infinity, maxHeight: .infinity)
                if drawing.twoPointMode {
                    TwoPointPanel(field: field, drawing: drawing)
                } else {
                    actionBar
                }
            }
        }
    }

    /// 図面が無いあいだは、測量と同じ並びで手順を出す。空白のキャンバスにしない。
    private var emptyBoard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("図面")
                .font(SurveyType(28, .heavy))
                .foregroundStyle(SurveyColor.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            Button {
                field.showsProjects = true
            } label: {
                HStack(spacing: 8) {
                    Text(drawing.project?.name ?? "現場")
                        .font(SurveyType(18, .heavy))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(SurveyType(14, .bold))
                        .foregroundStyle(SurveyColor.muted)
                }
                .foregroundStyle(SurveyColor.text)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .accessibilityLabel("現場")
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let message = drawing.message, !message.isEmpty {
                        Text(message)
                            .font(SurveyType(16, .heavy))
                            .foregroundStyle(SurveyColor.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    FlowRow(title: "取り込む", icon: "square.and.arrow.down") {
                        if drawing.project == nil {
                            field.showsProjects = true
                        } else {
                            importing = true
                        }
                    }
                    FlowRow(title: "2点合わせ", icon: "link") {
                        FieldFlow.perform(.align, field: field, fromMenu: false)
                    }
                    FlowRow(title: "任意点", icon: "mappin") {
                        FieldFlow.perform(.arbitrary, field: field, fromMenu: false)
                    }
                    FlowRow(title: "丁張へ", icon: "arrow.up.forward") {
                        sendSelectionToStakeout()
                    }
                    FlowRow(title: "出す", icon: "square.and.arrow.up") {
                        FieldFlow.perform(.writeDrawing, field: field, fromMenu: false)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SurveyColor.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let step = FieldFlow.drawingStep(drawing) {
                Button(FieldFlow.title(step, field: field)) {
                    if step == .importFile {
                        importing = true
                    } else if step == .projects {
                        field.showsProjects = true
                    } else if step == .sendStakeout {
                        sendSelectionToStakeout()
                    } else {
                        FieldFlow.perform(step, field: field, fromMenu: false)
                    }
                }
                .buttonStyle(FlowNextButton())
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
                .background(SurveyColor.bar)
            }
        }
    }

    private func sendSelectionToStakeout() {
        let sent: Bool
        if drawing.draftPoint != nil {
            sent = drawing.sendDraftToStakeout()
        } else if let id = drawing.selectedPointID {
            sent = drawing.sendToStakeout(id)
        } else if let id = drawing.fieldPoints.first?.id {
            sent = drawing.sendToStakeout(id)
        } else {
            sent = false
        }
        if sent {
            field.selectWork("stakeout")
            field.tab = .build
        } else {
            drawing.report("先に点を置いてください。")
        }
    }

    private var canvas: some View {
        ZStack {
            if let data = drawing.pdfData, drawing.document == nil {
                PDFDrawingView(data: data)
                    .id(drawing.fileName ?? "pdf")
            } else {
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
                    onLongPress: { point, tolerance in
                        drawing.takeDrawingLongPress(point, tolerance: tolerance)
                    },
                    onFit: { drawing.fit(in: $0) }
                )
            }
            VStack {
                if field.extras.proximity {
                    SafetyBanner(crew: field.crew) {
                        field.recordIncident(trigger: .manual)
                    }
                }
                if field.extras.fall {
                    FallBanner(fall: field.fall, incoming: field.crew.fallSpeech) {
                        field.cancelFall()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                }
                if field.extras.firstResponse {
                    FirstResponseCard(field: field)
                }
                if field.extras.sos {
                    SOSControl(field: field)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
                if field.extras.recordsIncidents {
                    IncidentTray(field: field)
                }
                Spacer()
            }
            if let draft = drawing.draftPoint {
                VStack {
                    Spacer()
                    arbitraryCard(draft)
                        .padding(12)
                }
            }
            if let progress = drawing.importProgress {
                VStack(spacing: 10) {
                    Text(progress.label)
                        .font(SurveyType(16, .heavy))
                        .foregroundStyle(SurveyColor.text)
                    ProgressView(value: progress.fraction)
                        .tint(SurveyColor.blue)
                        .frame(maxWidth: 280)
                    Text("解析が終わる前から、プロジェクトは使えます。")
                        .font(SurveyType(13, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                }
                .padding(24)
            } else if drawing.document == nil && drawing.pdfData == nil {
                Text(drawing.project == nil ? "現場を選ぶ" : "取り込む")
                    .font(SurveyType(18, .heavy))
                    .foregroundStyle(SurveyColor.muted)
                    .padding(24)
            }
        }
    }

    private var zoneBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("系", selection: zoneBinding) {
                ForEach(drawing.zoneChoices, id: \.self) { number in
                    Text(PlaneRectangular.zone(number)?.romanLabel ?? "\(number)系").tag(number)
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
        }
    }

    private var layerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let document = drawing.document, document.has(.background) {
                Toggle("背景を表示", isOn: roleBinding(.background))
                    .font(SurveyType(15, .semibold))
                    .tint(SurveyColor.amber)
                if document.has(.design) {
                    Toggle("設計を表示", isOn: roleBinding(.design))
                        .font(SurveyType(15, .semibold))
                        .tint(SurveyColor.amber)
                }
            }
            if let layers = drawing.document?.layers, !layers.isEmpty {
                DisclosureGroup("レイヤ \(layers.filter(\.isVisible).count)/\(layers.count)") {
                    ForEach(layers) { layer in
                        Toggle(layerTitle(layer), isOn: layerBinding(layer))
                            .font(SurveyType(15, .semibold))
                            .tint(SurveyColor.amber)
                    }
                }
                .font(SurveyType(15, .heavy))
                .foregroundStyle(SurveyColor.text)
            }
        }
    }

    private func arbitraryCard(_ draft: FieldPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(draft.snapLabel ?? "任意")
                .font(SurveyType(14, .heavy))
                .foregroundStyle(SurveyColor.muted)
            Text("X \(FieldPoint.meters(draft.northingMeters))")
            Text("Y \(FieldPoint.meters(draft.eastingMeters))")
            TextField("計画高", text: Binding(
                get: {
                    guard let meters = draft.designHeightMeters else { return "" }
                    return String(format: "%g", meters)
                },
                set: { drawing.setDraftHeight($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .keyboardType(.numbersAndPunctuation)
            Button("保存") { drawing.saveDraftPoint() }
                .buttonStyle(SurveyPlainButton())
        }
        .font(SurveyType(28, .heavy, mono: true))
        .foregroundStyle(SurveyColor.text)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                projectSection
                if let message = drawing.message {
                    Text(message)
                        .font(SurveyType(14, .semibold))
                        .foregroundStyle(SurveyColor.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let warning = drawing.warning?.message {
                    Text(warning)
                        .font(SurveyType(14, .heavy))
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
                .font(SurveyType(13, .heavy))
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
                    .font(SurveyType(12, .semibold))
                    .foregroundStyle(SurveyColor.muted)
            } else {
                Text("図面の線をタップして中心線にするか、座標簿の No. から点列を作ります。")
                    .font(SurveyType(12, .semibold))
                    .foregroundStyle(SurveyColor.muted)
            }
        }
    }

    private var machineSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("作業半径（腕の長さの目安）")
                .font(SurveyType(13, .heavy))
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
                .font(SurveyType(12, .semibold))
                .foregroundStyle(SurveyColor.muted)
        }
    }

    private var eyeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("視線高")
                .font(SurveyType(13, .heavy))
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
                .font(SurveyType(15, .semibold))
                .tint(SurveyColor.amber)
            Text(drawing.phoneAtEyes
                ? "下がりは、鉛直の端末高を目の高さとして計画高を引いた値です。±1°以内は目線水平。傾きがあるときは d·sinθ を足します。0.1m。"
                : "端末を\(drawing.sightDatum.label)に置いた高さへ、視線高を足してから計画高を引きます。")
                .font(SurveyType(12, .semibold))
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
        impactDraft = String(format: "%g", field.fall.impactG)
        stillDraft = String(format: "%g", field.fall.stillSeconds)
    }

    private var proximitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("接近")
                .font(SurveyType(13, .heavy))
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
                .font(SurveyType(12, .semibold))
                .foregroundStyle(SurveyColor.muted)
        }
    }

    private var fallSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("転倒・衝撃")
                .font(SurveyType(13, .heavy))
                .foregroundStyle(SurveyColor.muted)
            Toggle("加速度で検知する", isOn: fallEnabled)
                .font(SurveyType(15, .semibold))
                .tint(SurveyColor.amber)
            HStack {
                TextField("衝撃の閾値 g", text: $impactDraft)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                Button("保存") {
                    fallNote = field.fall.setImpactG(impactDraft)
                    impactDraft = String(format: "%g", field.fall.impactG)
                }
                .buttonStyle(SurveyPlainButton())
            }
            HStack {
                TextField("静止の確認 秒", text: $stillDraft)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                Button("保存") {
                    fallNote = field.fall.setStillSeconds(stillDraft)
                    stillDraft = String(format: "%g", field.fall.stillSeconds)
                }
                .buttonStyle(SurveyPlainButton())
            }
            if !fallNote.isEmpty {
                Text(fallNote)
                    .font(SurveyType(12, .semibold))
                    .foregroundStyle(SurveyColor.amber)
            }
            Text("強い加速度のあと、動きが止まっていれば10秒だけ取り消せます。取り消さなければ近くへ方向つきで知らせ、記録の種類は転倒か衝撃になります。\(FallCall.disclaimer)")
                .font(SurveyType(12, .semibold))
                .foregroundStyle(SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fallEnabled: Binding<Bool> {
        Binding(
            get: { field.fall.enabled },
            set: { field.fall.setEnabled($0) }
        )
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
                .font(SurveyType(13, .heavy))
                .foregroundStyle(SurveyColor.muted)
            if drawing.projects.isEmpty {
                Text("まだありません。")
                    .font(SurveyType(15, .semibold))
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
                    .font(SurveyType(16, .heavy))
                    .foregroundStyle(SurveyColor.text)
                    .lineLimit(1)
                Spacer()
                Button("図面を読む") { importing = true }
                    .buttonStyle(SurveyPlainButton())
            }
            if let progress = drawing.importProgress {
                Text(progress.label)
                    .font(SurveyType(13, .semibold))
                    .foregroundStyle(SurveyColor.muted)
            }
            if let document = drawing.document, !document.unsupportedSummary.isEmpty {
                Text("読めない要素: \(document.unsupportedSummary)")
                    .font(SurveyType(13, .semibold))
                    .foregroundStyle(SurveyColor.yellow)
            }
            if let unit = drawing.document?.unitWarning {
                Text(unit)
                    .font(SurveyType(13, .semibold))
                    .foregroundStyle(SurveyColor.yellow)
            }
            if drawing.overlayCapped {
                Text("線が多すぎるので、地図への重ねは途中までです。図面の画面は、見えている範囲だけ描きます。")
                    .font(SurveyType(13, .semibold))
                    .foregroundStyle(SurveyColor.muted)
            }
            if let note = drawing.placementNote {
                Text(note)
                    .font(SurveyType(13, .semibold))
                    .foregroundStyle(SurveyColor.yellow)
                    .fixedSize(horizontal: false, vertical: true)
            }
            stationSection
            TextField("計画高 m（床掘底。空なら高さそのもの）", text: designHeightBinding)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)
            machineSection
            if field.extras.proximity {
                proximitySection
            }
            if field.extras.fall {
                fallSection
            }
            if field.extras.firstResponse {
                SiteAidEditor(field: field)
            }
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
                    Text(PlaneRectangular.zone(number)?.romanLabel ?? "\(number)系").tag(number)
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
                    .font(SurveyType(15, .semibold))
                    .tint(SurveyColor.amber)
                if document.has(.design) {
                    Toggle("設計を表示", isOn: roleBinding(.design))
                        .font(SurveyType(15, .semibold))
                        .tint(SurveyColor.amber)
                }
            }
            if let layers = drawing.document?.layers, !layers.isEmpty {
                DisclosureGroup("レイヤ \(layers.filter(\.isVisible).count)/\(layers.count)") {
                    ForEach(layers) { layer in
                        Toggle(layerTitle(layer), isOn: layerBinding(layer))
                            .font(SurveyType(15, .semibold))
                            .tint(SurveyColor.amber)
                    }
                }
                .font(SurveyType(15, .heavy))
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
                .font(SurveyType(16, .heavy))
                .foregroundStyle(SurveyColor.text)
            Text("背景の線を基盤地図の道路縁・建物と比べます。合えばそのまま使えます。ずれていれば、向きと距離を出して合わせます。合わない図面もあります。")
                .font(SurveyType(13, .semibold))
                .foregroundStyle(SurveyColor.muted)
            Button(drawing.backgroundBusy ? "照合しています" : "背景を照合") {
                drawing.checkBackground()
            }
            .buttonStyle(SurveyPlainButton())
            .disabled(drawing.backgroundBusy)
            if let verdict = drawing.backgroundVerdict {
                Text(verdict.message)
                    .font(SurveyType(14, .heavy))
                    .foregroundStyle(verdict.suggestsShift ? SurveyColor.amber : SurveyColor.text)
                if verdict.suggestsShift {
                    Button("このずれで合わせる") { drawing.applyBackgroundAlignment() }
                        .buttonStyle(SurveyPlainButton())
                    Text(AlignmentAccuracy.stakeoutNotice)
                        .font(SurveyType(13, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                }
            }
        }
    }

    private var alignmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("地図に合わせる")
                .font(SurveyType(16, .heavy))
                .foregroundStyle(SurveyColor.text)
            Text("図面の点と、地図・現在地・座標簿の点を2組以上対応づけます。3組以上は点ごとの残差を出します。")
                .font(SurveyType(13, .semibold))
                .foregroundStyle(SurveyColor.muted)
            Toggle("縮尺を 1 に固定（図面の 1 が 1 m のとき）", isOn: lockBinding)
                .font(SurveyType(14, .semibold))
                .tint(SurveyColor.amber)
            if drawing.pick == .drawingVertex {
                Text("図面の点をタップしてください。")
                    .font(SurveyType(14, .heavy))
                    .foregroundStyle(SurveyColor.amber)
            }
            if drawing.pending != nil {
                Text("対応する場所を選んでください。")
                    .font(SurveyType(14, .heavy))
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
                    .font(SurveyType(13, .heavy))
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
                            .font(SurveyType(14, .heavy))
                        Text(String(format: "図面 X %.3f  Y %.3f", pair.drawingX, pair.drawingY))
                            .font(SurveyType(12, .semibold))
                            .foregroundStyle(SurveyColor.muted)
                        if drawing.pairs.count >= 3, let residual = drawing.fit?.residualsMeters[safe: index] {
                            Text("残差 \(formatMeters(residual))")
                                .font(SurveyType(13, .heavy))
                                .foregroundStyle(residual > 1 ? SurveyColor.yellow : SurveyColor.text)
                        }
                    }
                    Spacer()
                    Button("外す") { drawing.removePair(pair.id) }
                        .font(SurveyType(13, .heavy))
                        .foregroundStyle(SurveyColor.red)
                }
            }
            if let fit = drawing.fit, drawing.pairs.count >= 2 {
                Text("残差の二乗平均 \(formatMeters(fit.rmsMeters))　縮尺 \(String(format: "%.5f", fit.transform.scale))　回転 \(String(format: "%.2f°", fit.transform.rotationDegrees))")
                    .font(SurveyType(13, .semibold))
                    .foregroundStyle(SurveyColor.text)
            }
            if drawing.pairs.count >= 2, drawing.accuracy == .mapGrade {
                Text(AlignmentAccuracy.stakeoutNotice)
                    .font(SurveyType(14, .heavy))
                    .foregroundStyle(SurveyColor.amber)
                Text("この合わせの札は \(AlignmentAccuracy.mapGrade.rawValue) です。")
                    .font(SurveyType(13, .semibold))
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
                    .font(SurveyType(13, .heavy))
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
                    .font(SurveyType(13, .heavy))
                    .foregroundStyle(SurveyColor.muted)
                Text(String(format: "図面 X %.3f　Y %.3f", inspection.drawingX, inspection.drawingY))
                    .font(SurveyType(15, .heavy))
                if let east = inspection.eastingMeters, let north = inspection.northingMeters {
                    Text("\(drawing.zone)系　東 \(StakeoutText.meters(east, precision: stakeoutPrecision))　北 \(StakeoutText.meters(north, precision: stakeoutPrecision))")
                        .font(SurveyType(14, .semibold))
                }
                if let latitude = inspection.latitudeDegrees, let longitude = inspection.longitudeDegrees {
                    Text("\(CoordinateText.latitude(latitude)), \(CoordinateText.longitude(longitude))")
                        .font(SurveyType(14, .semibold))
                }
                Button("この線を中心線にする") {
                    drawing.adoptOperatorLine()
                }
                .buttonStyle(SurveyPlainButton())
                if let guide = field.stakeoutGuide {
                    Text(guide.speech)
                        .font(SurveyType(34, .heavy))
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = guide.detail {
                        Text(detail)
                            .font(SurveyType(20, .heavy))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("AR位置出し") { field.showsARStakeout = true }
                        .buttonStyle(SurveyPlainButton())
                    HStack(spacing: 0) {
                        Text("声")
                            .font(SurveyType(16, .heavy))
                        InfoButton(help: .stakeout)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        ForEach(StakeoutSpeechStyle.allCases, id: \.self) { style in
                            Button(style.label) { field.setStakeoutSpeech(style) }
                                .buttonStyle(.plain)
                                .font(SurveyType(16, .heavy))
                                .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                                .background(field.stakeoutSpeechStyle.style == style ? SurveyColor.blue : SurveyColor.card)
                                .foregroundStyle(field.stakeoutSpeechStyle.style == style ? SurveyColor.onAccent : SurveyColor.text)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach(StakeoutUnit.allCases, id: \.self) { unit in
                            Button(unit.label) { field.setStakeoutUnit(unit) }
                                .buttonStyle(.plain)
                                .font(SurveyType(16, .heavy))
                                .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                                .background(field.stakeoutUnit.unit == unit ? SurveyColor.blue : SurveyColor.card)
                                .foregroundStyle(field.stakeoutUnit.unit == unit ? SurveyColor.onAccent : SurveyColor.text)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                } else if inspection.distanceMeters == nil {
                    Text("現在地なし")
                        .font(SurveyType(14, .semibold))
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
                    .font(SurveyType(14, .heavy))
                    .foregroundStyle(SurveyColor.text)
                candidateButtons(suggestion.fromDrawingNumbers, title: "数値の合う系", applyAxis: true)
            } else {
                Text("図面の数値だけでは系が決まりません。対応点の場所から合いそうな系を出します。")
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.text)
                candidateButtons(suggestion.forThisPlace, title: "この場所の系", applyAxis: false)
            }
        }
    }

    private func candidateButtons(_ candidates: [ZoneCandidate], title: String, applyAxis: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(SurveyType(12, .heavy))
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
                drawing.setPrefecture(name, latitude: nil, longitude: nil)
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
        guard let position = field.navigationReading.position, position.isPlottable else { return nil }
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
        guard field.extras.proximity, drawing.document != nil else { return [] }
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
              let position = field.navigationReading.position,
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
        guard let position = field.navigationReading.position, position.hasValidHorizontalAccuracy else { return "精度なし" }
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
        guard let position = field.navigationReading.position, position.isPlottable else {
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

struct SurveyPlainButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SurveyType(17, .heavy))
            .padding(.horizontal, 12)
            .frame(minHeight: OutdoorContrast.primaryPoints)
            .background(configuration.isPressed ? SurveyColor.pressed : SurveyColor.card)
            .foregroundStyle(SurveyColor.text)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(SurveyColor.line, lineWidth: SurveyColor.stroke)
            )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
