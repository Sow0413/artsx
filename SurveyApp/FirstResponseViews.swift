import SwiftUI
import SurveyCore
import UIKit

/// SOS か転倒のあと、最寄りと迎えと 119 の読み上げを出す。電話はボタンを押したときだけ。
struct FirstResponseCard: View {
    @ObservedObject var field: FieldModel

    var body: some View {
        if let episode = field.firstEpisode, episode.active, let view = field.firstView {
            VStack(alignment: .leading, spacing: 8) {
                Text(view.headline)
                    .font(.system(size: 28, weight: .black))
                    .minimumScaleFactor(0.4)
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(view.headline)
                Text(view.progress)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                Text(FirstCall.cardNote)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.white)
                if view.nearestOpen {
                    dutyButton("担当になる") { field.acceptNearestDuty() }
                }
                if view.greeterOpen {
                    dutyButton("迎えに行く") { field.acceptGreeterDuty() }
                } else if episode.greeterAcceptedAt == nil, episode.victimID != field.crew.deviceID {
                    dutyButton("自分が迎えに行く") { field.takeGreeterDuty() }
                    ForEach(field.crew.peers.filter { $0.id != episode.victimID && $0.id != field.crew.deviceID }) { peer in
                        dutyButton("\(peer.name)を迎えに割り当てる") {
                            field.assignGreeter(id: peer.id, name: peer.name)
                        }
                    }
                }
                Text(AidChecklist.note)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(AidCheck.allCases, id: \.self) { item in
                    checkRow(item, answer: view.checklist.answer(item))
                }
                if field.aidArrows.isEmpty {
                    Text("AED・担架・救急箱は未登録")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Color.white)
                } else {
                    ForEach(field.aidArrows) { arrow in
                        Text(arrow.text)
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(Color.white)
                    }
                }
                dutyButton("119の読み上げ") { field.openReadout119() }
                Button("初動を閉じる") { field.endFirst() }
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            .padding(12)
            .background(SurveyColor.red)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .sheet(isPresented: $field.showsReadout119) {
                Readout119Sheet(field: field)
            }
        }
    }

    private func dutyButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 18, weight: .black))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(SurveyColor.amber)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func checkRow(_ item: AidCheck, answer: Bool?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.prompt)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                checkButton("はい", selected: answer == true) { field.setAidCheck(item, answer: true) }
                checkButton("いいえ", selected: answer == false) { field.setAidCheck(item, answer: false) }
            }
        }
    }

    private func checkButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 16, weight: .black))
            .foregroundStyle(selected ? SurveyColor.red : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color.white.opacity(selected ? 0.95 : 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct Readout119Sheet: View {
    @ObservedObject var field: FieldModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let site = field.drawing.project?.siteAid ?? .empty
        let position = field.workingReading.position
        let plottable = position?.isPlottable == true
        let lines = Readout119.lines(
            site: site,
            latitude: plottable ? position?.latitudeDegrees : nil,
            longitude: plottable ? position?.longitudeDegrees : nil
        )
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(SOSCall.disclaimer)
                        .font(.system(size: 20, weight: .black))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Readout119.idleNote)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(SurveyColor.amber)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 22, weight: .heavy))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("119に電話する") {
                        field.noteCall119()
                        guard let url = URL(string: "tel:119") else { return }
                        UIApplication.shared.open(url)
                    }
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(SurveyColor.red)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel("119に電話する。本人が発信する")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(SurveyColor.background)
            .navigationTitle("119の読み上げ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct SiteAidEditor: View {
    @ObservedObject var field: FieldModel
    @State private var address = ""
    @State private var landmark = ""
    @State private var entrance = ""
    @State private var hospital = ""
    @State private var contactName = ""
    @State private var contactPhone = ""

    var body: some View {
        let aid = field.drawing.project?.siteAid ?? .empty
        VStack(alignment: .leading, spacing: 6) {
            Text("初動")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(SurveyColor.muted)
            Text(FirstCall.cardNote)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            TextField("現場の住所", text: $address)
                .textFieldStyle(.roundedBorder)
            TextField("目印", text: $landmark)
                .textFieldStyle(.roundedBorder)
            TextField("救急車の進入口", text: $entrance)
                .textFieldStyle(.roundedBorder)
            TextField("最寄り救急病院", text: $hospital)
                .textFieldStyle(.roundedBorder)
            Button("住所を保存") { saveText(existing: aid) }
                .buttonStyle(SurveyPlainButton())
            Text("今の位置に置く")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(SurveyColor.muted)
            HStack {
                ForEach([AidPointKind.aed, .stretcher, .kit], id: \.self) { kind in
                    Button(kind.label) { field.addAidPoint(kind) }
                        .buttonStyle(SurveyPlainButton())
                }
            }
            HStack {
                Button(AidPointKind.entrance.label) { field.addAidPoint(.entrance) }
                    .buttonStyle(SurveyPlainButton())
                Button(AidPointKind.hospital.label) { field.addAidPoint(.hospital) }
                    .buttonStyle(SurveyPlainButton())
            }
            ForEach(aid.points) { point in
                HStack {
                    Text(point.kind.label)
                        .font(.system(size: 14, weight: .heavy))
                    Spacer()
                    Button("外す") { field.removeAidPoint(point.id) }
                        .buttonStyle(SurveyPlainButton())
                }
            }
            TextField("連絡先の名前", text: $contactName)
                .textFieldStyle(.roundedBorder)
            TextField("電話番号", text: $contactPhone)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.phonePad)
            Button("連絡先を足す") {
                field.addAidContact(name: contactName, phone: contactPhone)
                contactName = ""
                contactPhone = ""
            }
            .buttonStyle(SurveyPlainButton())
            ForEach(aid.contacts) { contact in
                HStack {
                    Text("\(contact.name) \(contact.phone)")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button("外す") { field.removeAidContact(contact.id) }
                        .buttonStyle(SurveyPlainButton())
                }
            }
            Text("地図に名前と矢印を出します。119への電話は読み上げ画面で、押したときだけ発信します。")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SurveyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { load(aid) }
    }

    private func load(_ aid: SiteAid) {
        address = aid.address
        landmark = aid.landmark
        entrance = aid.ambulanceEntrance
        hospital = aid.hospitalName
    }

    private func saveText(existing: SiteAid) {
        var aid = existing
        aid.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        aid.landmark = landmark.trimmingCharacters(in: .whitespacesAndNewlines)
        aid.ambulanceEntrance = entrance.trimmingCharacters(in: .whitespacesAndNewlines)
        aid.hospitalName = hospital.trimmingCharacters(in: .whitespacesAndNewlines)
        field.saveSiteAid(aid)
    }
}
