import SwiftUI
import SurveyCore

struct PointTableSheet: View {
    @ObservedObject var drawing: DrawingSession
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var table: PointTable?
    @State private var notice: String?

    init(drawing: DrawingSession, onSaved: @escaping () -> Void) {
        _drawing = ObservedObject(wrappedValue: drawing)
        self.onSaved = onSaved
        _table = State(initialValue: drawing.pointTable)
        _notice = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if let table {
                    summary(table)
                    Toggle("先頭行は見出し", isOn: headerBinding)
                        .font(SurveyType(16, .heavy))
                        .tint(SurveyColor.amber)
                    ScrollView([.horizontal, .vertical]) {
                        grid(table)
                            .padding(.bottom, 8)
                    }
                    if let notice {
                        Text(notice)
                            .font(SurveyType(15, .heavy))
                            .foregroundStyle(SurveyColor.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("この内容で保存") { save() }
                        .buttonStyle(SurveyPlainButton())
                }
            }
            .padding(16)
            .background(SurveyColor.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .font(SurveyType(17, .heavy))
                }
            }
        }
        .modifier(SurveyScheme())
        .onAppear {
            if table == nil { table = drawing.pointTable }
        }
    }

    private var title: String {
        let name = table?.fileName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "座標" : name
    }

    private var headerBinding: Binding<Bool> {
        Binding(
            get: { table?.hasHeader ?? false },
            set: { value in
                mutate { $0.hasHeader = value }
            }
        )
    }

    private func summary(_ table: PointTable) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(table.encodingName) · \(table.delimiter.label) · \(table.rows.count)行")
                .font(SurveyType(13, .semibold))
                .foregroundStyle(SurveyColor.muted)
            if let warning = table.axisWarning {
                Text(warning)
                    .font(SurveyType(15, .heavy))
                    .foregroundStyle(SurveyColor.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !table.issues.isEmpty {
                Text("読めない行 \(table.issues.count)。空では消しません。")
                    .font(SurveyType(15, .heavy))
                    .foregroundStyle(SurveyColor.amber)
            }
        }
    }

    private func grid(_ table: PointTable) -> some View {
        let columns = table.columnCount
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<columns, id: \.self) { column in
                    Picker("列", selection: roleBinding(column)) {
                        ForEach(PointColumnRole.allCases, id: \.self) { role in
                            Text(role.label).tag(role)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 112, height: 44)
                }
            }
            ForEach(Array(table.rows.indices), id: \.self) { row in
                rowView(table, row: row, columns: columns)
            }
        }
    }

    private func rowView(_ table: PointTable, row: Int, columns: Int) -> some View {
        let issue = table.issues.first { $0.row == row }
        let header = table.hasHeader && row == 0
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                ForEach(0..<columns, id: \.self) { column in
                    let cell = cellAt(table, row: row, column: column)
                    TextField("", text: cellBinding(row: row, column: column))
                        .font(SurveyType(16, .heavy, mono: true))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 112)
                        .padding(2)
                        .background(cellBackground(cell: cell, issue: issue != nil, header: header))
                }
            }
            if let issue {
                Text("\(row + 1)行目 \(issue.message)")
                    .font(SurveyType(13, .heavy))
                    .foregroundStyle(SurveyColor.amber)
            }
        }
    }

    private func cellBackground(cell: PointTableCell, issue: Bool, header: Bool) -> Color {
        if cell.isLowConfidence { return SurveyColor.yellowBackground }
        if issue { return SurveyColor.amberBackground }
        if header { return SurveyColor.card }
        return Color.clear
    }

    private func roleBinding(_ column: Int) -> Binding<PointColumnRole> {
        Binding(
            get: {
                guard let table, table.roles.indices.contains(column) else { return .ignore }
                return table.roles[column]
            },
            set: { role in
                mutate { current in
                    while current.roles.count <= column { current.roles.append(.ignore) }
                    current.roles[column] = role
                }
            }
        )
    }

    private func cellBinding(row: Int, column: Int) -> Binding<String> {
        Binding(
            get: {
                guard let table else { return "" }
                return cellAt(table, row: row, column: column).text
            },
            set: { text in
                mutate { current in
                    while current.rows.count <= row { current.rows.append([]) }
                    while current.rows[row].count <= column {
                        current.rows[row].append(PointTableCell(text: ""))
                    }
                    current.rows[row][column].text = text
                    current.rows[row][column].confidence = nil
                }
            }
        )
    }

    private func cellAt(_ table: PointTable, row: Int, column: Int) -> PointTableCell {
        guard table.rows.indices.contains(row), table.rows[row].indices.contains(column) else {
            return PointTableCell(text: "")
        }
        return table.rows[row][column]
    }

    private func mutate(_ body: (inout PointTable) -> Void) {
        guard var current = table else { return }
        body(&current)
        table = PointTableReader.evaluate(current, zone: drawing.zone)
    }

    private func save() {
        guard let table else { return }
        if let error = drawing.confirmPointTable(table) {
            notice = error
            return
        }
        onSaved()
        dismiss()
    }
}
