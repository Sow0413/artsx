import SwiftUI
import SurveyCore

struct MapTabView: View {
    @ObservedObject var field: FieldModel

    var body: some View {
        GeometryReader { geo in
            let mapHeight = max(180, geo.size.height * 0.40)
            VStack(spacing: 0) {
                WorkBar(field: field)
                mapBand(height: mapHeight)
                ScrollView {
                    VStack(spacing: 8) {
                        alertStack
                        bottomChrome
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(SurveyColor.mapBackdrop)
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
        .sheet(isPresented: $field.showsIncidentStats) {
            IncidentStatsSheet(field: field)
        }
        .sheet(isPresented: $field.showsDisaster) {
            DisasterSheet(field: field)
        }
    }

    private var reachCaption: String {
        let meters = String(format: field.drawing.machinePresetID == nil ? "%.1f" : "%.0f", field.drawing.machineRadiusMeters)
        if let id = field.drawing.machinePresetID, let preset = MachineCatalog.named(id) {
            return "作業半径 \(meters)m（\(preset.label)・目安）"
        }
        return "作業半径 \(meters)m"
    }

    private func mapBand(height: CGFloat) -> some View {
        SurveyMapView(field: field)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    if let guide = field.stakeoutGuide {
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
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(SurveyColor.card.opacity(0.94))
                        .accessibilityElement(children: .combine)
                    }
                    if let station = field.drawing.operatorGuide(at: field.navigationReading.position)?.line,
                       field.drawing.stationLine != nil {
                        Text(station)
                            .font(SurveyType(34, .heavy))
                            .minimumScaleFactor(0.4)
                            .lineLimit(1)
                            .foregroundStyle(SurveyColor.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(SurveyColor.card.opacity(0.94))
                    }
                    if field.enclosingBook {
                        enclosureBanner
                    } else if field.drawing.pick == .mapPoint {
                        mapPickBanner
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                AttributionLabel()
                    .padding(8)
            }
            .overlay(alignment: .bottomTrailing) {
                RecenterButton(following: field.followUser) {
                    field.recenter()
                }
                .padding(8)
            }
            .clipped()
    }

    private var alertStack: some View {
        VStack(spacing: 6) {
            if field.extras.proximity {
                SafetyBanner(crew: field.crew) {
                    field.recordIncident(trigger: .manual)
                }
            }
            if field.extras.fall {
                FallBanner(fall: field.fall, incoming: field.crew.fallSpeech) {
                    field.cancelFall()
                }
            }
            if field.extras.firstResponse {
                FirstResponseCard(field: field)
            }
            if field.extras.sos {
                SOSControl(field: field)
            }
            if field.extras.recordsIncidents {
                IncidentTray(field: field)
            }
            HStack {
                if field.extras.pushToTalk {
                    chipButton(field.radio.spaceAudio ? "定位オン" : "定位", tint: field.radio.spaceAudio ? SurveyColor.amber : SurveyColor.text) {
                        field.radio.setSpaceAudio(!field.radio.spaceAudio)
                    }
                    .accessibilityLabel(field.radio.spaceAudio ? "音声の方向定位オン" : "音声の方向定位オフ")
                }
                if field.extras.disaster {
                    chipButton("災害", tint: field.disasterMode ? Color.white : SurveyColor.text, fill: field.disasterMode ? SurveyColor.red : SurveyColor.card) {
                        field.showsDisaster = true
                    }
                }
                if field.extras.stats || field.extras.accidentReport {
                    chipButton(field.extras.stats ? "統計" : "事故報告", fill: field.showIncidentHeat ? SurveyColor.red : SurveyColor.card) {
                        field.showsIncidentStats = true
                    }
                }
                Spacer(minLength: 0)
                Text(reachCaption)
                    .font(SurveyType(12, .heavy))
                    .foregroundStyle(SurveyColor.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
                    .background(SurveyColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if field.extras.disaster, field.disasterMode {
                Text("災害派遣。圏外のまま、近くの端末へ中継します。")
                    .font(SurveyType(13, .heavy))
                    .foregroundStyle(SurveyColor.onAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(SurveyColor.redBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 12)
    }

    private var bottomChrome: some View {
        VStack(spacing: 8) {
            if field.selectedControlPoint != nil || field.benchmark != nil {
                BenchmarkCard(field: field)
                    .frame(maxHeight: 320)
            } else {
                BenchmarkHint(
                    notice: field.controlPointNotice,
                    loadedCount: field.controlPoints.count,
                    visibleCount: field.visibleControlPoints.count
                )
                LocationPanel(
                    reading: field.navigationReading,
                    note: field.navigationNote,
                    statureNotice: field.statureNotice,
                    onStature: { field.showsStature = true },
                    showsLevel: field.stature.style == .sight,
                    levelTilt: field.sightTiltRadians
                )
                toolGrid
                if !field.isDownloading {
                    Text(field.downloadMessage)
                        .font(SurveyType(13, .semibold))
                        .foregroundStyle(field.downloadMessage.contains("広すぎ") || field.downloadMessage.contains("できません") ? SurveyColor.amber : SurveyColor.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                captureButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var toolGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            toolButton("水準器") { field.showsCrosshair = true }
            toolButton("丁張") { field.showsBatter = true }
            toolButton("AR位置出し") { field.showsARStakeout = true }
            toolButton("歩測") { field.showsPace = true }
            toolButton(field.isDownloading ? field.downloadMessage : "この範囲を保存", enabled: !field.isDownloading) {
                field.downloadVisibleArea()
            }
            if field.isDownloading {
                toolButton("中止", filled: false) { field.cancelDownload() }
            }
        }
    }

    private func toolButton(_ title: String, filled: Bool = true, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(SurveyType(15, .heavy))
                .minimumScaleFactor(0.65)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 6)
                .background(filled && enabled ? SurveyColor.blue : SurveyColor.card)
                .foregroundStyle(filled && enabled ? SurveyColor.onAccent : SurveyColor.text)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func chipButton(_ title: String, tint: Color = SurveyColor.text, fill: Color = SurveyColor.card, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(SurveyType(14, .heavy))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .buttonStyle(.plain)
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
            .frame(minHeight: 44)
            Button("やめる") {
                field.cancelBookEnclosure()
            }
            .font(SurveyType(15, .heavy))
            .foregroundStyle(SurveyColor.text)
            .frame(minHeight: 44)
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
            .font(SurveyType(16, .heavy))
            .foregroundStyle(SurveyColor.text)
            .frame(minHeight: 44)
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
