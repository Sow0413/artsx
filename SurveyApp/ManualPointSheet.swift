import SwiftUI
import SurveyCore

struct ManualPointSheet: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case geographic
        case plane

        var id: String { rawValue }
        var label: String { self == .geographic ? "緯度経度" : "平面直角" }
    }

    private enum EntryField: Hashable {
        case name
        case latitude
        case longitude
        case northing
        case easting
        case height
    }

    @ObservedObject var field: FieldModel
    @State private var name = ""
    @State private var mode: Mode = .geographic
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var northing = ""
    @State private var easting = ""
    @State private var height = ""
    @State private var notice: String?
    @State private var oneShot = false
    @FocusState private var focus: EntryField?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    fieldRow("点名") {
                        TextField("K-1", text: $name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .name)
                            .onSubmit { advance() }
                    }
                    Picker("入れ方", selection: $mode) {
                        ForEach(Mode.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(minHeight: 44)
                    if mode == .geographic {
                        numberRow("緯度", text: $latitude, field: .latitude, prompt: "36.77450")
                        numberRow("経度", text: $longitude, field: .longitude, prompt: "139.20081")
                    } else {
                        numberRow("X(北)", text: $northing, field: .northing, prompt: "-123868.150")
                        numberRow("Y(東)", text: $easting, field: .easting, prompt: "39019.370")
                    }
                    Text("十進はテンキー。度分秒や「緯度, 経度」は貼り付け。")
                        .font(SurveyType(13, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(counterpart)
                        .font(SurveyType(16, .heavy, mono: true))
                        .foregroundStyle(reading == nil ? SurveyColor.muted : SurveyColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    numberRow("標高", text: $height, field: .height, prompt: "空でもよい")
                    if let notice {
                        Text(notice)
                            .font(SurveyType(15, .heavy))
                            .foregroundStyle(SurveyColor.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("保存") { save() }
                        .buttonStyle(SurveyPlainButton())
                }
                .padding(16)
            }
            .background(SurveyColor.background)
            .navigationTitle(oneShot && name == "ここ" ? "ここ" : "点を登録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { field.showsManualPoint = false }
                        .font(SurveyType(17, .heavy))
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Button("−") { insertMinus() }
                        .font(SurveyType(20, .heavy))
                    Button("次へ") { advance() }
                        .font(SurveyType(17, .heavy))
                    Spacer()
                    Button("保存") { save() }
                        .font(SurveyType(17, .heavy))
                }
            }
        }
        .modifier(SurveyScheme())
        .onAppear(perform: load)
        .onChange(of: latitude) { _, value in absorb(value) }
        .onChange(of: longitude) { _, value in absorb(value) }
        .onChange(of: northing) { _, value in absorb(value) }
        .onChange(of: easting) { _, value in absorb(value) }
        .onChange(of: mode) { _, new in convert(to: new) }
    }

    private var coordinateText: String {
        switch mode {
        case .geographic:
            return "\(latitude), \(longitude)"
        case .plane:
            return "X \(northing) Y \(easting)"
        }
    }

    private var reading: ManualPointFix? {
        ManualPoint.parse(coordinateText, zone: field.drawing.zone)
    }

    private var counterpart: String {
        let empty = mode == .geographic
            ? latitude.trimmingCharacters(in: .whitespaces).isEmpty && longitude.trimmingCharacters(in: .whitespaces).isEmpty
            : northing.trimmingCharacters(in: .whitespaces).isEmpty && easting.trimmingCharacters(in: .whitespaces).isEmpty
        if empty { return "入れると、緯度経度と平面直角を並べます。" }
        return reading?.counterpart ?? "緯度経度か、平面直角の X Y にしてください。"
    }

    private func fieldRow(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SurveyType(13, .heavy))
                .foregroundStyle(SurveyColor.muted)
            content()
                .font(SurveyType(18, .heavy, mono: true))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func numberRow(_ title: String, text: Binding<String>, field: EntryField, prompt: String) -> some View {
        fieldRow(title) {
            TextField(prompt, text: text)
                .keyboardType(.decimalPad)
                .focused($focus, equals: field)
                .onSubmit { advance() }
        }
    }

    private func load() {
        let seeded = field.manualPointCoordinate.trimmingCharacters(in: .whitespacesAndNewlines)
        oneShot = !seeded.isEmpty
        if field.manualPointName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let last = field.drawing.fieldPoints.last { $0.origin == .manual }?.name
            name = last.map { PointNameSequence.next(after: $0) } ?? "1"
        } else {
            name = field.manualPointName
        }
        if let fix = ManualPoint.parse(seeded, zone: field.drawing.zone) {
            apply(fix)
        }
        focus = oneShot ? .height : .name
    }

    private func absorb(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = trimmed.split(whereSeparator: \.isWhitespace).count
        guard trimmed.contains(",") || trimmed.contains("°") || trimmed.contains("度") || pieces >= 2 else { return }
        guard let fix = ManualPoint.parse(trimmed, zone: field.drawing.zone) else { return }
        apply(fix)
    }

    private func apply(_ fix: ManualPointFix) {
        latitude = ManualPointFix.degrees(fix.latitudeDegrees)
        longitude = ManualPointFix.degrees(fix.longitudeDegrees)
        northing = ManualPointFix.meters(fix.northingMeters)
        easting = ManualPointFix.meters(fix.eastingMeters)
        mode = fix.kind == .plane ? .plane : .geographic
    }

    private func convert(to new: Mode) {
        switch new {
        case .plane:
            guard let fix = ManualPoint.parse("\(latitude), \(longitude)", zone: field.drawing.zone) else { return }
            northing = ManualPointFix.meters(fix.northingMeters)
            easting = ManualPointFix.meters(fix.eastingMeters)
        case .geographic:
            guard let fix = ManualPoint.parse("X \(northing) Y \(easting)", zone: field.drawing.zone) else { return }
            latitude = ManualPointFix.degrees(fix.latitudeDegrees)
            longitude = ManualPointFix.degrees(fix.longitudeDegrees)
        }
    }

    private func insertMinus() {
        func toggle(_ text: inout String) {
            if text.hasPrefix("-") {
                text.removeFirst()
            } else {
                text.insert("-", at: text.startIndex)
            }
        }
        switch focus {
        case .latitude: toggle(&latitude)
        case .longitude: toggle(&longitude)
        case .northing: toggle(&northing)
        case .easting: toggle(&easting)
        case .height: toggle(&height)
        default: break
        }
    }

    private func advance() {
        switch focus {
        case .name:
            focus = mode == .geographic ? .latitude : .northing
        case .latitude:
            focus = .longitude
        case .longitude, .easting:
            focus = .height
        case .northing:
            focus = .easting
        case .height, nil:
            save()
        }
    }

    private func save() {
        if let error = field.drawing.saveEnteredPoint(name: name, coordinate: coordinateText, heightText: height) {
            notice = error
            return
        }
        field.ensureMapCad()
        notice = nil
        if oneShot {
            field.tab = .map
            field.showsManualPoint = false
            return
        }
        name = PointNameSequence.next(after: name)
        latitude = ""
        longitude = ""
        northing = ""
        easting = ""
        height = ""
        focus = mode == .geographic ? .latitude : .northing
    }
}
