import SwiftUI
import SurveyCore

struct ProjectListSheet: View {
    @ObservedObject var field: FieldModel
    @ObservedObject var drawing: DrawingSession
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var place = ""
    @State private var date = ""
    @State private var rename = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("名前", text: $name)
                        .textFieldStyle(.roundedBorder)
                    TextField("場所", text: $place)
                        .textFieldStyle(.roundedBorder)
                    TextField("日付", text: $date)
                        .textFieldStyle(.roundedBorder)
                    Button("作る") {
                        drawing.createProject(named: name, place: place, workDate: date)
                        name = ""
                    }
                    .buttonStyle(SurveyPlainButton())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    ForEach(drawing.projects) { project in
                        projectRow(project)
                    }
                }
                .padding(16)
            }
            .background(SurveyColor.background)
            .navigationTitle("現場")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                        .font(SurveyType(17, .heavy))
                }
            }
        }
        .modifier(SurveyScheme())
        .onAppear {
            if date.isEmpty { date = Self.today() }
            rename = drawing.project?.name ?? ""
        }
    }

    private func projectRow(_ project: SurveyProject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                drawing.select(project)
                rename = project.name
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(SurveyType(18, .heavy))
                    Text([project.place, project.listDate].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  "))
                        .font(SurveyType(14, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12)
                .foregroundStyle(SurveyColor.text)
            }
            .buttonStyle(.plain)
            .background(
                drawing.project?.id == project.id ? SurveyColor.blue.opacity(0.18) : SurveyColor.card,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            if drawing.project?.id == project.id {
                TextField("名前", text: $rename)
                    .textFieldStyle(.roundedBorder)
                Button("名前を変える") { drawing.renameProject(to: rename) }
                    .buttonStyle(SurveyPlainButton())
                ForEach(project.drawings, id: \.fileName) { item in
                    Button(item.fileName) { drawing.openDrawing(named: item.fileName) }
                        .buttonStyle(SurveyPlainButton())
                }
                if let place = project.place, !place.isEmpty {
                    let days = field.recordDays(for: place)
                    if !days.isEmpty {
                        Text(days.joined(separator: "  "))
                            .font(SurveyType(14, .semibold))
                            .foregroundStyle(SurveyColor.muted)
                    }
                }
            }
        }
    }

    private static func today() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
