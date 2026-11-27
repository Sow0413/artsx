import SwiftUI
import UIKit
import SurveyCore

private struct MapChromeHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MapTabView: View {
    @ObservedObject var field: FieldModel
    @ObservedObject var appearance: SurveyAppearance
    @State private var chromeHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if let status = field.uiTestDrawingStatus {
                    Text(status)
                        .font(SurveyType(14, .heavy))
                        .foregroundStyle(SurveyColor.amber)
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(SurveyColor.card)
                        .accessibilityIdentifier("draw-overlay-status")
                }
                if !SurveyBuild.basicMode {
                    WorkBar(field: field)
                }
                if !SurveyBuild.basicMode, let guide = field.stakeoutGuide {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(guide.speech)
                            .font(SurveyType(34, .heavy))
                            .minimumScaleFactor(0.5)
                            .lineLimit(2)
                        if let detail = guide.detail {
                            Text(detail)
                                .font(SurveyType(20, .heavy))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    .foregroundStyle(SurveyColor.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(SurveyColor.card)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(SurveyColor.line).frame(height: SurveyColor.stroke)
                    }
                    .accessibilityElement(children: .combine)
                }
                if !SurveyBuild.basicMode,
                   let station = field.drawing.operatorGuide(at: field.navigationReading.position)?.line,
                   field.drawing.stationLine != nil {
                    Text(station)
                        .font(SurveyType(34, .heavy))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .foregroundStyle(SurveyColor.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(SurveyColor.card)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(SurveyColor.line).frame(height: SurveyColor.stroke)
                        }
                }
                if !SurveyBuild.basicMode, field.extras.proximity {
                    SafetyBanner(crew: field.crew) {
                        field.recordIncident(trigger: .manual)
                    }
                }
                if !SurveyBuild.basicMode, field.extras.fall {
                    FallBanner(fall: field.fall, incoming: field.crew.fallSpeech) {
                        field.cancelFall()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                }
                if !SurveyBuild.basicMode, field.extras.firstResponse {
                    FirstResponseCard(field: field)
                }
                if !SurveyBuild.basicMode, field.extras.sos {
                    SOSControl(field: field)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
                if !SurveyBuild.basicMode, field.extras.recordsIncidents {
                    IncidentTray(field: field)
                }
                HStack {
                    if !SurveyBuild.basicMode {
                        ExtraEntryButton {
                            field.showsExtras = true
                        }
                    }
                    #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
                    if let session = field.rtkSession {
                        RTKEntryButton(connected: session.mode == .rtk && session.deviceConnected, fix: session.fix) {
                            field.openRTK()
                        }
                    }
                    #endif
                    if !SurveyBuild.basicMode, field.extras.pushToTalk {
                        Button(field.radio.spaceAudio ? "定位オン" : "定位") {
                            field.radio.setSpaceAudio(!field.radio.spaceAudio)
                        }
                        .font(SurveyType(14, .heavy))
                        .foregroundStyle(field.radio.spaceAudio ? SurveyColor.amber : SurveyColor.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(SurveyColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityLabel(field.radio.spaceAudio ? "音声の方向定位オン" : "音声の方向定位オフ")
                    }
                    if !SurveyBuild.basicMode, field.extras.disaster {
                        Button("災害") {
                            field.showsDisaster = true
                        }
                        .font(SurveyType(14, .heavy))
                        .foregroundStyle(field.disasterMode ? Color.white : SurveyColor.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(field.disasterMode ? SurveyColor.red : SurveyColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    if !SurveyBuild.basicMode, field.extras.stats || field.extras.accidentReport {
                        Button(field.extras.stats ? "統計" : "事故報告") {
                            field.showsIncidentStats = true
                        }
                        .font(SurveyType(14, .heavy))
                        .foregroundStyle(SurveyColor.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(field.showIncidentHeat ? SurveyColor.red : SurveyColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    Spacer()
                    if !SurveyBuild.basicMode {
                    Text(reachCaption)
                        .font(SurveyType(13, .heavy))
                        .foregroundStyle(SurveyColor.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(SurveyColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(.trailing, 12)
                .padding(.top, 6)
                if !SurveyBuild.basicMode, field.extras.disaster, field.disasterMode {
                    Text("災害派遣。圏外のまま、近くの端末へ中継します。")
                        .font(SurveyType(13, .heavy))
                        .foregroundStyle(SurveyColor.onAccent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(SurveyColor.redBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
                if !SurveyBuild.basicMode, field.enclosingBook {
                    enclosureBanner
                } else if field.drawing.pick == .mapPoint {
                    mapPickBanner
                }
                if !SurveyBuild.basicMode, let lines = field.basicStakeoutLines {
                    StakeoutGuideBlock(lines: lines)
                }
                if SurveyBuild.basicMode, field.tab == .map, let message = mapCaptureMessage {
                    Text(message)
                        .font(SurveyType(15, .heavy))
                        .foregroundStyle(SurveyColor.amber)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .accessibilityIdentifier("gcp-saved")
                }
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                pinnedMapChrome
                if !field.mapTargetVisible {
                    ScrollView {
                        scrollingChrome
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(key: MapChromeHeight.self, value: proxy.size.height)
                                }
                            }
                    }
                    .onPreferenceChange(MapChromeHeight.self) { chromeHeight = $0 }
                    .layoutPriority(1)
                    .frame(height: mapChromeBand(in: geo.size.height))
                    .accessibilityIdentifier("map-controls")
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .background {
                SurveyMapView(field: field)
            }
            .background(SurveyColor.mapBackdrop)
        }
        .clipped()
        .overlay {
            ZStack {
                if !SurveyBuild.basicMode, field.extras.proximity {
                    SafetyWash(level: field.crew.worst)
                }
                if !SurveyBuild.basicMode, field.extras.fall {
                    ThreatRim(cues: [], fall: field.crew.fallCue)
                }
                if !SurveyBuild.basicMode, field.extras.pushToTalk {
                    TalkRim(pointer: field.talkPointer)
                }
                if !SurveyBuild.basicMode, field.extras.sos {
                    SOSRim(pointer: field.sosPointer)
                }
            }
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $field.showsIncidentStats) {
            IncidentStatsSheet(field: field)
        }
        .sheet(isPresented: $field.showsDisaster) {
            DisasterSheet(field: field)
        }
        .sheet(isPresented: Binding(
            get: { field.mapTargetVisible },
            set: { if !$0 { field.dismissMapTarget() } }
        )) {
            mapTargetCard
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .height(280)))
        }
    }

    /// FIX に戻ったあとの「記録を止めました」は出さない。
    private var mapCaptureMessage: String? {
        let quality = field.reading.position?.fixQuality ?? .none
        return StageDropNotice.resolve(
            current: field.captureMessage,
            stage: field.stageTransition.stage,
            quality: quality
        )
    }

    /// カードの高さだけ下に残し、空いた分は地図にする。長い列は画面の 46% でスクロールする。
    private func mapChromeBand(in total: CGFloat) -> CGFloat {
        let cap = max(160, total * 0.46)
        let content = chromeHeight > 1 ? chromeHeight : 120
        return min(content, cap)
    }

    private var reachCaption: String {
        let meters = String(format: field.drawing.machinePresetID == nil ? "%.1f" : "%.0f", field.drawing.machineRadiusMeters)
        if let id = field.drawing.machinePresetID, let preset = MachineCatalog.named(id) {
            return "作業半径 \(meters)m（\(preset.label)・目安）"
        }
        return "作業半径 \(meters)m"
    }

    private struct StakeoutGuideBlock: View {
        var lines: StakeoutLines
        var compact = false

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                guideLine(lines.zone, "stakeout-zone")
                guideLine(lines.name, "stakeout-name")
                guideLine(lines.distance, "stakeout-distance")
                if !lines.north.isEmpty { guideLine(lines.north, "stakeout-north") }
                if !lines.east.isEmpty { guideLine(lines.east, "stakeout-east") }
                guideLine(lines.height, "stakeout-height")
            }
            .font(.system(size: compact ? 16 : 28, weight: .bold, design: .monospaced))
            .foregroundStyle(SurveyColor.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(compact ? 0 : 10)
            .background(compact ? Color.clear : SurveyColor.card)
            .padding(.horizontal, compact ? 0 : 12)
            .padding(.top, compact ? 0 : 6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("stakeout-guide")
        }

        private func guideLine(_ text: String, _ identifier: String) -> some View {
            Text(text)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
        }
    }

    private var mapTargetCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(targetTitle)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityIdentifier("cad-target-name")
                Spacer(minLength: 8)
                Button {
                    field.dismissMapTarget()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                        Text("測設をやめる")
                    }
                    .font(SurveyType(15, .heavy))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stakeout-stop")
            }
            if let headline = bigDistance {
                Text(headline)
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.25)
                    .accessibilityIdentifier(field.cadStaking ? "cad-distance" : "stakeout-big")
                if field.cadStaking {
                    Text(field.cadHint)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .accessibilityIdentifier("cad-hint")
                }
            }
            if let lines = field.basicStakeoutLines, field.basicTarget != nil {
                StakeoutGuideBlock(lines: lines, compact: true)
            }
            if field.cadPick != nil, !field.cadStaking {
                Button {
                    field.stakeCadPick()
                } label: {
                    Text("ここへ測設")
                        .font(SurveyType(20, .heavy))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(SurveyColor.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(SurveyColor.onAccent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cad-stake")
            } else if field.selectedControlPoint != nil, field.basicTarget == nil, !field.cadStaking {
                Button {
                    field.stakeSelectedControlPoint()
                } label: {
                    Text("測設")
                        .font(SurveyType(20, .heavy))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(SurveyColor.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(SurveyColor.onAccent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stake-selected")
            }
            Button("戻る") { field.dismissMapTarget() }
                .font(SurveyType(16, .heavy))
                .accessibilityIdentifier("selection-back")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SurveyColor.background)
        .onAppear {
            if bigDistance == "到達" {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        }
        .onChange(of: bigDistance) { _, next in
            if next == "到達" {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        }
    }

    private var targetTitle: String {
        field.cadPick?.name ?? field.selectedControlPoint?.name ?? field.basicTarget?.name ?? "測設"
    }

    private var bigDistance: String? {
        if field.cadStaking { return field.cadHeadline }
        guard let lines = field.basicStakeoutLines, field.basicTarget != nil else { return nil }
        if lines.distance.contains("m") || lines.distance.contains("cm") || lines.distance.contains("km") {
            return "あと \(lines.distance)"
        }
        return lines.distance
    }

    private var pinnedMapChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                AttributionLabel()
                Spacer(minLength: 8)
                RecenterButton(following: field.followUser) {
                    field.recenter()
                }
            }
            if SurveyBuild.basicMode, !field.drawing.mapPaths.isEmpty {
                Text("\(field.drawing.zone)系")
                    .font(SurveyType(18, .heavy))
                    .foregroundStyle(SurveyColor.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("map-zone")
            }
            if SurveyBuild.basicMode, !field.visibleControlPoints.isEmpty {
                Text("測点 \(field.visibleControlPoints.count)")
                    .font(SurveyType(18, .heavy))
                    .foregroundStyle(SurveyColor.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("survey-points")
            }
            if SurveyBuild.basicMode {
                Button(action: appearance.cycle) {
                    Text(appearance.label)
                        .font(SurveyType(16, .heavy))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(appearance.outdoor ? SurveyColor.color(OutdoorContrast.yellow) : SurveyColor.card)
                        .foregroundStyle(appearance.outdoor ? SurveyColor.color(OutdoorContrast.black) : SurveyColor.text)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("theme-toggle")
            }
        }
        .padding(.horizontal, 12)
    }

    private var scrollingChrome: some View {
        VStack(spacing: 10) {
                if !SurveyBuild.basicMode, field.selectedControlPoint != nil || field.benchmark != nil {
                    BenchmarkCard(field: field)
                        .frame(maxHeight: 460)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    if !SurveyBuild.basicMode {
                        BenchmarkHint(
                            notice: field.controlPointNotice,
                            loadedCount: field.controlPoints.count,
                            visibleCount: field.visibleControlPoints.count
                        )
                        DownloadBar(
                            message: field.downloadMessage,
                            isDownloading: field.isDownloading,
                            onSave: field.downloadVisibleArea,
                            onCancel: field.cancelDownload
                        )
                    }
                    LocationPanel(
                        reading: field.navigationReading,
                        note: field.navigationNote,
                        statureNotice: SurveyBuild.basicMode ? nil : field.statureNotice,
                        onStature: SurveyBuild.basicMode ? nil : { field.showsStature = true },
                        showsLevel: !SurveyBuild.basicMode && field.stature.style == .sight,
                        levelTilt: field.sightTiltRadians,
                        onRecord: { field.stageMapObservation() },
                        onGCP: { field.stageMapGCP() },
                        gcpEnabled: field.canStageGCP,
                        rawStatus: field.rawCaptureStatus == "記録中" ? "記録中" : nil
                    )
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !SurveyBuild.basicMode {
                    Button {
                        field.showsCrosshair = true
                    } label: {
                        Text("水準器")
                            .font(SurveyType(18, .heavy))
                            .frame(maxWidth: 560, minHeight: OutdoorContrast.primaryPoints)
                            .frame(maxWidth: .infinity)
                            .background(SurveyColor.blue)
                            .foregroundStyle(SurveyColor.onAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button {
                        field.showsBatter = true
                    } label: {
                        Text("丁張")
                            .font(SurveyType(18, .heavy))
                            .frame(maxWidth: 560, minHeight: OutdoorContrast.primaryPoints)
                            .frame(maxWidth: .infinity)
                            .background(SurveyColor.blue)
                            .foregroundStyle(SurveyColor.onAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button {
                        field.showsARStakeout = true
                    } label: {
                        Text("AR位置出し")
                            .font(SurveyType(18, .heavy))
                            .frame(maxWidth: 560, minHeight: OutdoorContrast.primaryPoints)
                            .frame(maxWidth: .infinity)
                            .background(SurveyColor.blue)
                            .foregroundStyle(SurveyColor.onAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button {
                        field.showsPace = true
                    } label: {
                        Text("歩測")
                            .font(SurveyType(18, .heavy))
                            .frame(maxWidth: 560, minHeight: OutdoorContrast.primaryPoints)
                            .frame(maxWidth: .infinity)
                            .background(SurveyColor.blue)
                            .foregroundStyle(SurveyColor.onAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    captureButton
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: 640)
    }

    private var enclosureBanner: some View {
        HStack(spacing: 12) {
            Text("見えている範囲で座標簿を絞る")
                .font(SurveyType(15, .heavy))
                .foregroundStyle(SurveyColor.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("この範囲") {
                field.confirmBookEnclosure()
            }
            .font(SurveyType(15, .heavy))
            .foregroundStyle(SurveyColor.green)
            .frame(minHeight: OutdoorContrast.primaryPoints)
            Button("やめる") {
                field.cancelBookEnclosure()
            }
            .font(SurveyType(15, .heavy))
            .foregroundStyle(SurveyColor.text)
            .frame(minHeight: OutdoorContrast.primaryPoints)
        }
        .padding(12)
        .background(SurveyColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var mapPickBanner: some View {
        HStack(spacing: 12) {
            Text("図面の点に対応する場所をタップ")
                .font(SurveyType(15, .heavy))
                .foregroundStyle(SurveyColor.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("戻る") {
                field.cancelDrawingMapPick()
            }
            .font(SurveyType(18, .heavy))
            .foregroundStyle(SurveyColor.text)
            .frame(minHeight: OutdoorContrast.primaryPoints)
        }
        .padding(12)
        .background(SurveyColor.amberBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var captureButton: some View {
        OperationBar(field: field, showsSkill: false, compact: true)
    }
}

struct MapLoadMenu: View {
    @ObservedObject var field: FieldModel
    @Binding var showsDrawingImport: Bool

    var body: some View {
        Menu {
            Button("図面を読む") { showsDrawingImport = true }
                .accessibilityIdentifier("map-open-draw")
            Button("座標を読み込む") { CoordinateImport.start(field: field) }
                .accessibilityIdentifier("import-coordinates")
            Menu(field.zoneChoiceLabel) {
                ForEach(PlaneZoneLabel.pickerZones(), id: \.self) { zone in
                    Button(PlaneZoneLabel.button(zone)) {
                        field.chooseCoordinateZone(zone)
                    }
                    .accessibilityIdentifier("coord-zone-\(zone)")
                }
            }
            .accessibilityIdentifier("coord-zone-button")
            Button(field.showDrawing ? "図面を隠す" : "図面を出す") {
                field.showDrawing.toggle()
            }
            .accessibilityIdentifier("toggle-drawing")
            Button(field.showMapTiles ? "地図を隠す" : "地図を出す") {
                field.showMapTiles.toggle()
            }
            .accessibilityIdentifier("toggle-tiles")
            if field.selectedControlPoint == nil, field.cadPick == nil, let point = field.visibleControlPoints.first {
                Button(point.name) { field.selectControlPoint(point.id) }
                    .accessibilityIdentifier("pick-imported-point")
            }
            if ProcessInfo.processInfo.arguments.contains("-surveyUITest"), !field.drawing.mapPaths.isEmpty {
                Button("図面の頂点") { field.snapDrawingVertex() }
                    .accessibilityIdentifier("cad-tap-vertex")
            }
        } label: {
            Image(systemName: "square.and.arrow.down")
                .font(SurveyType(18, .heavy))
                .frame(width: 44, height: 44)
                .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(SurveyColor.text)
        }
        .accessibilityLabel("読込")
        .accessibilityIdentifier("map-load")
    }
}
