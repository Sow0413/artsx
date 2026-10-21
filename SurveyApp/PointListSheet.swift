import SwiftUI
import SurveyCore

struct PointListRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case record(String)
        case observation(String, String)
        case drawing(String)
    }

    var id: String
    var name: String
    var group: String
    var detail: String
    var kind: Kind
}

struct PointListSheet: View {
    @ObservedObject var field: FieldModel
    @State private var pendingDelete = false

    var body: some View {
        NavigationStack {
            Group {
                if field.showsTrash {
                    trashList
                } else {
                    pointList
                }
            }
            .background(SurveyColor.background)
            .navigationTitle(field.showsTrash ? "ゴミ箱" : listTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { field.showsPointList = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .confirmationDialog("削除しますか。30日はゴミ箱から戻せます。", isPresented: $pendingDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive) { field.trashSelectedPoint() }
                Button("キャンセル", role: .cancel) {}
            }
        }
        .modifier(SurveyScheme())
    }

    private var listTitle: String {
        switch field.tab {
        case .map: return "記録"
        case .drawing: return "図面"
        case .survey: return "測量"
        case .build: return "施工"
        }
    }

    private var pointList: some View {
        let sections = field.pointListSections().filter { !$0.rows.isEmpty }
        return List {
            if sections.isEmpty {
                Text("まだ点がありません。")
                    .font(SurveyType(16, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .listRowBackground(SurveyColor.background)
            }
            ForEach(sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.rows) { row in
                        rowButton(row)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("削除", role: .destructive) {
                                    field.selectedPointListID = row.id
                                    pendingDelete = true
                                }
                            }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var trashList: some View {
        let rows = field.trashRows()
        return List {
            if rows.isEmpty {
                Text("ゴミ箱は空です。")
                    .font(SurveyType(16, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .listRowBackground(SurveyColor.background)
            }
            ForEach(rows) { item in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(SurveyType(18, .heavy))
                        Text("あと\(item.daysLeft(at: Date()))日")
                            .font(SurveyType(14, .semibold))
                            .foregroundStyle(SurveyColor.muted)
                    }
                    Spacer(minLength: 8)
                    Button("戻す") { field.restoreTrash(item.id) }
                        .font(SurveyType(16, .heavy))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .listRowBackground(SurveyColor.card)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func rowButton(_ row: PointListRow) -> some View {
        let selected = field.selectedPointListID == row.id
        return Button {
            field.selectedPointListID = row.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(SurveyType(18, .heavy))
                Text(row.detail)
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                if selected {
                    ForEach(field.bookHistory(for: row.name).prefix(5)) { revision in
                        Text("履歴 \(historyLine(revision))")
                            .font(SurveyType(13, .semibold))
                            .foregroundStyle(SurveyColor.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selected ? SurveyColor.blue.opacity(0.18) : SurveyColor.card)
    }

    private func historyLine(_ revision: ArchivedBookEntry) -> String {
        let height = revision.entry.deliveredHeightMeters.map { "標高 \(SurveyHeight.meters($0))m" } ?? "高さ —"
        return "\(Self.stamp.string(from: revision.replacedAt)) \(height)"
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button(field.showsTrash ? "一覧" : "ゴミ箱") {
                field.showsTrash.toggle()
            }
            .buttonStyle(SurveyPlainButton())
            if !field.showsTrash {
                Button("取り直し") { field.beginRetake() }
                    .buttonStyle(SurveyPlainButton())
                    .disabled(field.selectedPointRow() == nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(SurveyColor.bar)
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
