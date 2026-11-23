import SwiftUI
import UIKit
import SurveyCore
import UniformTypeIdentifiers

#if canImport(PDFKit)
import PDFKit
#endif

/// 出すの1段目。図面を現場の下敷きへ置き、置いた結果を残す。
struct SheetImportPage: View {
    @ObservedObject var field: FieldModel
    var onNext: () -> Void
    @State private var picking = false

    private static let uiTestPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("図面を読み込む")
                    .font(SurveyType(22, .heavy))
                Text("この現場に、図面を1枚置く。")
                    .font(SurveyType(18, .heavy))
                    .lineLimit(1)
                    .accessibilityIdentifier("purpose-draw")
                DeskTile(title: "図面を読む", systemImage: "doc.badge.plus", identifier: "draw-import", prominent: true) {
                    if Self.uiTest {
                        field.importProjectSheet(data: Self.uiTestPNG, fileName: "図面.png")
                    } else {
                        picking = true
                    }
                }
                if let message = field.sheetMessage {
                    Text(message)
                        .font(SurveyType(18, .heavy))
                        .lineLimit(3)
                        .accessibilityIdentifier("draw-result")
                }
                if let sheet = field.projectSheet, let data = field.projectSheetData() {
                    SheetPreview(data: data, sheet: sheet)
                        .accessibilityIdentifier("sheet-preview")
                }
                if field.projectSheet != nil {
                    Button(action: onNext) {
                        Text("縮尺設定へ")
                            .font(SurveyType(18, .heavy))
                            .frame(maxWidth: .infinity, minHeight: 72)
                            .background(SurveyColor.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(SurveyColor.onAccent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("go-scale")
                }
            }
            .padding(20)
            .padding(.bottom, 92)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("screen-draw")
        .background(SurveyColor.background)
        .onAppear { field.refreshProjectSheet() }
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.types) { result in
            guard case let .success(url) = result else { return }
            let allowed = url.startAccessingSecurityScopedResource()
            defer { if allowed { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                field.importProjectSheet(data: Data(), fileName: "empty.txt")
                return
            }
            field.importProjectSheet(data: data, fileName: url.lastPathComponent)
        }
    }

    private static var uiTest: Bool { ProcessInfo.processInfo.arguments.contains("-surveyUITest") }

    private static var types: [UTType] {
        var list: [UTType] = [.pdf, .image]
        if let dxf = UTType(filenameExtension: "dxf") { list.append(dxf) }
        return list
    }
}

private struct SheetPreview: View {
    var data: Data
    var sheet: ProjectSheet

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sheet.fileName)
                .font(SurveyType(16, .heavy))
                .lineLimit(1)
            preview
        }
    }

    @ViewBuilder
    private var preview: some View {
        if sheet.kind == "image", let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 280)
        } else if sheet.kind == "pdf" {
            pdfPreview
        } else {
            Text("DXF を現場に置きました。図への合わせは次の段です。")
                .font(SurveyType(16, .semibold))
                .foregroundStyle(SurveyColor.muted)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var pdfPreview: some View {
        #if canImport(PDFKit)
        if let document = PDFDocument(data: data), let page = document.page(at: 0) {
            let image = page.thumbnail(of: CGSize(width: 600, height: 800), for: .mediaBox)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 280)
        } else {
            Text("PDF を置けませんでした。")
                .font(SurveyType(16, .semibold))
        }
        #else
        Text("PDF を現場に置きました。")
            .font(SurveyType(16, .semibold))
        #endif
    }
}
