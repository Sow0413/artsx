import SwiftUI
import SurveyCore

private enum DeliverPage: Hashable {
    case drawing
    case scale
    case localize
    case cad
    case restore
    case coordinate

    var identifier: String {
        switch self {
        case .drawing: return "open-draw"
        case .scale: return "open-scale"
        case .localize: return "open-localize"
        case .cad: return "open-cad"
        case .restore: return "open-restore-points"
        case .coordinate: return "open-coordinate"
        }
    }
}

struct ExportTabView: View {
    @ObservedObject var field: FieldModel
    @State private var accuracyText = ""
    @State private var importedDay = ""
    @State private var deliverPath: [DeliverPage] = []

    private let listBottomClearance: CGFloat = 68 + 24

    var body: some View {
        if SurveyBuild.basicMode {
            futureEntrance
        } else {
            legacyExport
        }
    }

    private var futureEntrance: some View {
        NavigationStack(path: $deliverPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("図面を合わせて、点へ測設する。")
                        .font(SurveyType(18, .heavy))
                        .lineLimit(1)
                        .accessibilityIdentifier("purpose-deliver")
                    stepTile(order: 1, title: "図面を読み込む", systemImage: "doc", page: .drawing, status: field.projectSheet == nil ? "未着手" : "済", locked: false, later: false)
                    stepTile(order: 2, title: "図面の縮尺設定／2点割り付け", systemImage: "ruler", page: .scale, status: "2cm・1/10000", locked: field.projectSheet == nil, later: false)
                    stepTile(order: 3, title: "GNSSローカライズ", systemImage: "location.north.line", page: .localize, status: "3点以上", locked: false, later: false)
                    stepTile(order: 4, title: "CAD測設", systemImage: "square.and.pencil", page: .cad, status: "地図でタップ", locked: false, later: false)
                    Text("別の入口")
                        .font(SurveyType(18, .heavy))
                        .padding(.top, 8)
                    stepTile(order: nil, title: "データから点の復元", systemImage: "arrow.uturn.backward", page: .restore, status: "書き出しから", locked: false, later: false)
                    Text("測設")
                        .font(SurveyType(18, .heavy))
                        .padding(.top, 8)
                    stepTile(order: nil, title: "座標を打って測設", systemImage: "scope", page: .coordinate, status: "未着手", locked: false, later: false)
                }
                .padding(20)
                .padding(.bottom, listBottomClearance)
            }
            .accessibilityIdentifier("screen-export")
            .background(SurveyColor.background)
            .navigationTitle("出す")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(deliverPath.isEmpty ? .hidden : .visible, for: .navigationBar)
            .onAppear { field.refreshProjectSheet() }
            .navigationDestination(for: DeliverPage.self) { page in
                deliverPage(page)
            }
        }
        .foregroundStyle(SurveyColor.text)
    }

    private func stepTile(order: Int?, title: String, systemImage: String, page: DeliverPage, status: String, locked: Bool, later: Bool) -> some View {
        Button {
            deliverPath.append(page)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(locked ? SurveyColor.muted : SurveyColor.blue)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(order.map { "\($0) \(title)" } ?? title)
                        .font(SurveyType(18, .heavy))
                        .lineLimit(2)
                    Text(later ? "\(status)・次の版" : status)
                        .font(SurveyType(15, .heavy))
                        .foregroundStyle(locked ? SurveyColor.muted : SurveyColor.amber)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .foregroundStyle(SurveyColor.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(locked ? SurveyColor.line : SurveyColor.blue, lineWidth: locked ? 1 : 3)
            )
            .opacity(locked ? 0.72 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(page.identifier)
        .accessibilityLabel("\(title)。\(status)\(later ? "。次の版" : "")")
    }

    @ViewBuilder
    private func deliverPage(_ page: DeliverPage) -> some View {
        switch page {
        case .coordinate:
            BasicStakeoutCard(field: field)
                .navigationTitle("座標を打って測設")
                .navigationBarTitleDisplayMode(.inline)
                .deliverBack { deliverPath.removeLast() }
        case .drawing:
            SheetImportPage(field: field) {
                deliverPath.append(.scale)
            }
            .navigationTitle("図面を読み込む")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SurveyColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .deliverBack { deliverPath.removeLast() }
        case .scale:
            ScaleCheckPage(field: field)
                .navigationTitle("縮尺設定")
                .navigationBarTitleDisplayMode(.inline)
                .deliverBack { deliverPath.removeLast() }
        case .localize:
            LocalizePage(field: field)
                .navigationTitle("GNSSローカライズ")
                .navigationBarTitleDisplayMode(.inline)
                .deliverBack { deliverPath.removeLast() }
        case .cad:
            CadStakePage(field: field)
                .navigationTitle("CAD測設")
                .navigationBarTitleDisplayMode(.inline)
                .deliverBack { deliverPath.removeLast() }
        case .restore:
            RestorePointsPage(field: field)
                .navigationTitle("点の復元")
                .navigationBarTitleDisplayMode(.inline)
                .deliverBack { deliverPath.removeLast() }
        }
    }

    private var legacyExport: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("出す")
                    .font(SurveyType(28, .heavy))
                if !SurveyBuild.basicMode {
                ExtraEntryButton {
                    field.showsExtras = true
                }
                Text("無線、接近、転倒、SOS、災害、中継、統計はおまけです。既定ではオフで、測量の画面には出ません。")
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Text("受取手が今受け取れる形だけ出します。点群と3Dは点群フォルダに保存するだけで、ここには出しません。")
                    .font(SurveyType(16, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(CoordinateDelivery.pointCloudNote)
                    .font(SurveyType(14, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                filters
                let preview = field.bookPreview()
                Text("\(preview.count) 点")
                    .font(SurveyType(18, .heavy))
                names(preview.sample)
                ForEach(DeliveryFormat.allCases.filter { format in
                    !SurveyBuild.basicMode || format == .csv || format == .sima
                }) { format in
                    Button {
                        field.exportDelivery(format)
                    } label: {
                        Text(format.label)
                            .font(SurveyType(18, .heavy))
                            .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                            .background(SurveyColor.blue)
                            .foregroundStyle(SurveyColor.onAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                if let message = field.exportMessage {
                    Text(message)
                        .font(SurveyType(15, .heavy))
                        .foregroundStyle(SurveyColor.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let url = field.exportURL {
                    ShareLink(item: url) {
                        Text("共有シートで渡す")
                            .font(SurveyType(18, .heavy))
                            .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                            .background(SurveyColor.blue)
                            .foregroundStyle(SurveyColor.onAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Text("系\(field.drawing.zone)の平面直角座標で書きます。JGD2024 の元期補正は、まだ掛けていません。")
                    .font(SurveyType(13, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Color.clear
                    .frame(height: listBottomClearance)
                    .accessibilityHidden(true)
            }
            .padding(20)
        }
        .contentMargins(.bottom, listBottomClearance, for: .scrollContent)
        .safeAreaPadding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .accessibilityIdentifier("screen-export")
        .background(SurveyColor.background)
        .foregroundStyle(SurveyColor.text)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("座標簿の絞り込み")
                .font(SurveyType(18, .heavy))
            Text("条件はすべて同時に効きます。空欄は無視します。")
                .font(SurveyType(13, .semibold))
                .foregroundStyle(SurveyColor.muted)
            fieldRow("点名の頭") {
                TextField("T", text: prefixBinding)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            fieldRow("種類") {
                TextField("基準点", text: kindBinding)
                    .autocorrectionDisabled()
            }
            fieldRow("出典") {
                TextField("観測", text: sourceBinding)
                    .autocorrectionDisabled()
            }
            fieldRow("解段階") {
                Picker("解段階", selection: stageBinding) {
                    Text("指定しない").tag(-1)
                    Text("段階0以上").tag(0)
                    Text("段階1以上").tag(1)
                    Text("段階2以上").tag(2)
                    Text("段階3").tag(3)
                }
                .pickerStyle(.menu)
            }
            fieldRow("水平精度 m 以内") {
                TextField("0.03", text: $accuracyText)
                    .keyboardType(.decimalPad)
                    .autocorrectionDisabled()
                    .onChange(of: accuracyText) { _, value in
                        let trimmed = value.trimmingCharacters(in: .whitespaces)
                        field.bookQuery.maximumHorizontalMeters = trimmed.isEmpty ? nil : Double(trimmed)
                    }
            }
            fieldRow("取込日") {
                TextField("2026-10-20", text: $importedDay)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("book-imported-day")
                    .onChange(of: importedDay) { _, value in
                        let trimmed = value.trimmingCharacters(in: .whitespaces)
                        field.bookQuery.importedDay = trimmed.isEmpty ? nil : trimmed
                    }
            }
            if let bounds = field.bookQuery.bounds {
                Text(boundsLabel(bounds))
                    .font(SurveyType(13, .semibold, mono: true))
                    .fixedSize(horizontal: false, vertical: true)
                Button("範囲を外す") {
                    field.bookQuery.bounds = nil
                }
                .font(SurveyType(15, .heavy))
                .foregroundStyle(SurveyColor.amber)
            }
            HStack(spacing: 10) {
                Button("地図で範囲を囲む") {
                    field.beginBookEnclosure()
                }
                .font(SurveyType(15, .heavy))
                .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                .background(SurveyColor.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button("条件を消す") {
                    accuracyText = ""
                    importedDay = ""
                    field.clearBookFilters()
                }
                .font(SurveyType(15, .heavy))
                .frame(maxWidth: .infinity, minHeight: OutdoorContrast.primaryPoints)
                .background(SurveyColor.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SurveyColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func names(_ shown: [CoordinateBookEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if shown.isEmpty {
                Text("合う点がありません。")
                    .font(SurveyType(15, .semibold))
                    .foregroundStyle(SurveyColor.muted)
            } else {
                ForEach(Array(shown), id: \.name) { entry in
                    Text(entryLine(entry))
                        .font(SurveyType(14, .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func fieldRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SurveyType(13, .heavy))
                .foregroundStyle(SurveyColor.muted)
            content()
                .textFieldStyle(.roundedBorder)
        }
    }

    private var prefixBinding: Binding<String> {
        Binding(get: { field.bookQuery.namePrefix }, set: { field.bookQuery.namePrefix = $0 })
    }

    private var kindBinding: Binding<String> {
        Binding(get: { field.bookQuery.kind }, set: { field.bookQuery.kind = $0 })
    }

    private var sourceBinding: Binding<String> {
        Binding(get: { field.bookQuery.source }, set: { field.bookQuery.source = $0 })
    }

    private var stageBinding: Binding<Int> {
        Binding(
            get: { field.bookQuery.minimumStage?.rawValue ?? -1 },
            set: { field.bookQuery.minimumStage = PositionStage(rawValue: $0) }
        )
    }

    private func boundsLabel(_ bounds: GeoBounds) -> String {
        String(format: "N %.5f–%.5f  E %.5f–%.5f", bounds.south, bounds.north, bounds.west, bounds.east)
    }

    private func entryLine(_ entry: CoordinateBookEntry) -> String {
        let kind = entry.kind ?? "—"
        return "\(entry.name)  \(kind)  \(entry.source ?? "—")  \(solutionWord(entry))"
    }

    private func solutionWord(_ entry: CoordinateBookEntry) -> String {
        guard let solution = entry.solution else { return "—" }
        if entry.receiverLabel == "iPhone" { return "単独" }
        switch solution {
        case .rtkFix: return entry.receiverLabel == "CLAS" ? "CLAS" : "FIX"
        case .float: return "FLOAT"
        case .clas: return "CLAS"
        case .dgps: return "DGPS"
        case .standalone, .none: return "単独"
        }
    }
}

private extension View {
    func deliverBack(action: @escaping () -> Void) -> some View {
        navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: action) {
                        Label("戻る", systemImage: "chevron.left")
                            .font(SurveyType(18, .heavy))
                            .frame(minWidth: 56, minHeight: 56)
                    }
                    .accessibilityIdentifier("deliver-back")
                }
            }
    }
}
