import SwiftUI
import SurveyCore

struct MapTabView: View {
    @ObservedObject var field: FieldModel
    @State private var suppressCadPress = false

    var body: some View {
        SurveyMapView(field: field)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) { topStack }
            .overlay(alignment: .bottomLeading) {
                coordinateStack.padding(.bottom, mapSendPoint == nil ? 0 : 96)
            }
            .overlay(alignment: .bottomTrailing) {
                mapButtons.padding(.bottom, mapSendPoint == nil ? 0 : 96)
            }
            .overlay(alignment: .bottom) { mapSendButton }
            .background(SurveyColor.mapBackdrop)
            .overlay { safetyWash }
            .onAppear { field.refreshTerrainElevation() }
            .sheet(isPresented: $field.showsIncidentStats) {
                IncidentStatsSheet(field: field)
            }
            .sheet(isPresented: $field.showsDisaster) {
                DisasterSheet(field: field)
            }
    }

    private var topStack: some View {
        VStack(spacing: 0) {
            if let name = field.drawing.project?.name {
                HStack {
                    Button {
                        field.showsProjects = true
                    } label: {
                        Text(name)
                            .font(SurveyType(13, .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(Color.black.opacity(0.8))
                            .padding(.horizontal, 10)
                            .frame(minHeight: 44)
                            .background(Color.white.opacity(0.72), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("現場 \(name)")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
            }
            if let point = field.drawing.stakeoutPoint {
                stakeoutHeights(point)
            }
            if let id = field.drawing.selectedPointID,
               field.drawing.pending == nil,
               let point = field.drawing.fieldPoints.first(where: { $0.id == id }),
               field.drawing.stakeoutPointID != id {
                selectedPointCard(point)
            }
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
            alertStack
        }
    }

    private var coordinateStack: some View {
        VStack(alignment: .leading, spacing: 6) {
            if field.isDownloading {
                HStack(spacing: 8) {
                    Text("保存中")
                        .font(SurveyType(14, .heavy))
                    Button("中止") { field.cancelDownload() }
                        .font(SurveyType(14, .heavy))
                        .frame(minHeight: 44)
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 8)
                .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            coordinateChip
            AttributionLabel()
        }
        .padding(8)
    }

    @ViewBuilder
    private var coordinateChip: some View {
        if let position = field.reading.position ?? field.navigationReading.position, position.isPlottable {
            let survey = field.liveSurveyHeight(position)
            let height = Self.mapHeightLine(survey)
            let terrain = field.gsiElevationMeters.flatMap {
                GSIElevationText.line(demMeters: $0, gnssMeters: survey.orthometricMeters)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(height)
                    .foregroundStyle(Color.black)
                if let terrain {
                    terrainText(terrain)
                }
                Text(CoordinateText.latitude(position.latitudeDegrees))
                    .foregroundStyle(Color.black)
                Text(CoordinateText.longitude(position.longitudeDegrees))
                    .foregroundStyle(Color.black)
            }
            .font(SurveyType(14, .heavy, mono: true))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.coordinateLabel(height: height, terrain: terrain, position: position))
            .allowsHitTesting(false)
        }
    }

    private func terrainText(_ line: GSIElevationLine) -> Text {
        let prefix = Text(line.prefix).foregroundColor(.black)
        guard let difference = line.difference else { return prefix }
        let color: Color = line.highlightDifference ? Self.terrainAlert : .black
        return prefix + Text(difference).foregroundColor(color)
    }

    private static func coordinateLabel(height: String, terrain: GSIElevationLine?, position: GeodeticPosition) -> String {
        let place = "\(height)、緯度 \(CoordinateText.latitude(position.latitudeDegrees))、経度 \(CoordinateText.longitude(position.longitudeDegrees))"
        guard let terrain else { return place }
        return "\(height)、\(terrain.spoken)、緯度 \(CoordinateText.latitude(position.latitudeDegrees))、経度 \(CoordinateText.longitude(position.longitudeDegrees))"
    }

    /// 白地のチップの上で橙のまま残す。屋外表示の黒にはしない。
    private static let terrainAlert = Color(red: 0.90, green: 0.42, blue: 0.05)

    private static func mapHeightLine(_ height: SurveyHeight) -> String {
        guard let meters = height.orthometricMeters else { return "標高 —" }
        return "標高 \(FixedNumber.string(meters, fractionDigits: 1))m"
    }

    private var mapButtons: some View {
        VStack(spacing: 8) {
            if field.drawing.hasMapOverlay {
                Button {
                    if suppressCadPress {
                        suppressCadPress = false
                        return
                    }
                    field.toggleMapCad()
                } label: {
                    Image(systemName: field.mapCadOn ? "ruler.fill" : "ruler")
                        .font(SurveyType(16, .bold))
                        .frame(width: 44, height: 44)
                        .background(Color.white, in: Circle())
                        .foregroundStyle(Color.black)
                }
                .buttonStyle(.plain)
                .onLongPressGesture(minimumDuration: 0.45) {
                    suppressCadPress = true
                    field.showsCadOpacity = true
                }
                .accessibilityLabel(field.mapCadOn ? "図面オン" : "図面オフ")
                .accessibilityHint("長押しで濃さ")
            }
            Button {
                field.toggleMapHeading()
            } label: {
                Text(field.mapHeadingUp ? "進行" : "北")
                    .font(SurveyType(15, .heavy))
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: Circle())
                    .foregroundStyle(Color.black)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(field.mapHeadingUp ? "進行を上" : "北を上")
            RecenterButton(following: field.followUser) {
                field.recenter()
            }
        }
        .padding(8)
    }

    private func stakeoutHeights(_ point: FieldPoint) -> some View {
        let fill = CutFill.make(formation: point.formationHeightMeters, ground: point.groundLevelMeters)
        return VStack(alignment: .leading, spacing: 0) {
            if let formation = fill.formationMeters {
                Text("FH \(FieldPoint.meters(formation))")
            }
            if let ground = fill.groundMeters {
                Text("標高 \(FieldPoint.meters(ground))")
            }
            if let word = fill.word, let difference = fill.differenceText {
                Text(word)
                Text(difference)
                    .font(SurveyType(40, .heavy, mono: true))
            } else if let design = point.designHeightMeters {
                Text("計画 \(FieldPoint.meters(design))")
                    .font(SurveyType(34, .heavy, mono: true))
            }
        }
        .font(SurveyType(22, .heavy, mono: true))
        .foregroundStyle(SurveyColor.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(SurveyColor.card.opacity(0.94))
    }

    private var mapSendPoint: FieldPoint? {
        guard let id = field.drawing.selectedPointID,
              field.drawing.pending == nil,
              field.drawing.stakeoutPointID != id else { return nil }
        return field.drawing.fieldPoints.first { $0.id == id }
    }

    @ViewBuilder
    private var mapSendButton: some View {
        if let point = mapSendPoint {
            Button("丁張へ") {
                if field.drawing.sendToStakeout(point.id) {
                    field.selectWork("stakeout")
                    field.tab = .build
                }
            }
            .buttonStyle(FlowNextButton())
            .padding(.horizontal, 12)
            .padding(.bottom, 28)
        }
    }

    private func selectedPointCard(_ point: FieldPoint) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(point.mapLabel)
                .lineLimit(1)
            Text("X \(FieldPoint.meters(point.northingMeters))  Y \(FieldPoint.meters(point.eastingMeters))")
                .font(SurveyType(14, .heavy, mono: true))
        }
        .font(SurveyType(18, .heavy))
        .foregroundStyle(SurveyColor.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(SurveyColor.card.opacity(0.94))
    }

    private var safetyWash: some View {
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
        .allowsHitTesting(false)
    }

    @ViewBuilder
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
            if field.extras.disaster, field.disasterMode {
                Text("災害派遣")
                    .font(SurveyType(13, .heavy))
                    .foregroundStyle(SurveyColor.onAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(SurveyColor.redBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.horizontal, 12)
            }
        }
        .padding(.top, 6)
    }

    private var enclosureBanner: some View {
        HStack(spacing: 12) {
            Text("この範囲で絞る")
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
            Text("地図をタップ")
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
}
