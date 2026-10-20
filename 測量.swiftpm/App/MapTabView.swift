import SwiftUI

struct MapTabView: View {
    @ObservedObject var field: FieldModel

    var body: some View {
        ZStack {
            SurveyMapView(field: field)
            VStack(spacing: 0) {
                WorkBar(field: field)
                if let station = field.drawing.operatorGuide(at: field.workingReading.position)?.line,
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
                HStack {
                    ExtraEntryButton {
                        field.showsExtras = true
                    }
                    if field.extras.pushToTalk {
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
                    if field.extras.disaster {
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
                    if field.extras.stats || field.extras.accidentReport {
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
                    Text(reachCaption)
                        .font(SurveyType(13, .heavy))
                        .foregroundStyle(SurveyColor.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(SurveyColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(.trailing, 12)
                .padding(.top, 6)
                if field.extras.disaster, field.disasterMode {
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
                if field.enclosingBook {
                    enclosureBanner
                } else if field.drawing.pick == .mapPoint {
                    mapPickBanner
                }
                Spacer(minLength: 0)
                bottomChrome
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

    private var bottomChrome: some View {
        VStack(spacing: 10) {
                HStack(alignment: .top) {
                    AttributionLabel()
                    Spacer(minLength: 8)
                    RecenterButton(following: field.followUser) {
                        field.recenter()
                    }
                }
                if field.selectedControlPoint != nil || field.benchmark != nil {
                    BenchmarkCard(field: field)
                        .frame(maxHeight: 460)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
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
                    LocationPanel(
                        reading: field.workingReading,
                        note: field.showsCorrectedPosition ? "三角点補正を引いた位置" : nil,
                        statureNotice: field.statureNotice,
                        onStature: { field.showsStature = true },
                        showsLevel: field.stature.style == .sight,
                        levelTilt: field.sightTiltRadians
                    )
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                    captureButton
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
