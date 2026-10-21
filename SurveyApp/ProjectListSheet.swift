import SwiftUI
import SurveyCore

struct ProjectListSheet: View {
    @ObservedObject var field: FieldModel
    @ObservedObject var drawing: DrawingSession
    @Environment(\.dismiss) private var dismiss
    @State private var showsTrash = false
    @State private var pending: DeleteTarget?
    @State private var name = ""
    @State private var date = ""
    @State private var prefecture: String?
    @State private var area: String?
    @State private var zone: Int?
    @State private var manual = false

    var body: some View {
        NavigationStack {
            Group {
                if showsTrash {
                    trashList
                } else {
                    projectList
                }
            }
            .scrollContentBackground(.hidden)
            .background(SurveyColor.background)
            .navigationTitle(showsTrash ? "ゴミ箱" : "現場")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(showsTrash ? "現場" : "閉じる") {
                        if showsTrash { showsTrash = false } else { dismiss() }
                    }
                    .font(SurveyType(17, .heavy))
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !showsTrash {
                        Button("ゴミ箱") { showsTrash = true }
                            .font(SurveyType(17, .heavy))
                    }
                }
            }
            .confirmationDialog("削除しますか。30日はゴミ箱から戻せます。", isPresented: pendingPresented, titleVisibility: .visible) {
                Button("削除", role: .destructive) { commitDelete() }
                Button("キャンセル", role: .cancel) { pending = nil }
            }
        }
        .modifier(SurveyScheme())
        .modifier(ProjectSheetWidth())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(SurveyColor.background)
        .onAppear {
            if date.isEmpty { date = Self.today() }
            drawing.reload()
        }
    }

    private var pendingPresented: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private var projectList: some View {
        List {
            if let message = drawing.message, !message.isEmpty {
                Section {
                    Text(message)
                        .font(SurveyType(15, .semibold))
                        .foregroundStyle(SurveyColor.text)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .listRowBackground(SurveyColor.card)
                }
            }
            Section {
                labeledField("名前", text: $name)
                NavigationLink {
                    ZoneLocationPicker(
                        prefecture: prefecture,
                        area: area,
                        zone: zone,
                        manual: manual,
                        onChange: { nextPrefecture, nextArea, nextZone, nextManual in
                            prefecture = nextPrefecture
                            area = nextArea
                            zone = nextZone
                            manual = nextManual
                        }
                    )
                } label: {
                    valueRow("場所", value: draftLocation)
                }
                labeledField("日付", text: $date)
                Button(action: create) {
                    Text("作る")
                        .font(SurveyType(20, .heavy))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? SurveyColor.card : SurveyColor.blue)
                        .foregroundStyle(SurveyColor.onAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .listRowBackground(Color.clear)
            } header: {
                sectionTitle("新しい現場")
            }
            Section {
                if drawing.projects.isEmpty {
                    Text("まだ現場がありません。")
                        .font(SurveyType(16, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .frame(minHeight: 44)
                        .listRowBackground(SurveyColor.card)
                }
                ForEach(drawing.projects) { project in
                    NavigationLink {
                        ProjectEditor(field: field, drawing: drawing, projectID: project.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                                .font(SurveyType(18, .heavy))
                                .foregroundStyle(SurveyColor.text)
                            Text(projectSubtitle(project))
                                .font(SurveyType(14, .semibold))
                                .foregroundStyle(SurveyColor.muted)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .listRowBackground(drawing.project?.id == project.id ? SurveyColor.blue.opacity(0.18) : SurveyColor.card)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("削除", role: .destructive) { pending = .project(project.id) }
                    }
                }
            } header: {
                sectionTitle("現場")
            }
        }
        .listStyle(.insetGrouped)
    }

    private var trashList: some View {
        List {
            if drawing.trashed.isEmpty {
                Text("ゴミ箱は空です。")
                    .font(SurveyType(16, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .frame(minHeight: 44)
                    .listRowBackground(SurveyColor.card)
            }
            ForEach(drawing.trashed) { item in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(SurveyType(18, .heavy))
                            .foregroundStyle(SurveyColor.text)
                        Text(trashDetail(item))
                            .font(SurveyType(14, .semibold))
                            .foregroundStyle(SurveyColor.muted)
                    }
                    Spacer(minLength: 8)
                    Button("戻す") { drawing.restoreTrash(id: item.id) }
                        .font(SurveyType(16, .heavy))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .frame(minHeight: 44)
                .listRowBackground(SurveyColor.card)
            }
        }
        .listStyle(.insetGrouped)
    }

    private var draftLocation: String {
        guard let zone else { return "選ぶ" }
        if let prefecture {
            return PlaneZoneCatalog.summary(prefecture: prefecture, area: area, zone: zone)
        }
        return PlaneRectangular.zone(zone)?.romanLabel ?? "\(zone)系"
    }

    private func create() {
        drawing.createProject(
            named: name,
            workDate: date,
            prefecture: prefecture,
            area: area,
            zone: zone,
            manualZone: manual
        )
        name = ""
        prefecture = nil
        area = nil
        zone = nil
        manual = false
    }

    private func commitDelete() {
        switch pending {
        case .project(let id):
            drawing.trashProject(id: id)
        case .drawing(let projectID, let fileName):
            drawing.trashDrawing(fileName: fileName, projectID: projectID)
        case nil:
            break
        }
        pending = nil
    }

    private func projectSubtitle(_ project: SurveyProject) -> String {
        [locationLine(project), project.listDate].filter { !$0.isEmpty }.joined(separator: "  ")
    }

    private func trashDetail(_ item: ProjectTrashItem) -> String {
        let kind = item.kind == .project ? "現場" : "図面"
        return "\(kind)  あと\(item.daysLeft(at: Date()))日"
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(SurveyType(13, .heavy))
            .foregroundStyle(SurveyColor.muted)
            .textCase(nil)
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SurveyType(13, .heavy))
                .foregroundStyle(SurveyColor.muted)
            TextField(title, text: text)
                .font(SurveyType(18, .heavy))
                .foregroundStyle(SurveyColor.text)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .listRowBackground(SurveyColor.card)
    }

    private func valueRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(SurveyType(13, .heavy))
                .foregroundStyle(SurveyColor.muted)
            Text(value)
                .font(SurveyType(18, .heavy))
                .foregroundStyle(SurveyColor.text)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private static func today() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

private struct ProjectEditor: View {
    @ObservedObject var field: FieldModel
    @ObservedObject var drawing: DrawingSession
    let projectID: String
    @State private var name = ""
    @State private var date = ""
    @State private var pending: DeleteTarget?

    private var project: SurveyProject? {
        drawing.projects.first { $0.id == projectID } ?? (drawing.project?.id == projectID ? drawing.project : nil)
    }

    var body: some View {
        List {
            if let project {
                identitySection(project)
                recordSection(project)
                drawingSection(project)
            } else {
                Text("この現場はゴミ箱にあります。")
                    .font(SurveyType(16, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .listRowBackground(SurveyColor.card)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SurveyColor.background)
        .navigationTitle(project?.name ?? "現場")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { sync() }
        .onDisappear { commitFields() }
        .onChange(of: project?.name) { _, _ in sync() }
        .onChange(of: project?.workDate) { _, _ in sync() }
        .confirmationDialog("削除しますか。30日はゴミ箱から戻せます。", isPresented: pendingPresented, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                if case .drawing(let id, let fileName) = pending {
                    drawing.trashDrawing(fileName: fileName, projectID: id)
                }
                pending = nil
            }
            Button("キャンセル", role: .cancel) { pending = nil }
        }
    }

    private func identitySection(_ project: SurveyProject) -> some View {
        Section {
            labeledField("名前", text: $name) {
                drawing.renameProject(id: projectID, to: name)
            }
            NavigationLink {
                ZoneLocationPicker(
                    prefecture: project.prefecture,
                    area: project.area,
                    zone: project.zone,
                    manual: project.manualZone == true,
                    onChange: { prefecture, area, zone, manual in
                        drawing.setProjectLocation(
                            id: projectID,
                            prefecture: prefecture,
                            area: area,
                            zone: zone,
                            manual: manual
                        )
                    }
                )
            } label: {
                valueRow("場所", value: locationLine(project))
            }
            labeledField("日付", text: $date) {
                drawing.setProjectDate(id: projectID, to: date)
            }
            Button("開く") {
                if let fresh = self.project { drawing.select(fresh) }
            }
            .font(SurveyType(18, .heavy))
            .frame(maxWidth: .infinity, minHeight: 44)
            .listRowBackground(SurveyColor.card)
        } header: {
            sectionTitle("現場")
        }
    }

    @ViewBuilder
    private func recordSection(_ project: SurveyProject) -> some View {
        if let place = project.place, !place.isEmpty {
            let days = field.recordDays(for: place)
            if !days.isEmpty {
                Section {
                    Text(days.joined(separator: "  "))
                        .font(SurveyType(14, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .frame(minHeight: 44, alignment: .leading)
                        .listRowBackground(SurveyColor.card)
                } header: {
                    sectionTitle("記録")
                }
            }
        }
    }

    private func drawingSection(_ project: SurveyProject) -> some View {
        Section {
            if project.drawings.isEmpty {
                Text("図面はまだありません。")
                    .font(SurveyType(16, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .frame(minHeight: 44)
                    .listRowBackground(SurveyColor.card)
            }
            ForEach(project.drawings, id: \.fileName) { item in
                drawingLink(item, project: project)
            }
        } header: {
            sectionTitle("図面")
        }
    }

    private func drawingLink(_ item: ProjectDrawing, project: SurveyProject) -> some View {
        NavigationLink {
            DrawingEditor(drawing: drawing, projectID: projectID, fileName: item.fileName)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(SurveyType(18, .heavy))
                    .foregroundStyle(SurveyColor.text)
                    .lineLimit(1)
                Text(drawingLine(item, project: project))
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .listRowBackground(SurveyColor.card)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("削除", role: .destructive) {
                pending = .drawing(projectID: projectID, fileName: item.fileName)
            }
        }
    }

    private var pendingPresented: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private func sync() {
        name = project?.name ?? ""
        date = project?.workDate ?? project?.listDate ?? ""
    }

    private func commitFields() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != project?.name {
            drawing.renameProject(id: projectID, to: trimmed)
        }
        let stored = project?.workDate ?? project?.listDate ?? ""
        if date != stored {
            drawing.setProjectDate(id: projectID, to: date)
        }
    }
}

private struct DrawingEditor: View {
    @ObservedObject var drawing: DrawingSession
    let projectID: String
    let fileName: String
    @State private var name = ""

    private var project: SurveyProject? {
        drawing.projects.first { $0.id == projectID } ?? (drawing.project?.id == projectID ? drawing.project : nil)
    }

    private var item: ProjectDrawing? {
        project?.drawings.first { $0.fileName == fileName }
    }

    var body: some View {
        List {
            if let item, let project {
                Section {
                    labeledField("名前", text: $name) {
                        drawing.renameDrawing(projectID: projectID, fileName: fileName, to: name)
                    }
                    NavigationLink {
                        ZoneLocationPicker(
                            prefecture: item.prefecture ?? project.prefecture,
                            area: item.prefecture != nil ? item.area : project.area,
                            zone: item.zone ?? project.zone,
                            manual: item.zone != nil && item.zone != PlaneZoneCatalog.zone(
                                prefecture: item.prefecture ?? project.prefecture ?? "",
                                area: item.prefecture != nil ? item.area : project.area
                            ),
                            onChange: { prefecture, area, zone, manual in
                                drawing.setDrawingLocation(
                                    projectID: projectID,
                                    fileName: fileName,
                                    prefecture: prefecture,
                                    area: area,
                                    zone: zone,
                                    manual: manual
                                )
                            }
                        )
                    } label: {
                        valueRow("場所", value: drawingLine(item, project: project))
                    }
                    Text(item.fileName)
                        .font(SurveyType(14, .semibold))
                        .foregroundStyle(SurveyColor.muted)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .listRowBackground(SurveyColor.card)
                } header: {
                    sectionTitle("図面")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SurveyColor.background)
        .navigationTitle(item?.title ?? "図面")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = item?.displayName ?? item?.fileName ?? "" }
        .onDisappear {
            let stored = item?.displayName ?? item?.fileName ?? ""
            if name != stored {
                drawing.renameDrawing(projectID: projectID, fileName: fileName, to: name)
            }
        }
        .onChange(of: item?.displayName) { _, _ in
            name = item?.displayName ?? item?.fileName ?? ""
        }
    }
}

private struct ZoneLocationPicker: View {
    let prefecture: String?
    let area: String?
    let zone: Int?
    let manual: Bool
    let onChange: (String?, String?, Int?, Bool) -> Void

    var body: some View {
        List {
            if let zone {
                Section {
                    Text(summary(zone))
                        .font(SurveyType(18, .heavy))
                        .foregroundStyle(SurveyColor.text)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .listRowBackground(SurveyColor.card)
                } header: {
                    sectionTitle("場所")
                }
            }
            Section {
                ForEach(PlaneZoneCatalog.prefectures) { item in
                    if item.needsArea {
                        NavigationLink {
                            areaList(item)
                        } label: {
                            HStack(spacing: 8) {
                                Text(item.name)
                                    .font(SurveyType(18, .heavy))
                                    .foregroundStyle(SurveyColor.text)
                                Spacer(minLength: 8)
                                if prefecture == item.name {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(SurveyColor.blue)
                                }
                            }
                            .frame(minHeight: 44)
                        }
                    } else {
                        Button {
                            onChange(item.name, nil, item.zones.first, false)
                        } label: {
                            HStack(spacing: 8) {
                                Text(item.name)
                                    .font(SurveyType(18, .heavy))
                                Spacer(minLength: 8)
                                if let number = item.zones.first {
                                    Text(PlaneRectangular.zone(number)?.romanLabel ?? "\(number)系")
                                        .font(SurveyType(16, .semibold))
                                        .foregroundStyle(SurveyColor.muted)
                                }
                                if prefecture == item.name, !manual {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(SurveyColor.blue)
                                }
                            }
                            .foregroundStyle(SurveyColor.text)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                sectionTitle("都道府県")
            }
            Section {
                ForEach(Array(1...19), id: \.self) { number in
                    Button {
                        onChange(prefecture, area, number, true)
                    } label: {
                        HStack {
                            Text(PlaneRectangular.zone(number)?.romanLabel ?? "\(number)系")
                                .font(SurveyType(18, .heavy))
                            Spacer()
                            if zone == number, manual {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(SurveyColor.blue)
                            }
                        }
                        .foregroundStyle(SurveyColor.text)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(SurveyColor.card)
                }
            } header: {
                sectionTitle("系を指定")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SurveyColor.background)
        .navigationTitle("場所")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func areaList(_ item: PrefectureZones) -> some View {
        List {
            Section {
                ForEach(item.areas) { area in
                    Button {
                        onChange(item.name, area.name, area.zone, false)
                    } label: {
                        HStack(alignment: .center, spacing: 8) {
                            Text(area.name)
                                .font(SurveyType(16, .heavy))
                                .lineLimit(3)
                                .minimumScaleFactor(0.7)
                            Spacer(minLength: 8)
                            Text(PlaneRectangular.zone(area.zone)?.romanLabel ?? "\(area.zone)系")
                                .font(SurveyType(16, .semibold))
                                .foregroundStyle(SurveyColor.muted)
                            if prefecture == item.name, self.area == area.name, !manual {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(SurveyColor.blue)
                            }
                        }
                        .foregroundStyle(SurveyColor.text)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(SurveyColor.card)
                }
            } header: {
                sectionTitle(item.name)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SurveyColor.background)
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summary(_ zone: Int) -> String {
        if let prefecture {
            return PlaneZoneCatalog.summary(prefecture: prefecture, area: area, zone: zone)
        }
        return PlaneRectangular.zone(zone)?.romanLabel ?? "\(zone)系"
    }
}

private enum DeleteTarget: Identifiable {
    case project(String)
    case drawing(projectID: String, fileName: String)

    var id: String {
        switch self {
        case .project(let id): return "project-\(id)"
        case .drawing(let projectID, let fileName): return "drawing-\(projectID)-\(fileName)"
        }
    }
}

private func locationLine(_ project: SurveyProject) -> String {
    if let zone = project.zone, let prefecture = project.prefecture, !prefecture.isEmpty {
        return PlaneZoneCatalog.summary(prefecture: prefecture, area: project.area, zone: zone)
    }
    if let zone = project.zone, project.manualZone == true {
        return PlaneRectangular.zone(zone)?.romanLabel ?? "\(zone)系"
    }
    if let place = project.place, !place.isEmpty { return place }
    return "選ぶ"
}

private func drawingLine(_ item: ProjectDrawing, project: SurveyProject) -> String {
    let prefecture = item.prefecture ?? project.prefecture
    let area = item.prefecture != nil ? item.area : project.area
    let zone = item.zone ?? project.zone
    if let zone, let prefecture, !prefecture.isEmpty {
        return PlaneZoneCatalog.summary(prefecture: prefecture, area: area, zone: zone)
    }
    if let zone {
        return PlaneRectangular.zone(zone)?.romanLabel ?? "\(zone)系"
    }
    return "選ぶ"
}

private func sectionTitle(_ title: String) -> some View {
    Text(title)
        .font(SurveyType(13, .heavy))
        .foregroundStyle(SurveyColor.muted)
        .textCase(nil)
}

private func valueRow(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title)
            .font(SurveyType(13, .heavy))
            .foregroundStyle(SurveyColor.muted)
        Text(value)
            .font(SurveyType(18, .heavy))
            .foregroundStyle(SurveyColor.text)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
}

private func labeledField(_ title: String, text: Binding<String>, commit: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(SurveyType(13, .heavy))
            .foregroundStyle(SurveyColor.muted)
        TextField(title, text: text)
            .font(SurveyType(18, .heavy))
            .foregroundStyle(SurveyColor.text)
            .onSubmit(commit)
    }
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .listRowBackground(SurveyColor.card)
}

private struct ProjectSheetWidth: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.page)
        } else {
            content
        }
    }
}
