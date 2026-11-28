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

    private static let uiTestPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("この現場に、図面を1枚置く。")
                    .font(SurveyType(18, .heavy))
                    .lineLimit(1)
                    .accessibilityIdentifier("purpose-draw")
                DeskTile(title: "図面を読む", systemImage: "doc.badge.plus", identifier: "draw-import", prominent: true) {
                    if Self.uiTest, !Self.forcePicker {
                        field.importProjectSheet(data: Self.uiTestPNG, fileName: "図面.png")
                    } else {
                        SheetFilePicker.present(types: Self.types, allowsMultiple: true, onPick: { urls in
                            Self.importFiles(urls, into: field)
                        }, onFail: { reason in
                            field.failSheet(reason)
                        })
                    }
                }
                DeskTile(title: "座標を読む", systemImage: "mappin.and.ellipse", identifier: "import-coordinates-sheet", prominent: false) {
                    CoordinateImport.start(field: field)
                }
                Button {
                    SheetFilePicker.present(types: [.folder], allowsMultiple: false, onPick: { urls in
                        guard let folder = urls.first else {
                            field.failSheet("フォルダが選ばれませんでした。")
                            return
                        }
                        Self.importFolder(folder, into: field)
                    }, onFail: { reason in
                        field.failSheet(reason)
                    })
                } label: {
                    Text("フォルダを読む")
                        .font(SurveyType(15, .heavy))
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .foregroundStyle(SurveyColor.muted)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("draw-import-folder")
                if let message = field.sheetMessage {
                    Text(message)
                        .font(SurveyType(18, .heavy))
                        .lineLimit(4)
                        .accessibilityIdentifier("draw-result")
                }
                if !field.sheetZoneChoices.isEmpty {
                    Text("系を選んでください。")
                        .font(SurveyType(16, .semibold))
                    ForEach(field.sheetZoneChoices, id: \.self) { zone in
                        Button(PlaneZoneLabel.button(zone)) { field.acceptSheetZone(zone) }
                            .accessibilityIdentifier("sheet-zone-\(zone)")
                    }
                }
                if let sheet = field.projectSheet, let data = field.projectSheetData() {
                    SheetPreview(data: data, sheet: sheet, readyToPlace: field.canPlaceOnSite)
                        .accessibilityIdentifier("sheet-preview")
                }
                if field.sheetUsesCoordinates, field.canPlaceOnSite || field.projectSheet != nil {
                    Button {
                        if field.canPlaceOnSite {
                            field.placeImportedSheet()
                        } else {
                            field.tab = .map
                        }
                    } label: {
                        Text("地図で見る")
                            .font(SurveyType(18, .heavy))
                            .frame(maxWidth: .infinity, minHeight: 72)
                            .background(SurveyColor.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(SurveyColor.onAccent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("view-on-map")
                } else if field.canPlaceOnSite {
                    Button {
                        field.placeImportedSheet()
                    } label: {
                        Text("現場へ置く")
                            .font(SurveyType(18, .heavy))
                            .frame(maxWidth: .infinity, minHeight: 72)
                            .background(SurveyColor.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(SurveyColor.onAccent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("place-on-site")
                }
                if field.projectSheet != nil, !field.canPlaceOnSite, !field.sheetUsesCoordinates {
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
    }

    private static func importFolder(_ url: URL, into field: FieldModel) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            field.failSheet("ファイルを開けませんでした（OneDriveなどは一度ダウンロードしてください）: フォルダを読めません。")
            return
        }
        importFiles(children, into: field)
    }

    private static func importFiles(_ urls: [URL], into field: FieldModel) {
        guard !urls.isEmpty else {
            field.failSheet("ファイルが選ばれませんでした。")
            return
        }
        var sheet: (Data, String, URL)?
        var metas: [(name: String, data: Data)] = []
        var books: [(Data, String)] = []
        var failures: [String] = []
        for url in urls {
            switch PickedFileBytes.read(url) {
            case let .failure(error):
                failures.append(error.message)
            case let .success(data):
                var name = url.lastPathComponent
                if !name.lowercased().hasSuffix("dxf"), !name.lowercased().hasSuffix("meta.json"), looksLikeDXF(data) {
                    name += ".dxf"
                }
                let lower = name.lowercased()
                if lower.hasSuffix("meta.json") {
                    metas.append((name, data))
                } else if lower.hasSuffix("csv") || lower.hasSuffix("sima") {
                    books.append((data, name))
                } else if lower.hasSuffix("dxf") || lower.hasSuffix("sfc") || lower.hasSuffix("pdf")
                            || lower.hasSuffix("png") || lower.hasSuffix("jpg") || lower.hasSuffix("jpeg")
                            || lower.hasSuffix("heic") || lower.hasSuffix("gif") || lower.hasSuffix("webp")
                            || lower.hasSuffix("tif") || lower.hasSuffix("tiff") {
                    sheet = (data, name, url)
                } else {
                    failures.append("\(name) は図面でも基準点でもありません。")
                }
            }
        }
        var meta = sheet.flatMap { item in
            DrawingSidecarNames.match(dxfName: item.1, metaNames: metas.map(\.name))
                .flatMap { matched in metas.first { $0.name.caseInsensitiveCompare(matched) == .orderedSame }?.data }
        }
        if meta == nil, let sheet {
            for sibling in DrawingSidecarNames.siblingURLs(for: sheet.2) {
                if case let .success(data) = PickedFileBytes.read(sibling) {
                    meta = data
                    break
                }
            }
        }
        if let sheet {
            field.importProjectSheet(data: sheet.0, fileName: sheet.1, sidecar: meta, books: books)
        } else if let meta {
            field.holdSidecar(meta)
            for book in books { field.importBasic(data: book.0, filename: book.1) }
        } else if !books.isEmpty {
            for book in books { field.importBasic(data: book.0, filename: book.1) }
        } else {
            let reason = failures.isEmpty
                ? "選んだファイルを読めませんでした。"
                : failures.joined(separator: " ")
            field.failSheet(reason)
        }
    }

    private static func looksLikeDXF(_ data: Data) -> Bool {
        let sample = data.prefix(4000)
        guard let text = String(data: sample, encoding: .utf8) ?? String(data: sample, encoding: .ascii) else { return false }
        return text.contains("SECTION") && (text.contains("ENTITIES") || text.contains("AC10"))
    }

    private static var uiTest: Bool { ProcessInfo.processInfo.arguments.contains("-surveyUITest") }

    private static var forcePicker: Bool { ProcessInfo.processInfo.arguments.contains("-surveyUITestPicker") }

    private static var types: [UTType] {
        var list: [UTType] = [.pdf, .image, .json, .commaSeparatedText, .plainText, .data]
        list.append(UTType(filenameExtension: "dxf") ?? .data)
        list.append(UTType(filenameExtension: "sfc") ?? .data)
        list.append(UTType(filenameExtension: "csv") ?? .commaSeparatedText)
        list.append(UTType(filenameExtension: "json") ?? .json)
        return list
    }
}

enum CoordinateImport {
    static func start(field: FieldModel) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-surveyUITest"), !arguments.contains("-surveyUITestPicker") {
            field.importCoordinateFile(data: VIPack.csv, filename: "control-points.csv")
            return
        }
        var types: [UTType] = [.commaSeparatedText, .plainText, .text, .data, .json]
        types.append(UTType(filenameExtension: "csv") ?? .data)
        types.append(UTType(filenameExtension: "sima") ?? .data)
        types.append(UTType(filenameExtension: "sim") ?? .data)
        SheetFilePicker.present(types: types, onPick: { urls in
            var opened = false
            for url in urls {
                switch PickedFileBytes.read(url) {
                case let .success(data):
                    field.importCoordinateFile(data: data, filename: url.lastPathComponent)
                    opened = true
                case let .failure(error):
                    field.failSheet(error.message)
                }
            }
            if !opened {
                field.failSheet("座標ファイルを選べませんでした。CSV か SIMA を選んでください。")
            }
        }, onFail: { reason in
            field.failSheet(reason)
        })
    }
}

/// ファイルアプリの OneDrive は、選んだ直後は中身が端末に無いことがある。
struct PickError: Error {
    let message: String
}

enum PickedFileBytes {
    static func read(_ url: URL) -> Result<Data, PickError> {
        let name = url.lastPathComponent.isEmpty ? "ファイル" : url.lastPathComponent
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("picked-\(UUID().uuidString)-\(name)")
        var copied = copyIntoSandbox(url, sandbox: sandbox, options: .forUploading)
        if case .failure = copied {
            copied = copyIntoSandbox(url, sandbox: sandbox, options: [])
        }
        if case let .failure(error) = copied {
            return .failure(PickError(message: "ファイルを開けませんでした（OneDriveなどは一度ダウンロードしてください）: \(error.message)"))
        }
        return copied
    }

    private static func copyIntoSandbox(
        _ url: URL,
        sandbox: URL,
        options: NSFileCoordinator.ReadingOptions
    ) -> Result<Data, PickError> {
        let name = url.lastPathComponent.isEmpty ? "ファイル" : url.lastPathComponent
        var copied = Result<Data, PickError>.failure(PickError(message: "\(name) をコピーできませんでした。"))
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: options, error: &coordinationError) { coordinated in
            do {
                if FileManager.default.fileExists(atPath: sandbox.path) {
                    try FileManager.default.removeItem(at: sandbox)
                }
                try FileManager.default.copyItem(at: coordinated, to: sandbox)
                let data = try Data(contentsOf: sandbox)
                copied = data.isEmpty
                    ? .failure(PickError(message: "\(name) は空です。"))
                    : .success(data)
            } catch {
                copied = .failure(PickError(message: error.localizedDescription))
            }
        }
        if let coordinationError, case .failure = copied {
            return .failure(PickError(message: coordinationError.localizedDescription))
        }
        return copied
    }
}

/// SwiftUI の fileImporter は、ナビゲーションの中だとシートが重なって出ないことがある。
enum SheetFilePicker {
    private static var delegate: Delegate?

    static func present(
        types: [UTType],
        allowsMultiple: Bool = true,
        onPick: @escaping ([URL]) -> Void,
        onFail: @escaping (String) -> Void
    ) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: !types.contains(.folder))
        picker.allowsMultipleSelection = allowsMultiple
        picker.shouldShowFileExtensions = true
        let delegate = Delegate(onPick: onPick)
        self.delegate = delegate
        picker.delegate = delegate
        guard let host = topViewController() else {
            onFail("書類の選択画面を出せませんでした。")
            return
        }
        host.present(picker, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.flatMap(\.windows).first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }

    private final class Delegate: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
            SheetFilePicker.delegate = nil
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            SheetFilePicker.delegate = nil
        }
    }
}

private struct SheetPreview: View {
    var data: Data
    var sheet: ProjectSheet
    var readyToPlace: Bool = false

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
            Text(readyToPlace ? "読み込んだ図面です。現場へ置くと地図に出します。" : "DXF を現場に置きました。図への合わせは次の段です。")
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
