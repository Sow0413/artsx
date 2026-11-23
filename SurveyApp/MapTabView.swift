import SwiftUI
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
                // 操作の列は上に残す。空いたところは地図で、下のカードだけスクロールする。
                if let line = field.basicStakeoutLine {
                    Text(line)
                        .font(SurveyType(22, .heavy))
                        .foregroundStyle(SurveyColor.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(SurveyColor.card)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .accessibilityIdentifier("stakeout-guide")
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

    private var pinnedMapChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                AttributionLabel()
                Spacer(minLength: 8)
                RecenterButton(following: field.followUser) {
                    field.recenter()
                }
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
                        gcpEnabled: field.canStageGCP
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
