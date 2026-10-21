import PhotosUI
import SwiftUI
import UIKit
import SurveyCore

/// 座標の表を撮るか選ぶ。文字は端末の中だけで読む。通信しない。
struct PaperCaptureSheet: View {
    @ObservedObject var field: FieldModel
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var notice: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("座標の表を撮るか、写真を選びます。読み取りはこの端末の中だけで行い、通信しません。")
                    .font(SurveyType(15, .semibold))
                    .foregroundStyle(SurveyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if cameraAvailable {
                    Button("カメラで撮る") { showsCamera = true }
                        .buttonStyle(SurveyPlainButton())
                }
                photoButton
                if busy {
                    Text("読んでいます。")
                        .font(SurveyType(15, .heavy))
                        .foregroundStyle(SurveyColor.text)
                }
                if let notice {
                    Text(notice)
                        .font(SurveyType(15, .heavy))
                        .foregroundStyle(SurveyColor.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(16)
            .background(SurveyColor.background)
            .navigationTitle("用紙を読む")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .font(SurveyType(17, .heavy))
                }
            }
        }
        .modifier(SurveyScheme())
        .sheet(isPresented: $showsCamera) {
            CameraCapture { image in
                recognize(image)
            }
        }
    }

    private var cameraAvailable: Bool {
        #if canImport(UIKit)
        UIImagePickerController.isSourceTypeAvailable(.camera)
        #else
        false
        #endif
    }

    @ViewBuilder
    private var photoButton: some View {
        #if canImport(PhotosUI)
        PhotosPicker(selection: $photo, matching: .images) {
            Text("写真を選ぶ")
                .font(SurveyType(17, .heavy))
                .foregroundStyle(SurveyColor.onAccent)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(SurveyColor.text, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                let image = data.flatMap { UIImage(data: $0) }
                await MainActor.run {
                    if let image {
                        recognize(image)
                    } else {
                        notice = "写真を読めませんでした。"
                    }
                }
            }
        }
        #else
        EmptyView()
        #endif
    }

    private func recognize(_ image: UIImage) {
        #if canImport(Vision)
        busy = true
        notice = nil
        let upright = image.uprightImage()
        DispatchQueue.global(qos: .userInitiated).async {
            let cells = PaperRecognizer.cells(from: upright)
            DispatchQueue.main.async {
                busy = false
                guard let cells, let table = PointTableReader.table(from: cells, fileName: "用紙") else {
                    notice = "座標の表が見つかりませんでした。"
                    return
                }
                field.showsPaperCapture = false
                DispatchQueue.main.async {
                    field.drawing.presentPointTable(table)
                }
            }
        }
        #else
        notice = "この端末では用紙を読めません。"
        #endif
    }
}

private extension UIImage {
    func uprightImage() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

#if canImport(UIKit)
struct CameraCapture: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture

        init(_ parent: CameraCapture) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif

#if canImport(Vision)
import Vision

enum PaperRecognizer {
    /// VNRecognizeTextRequest。言語は日本語と英語、accurate、端末内。
    static func cells(from image: UIImage) -> [[PointTableCell]]? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            request.recognitionLanguages = ["ja-JP"]
            guard (try? handler.perform([request])) != nil else { return nil }
        }
        let observations = request.results ?? []
        let boxes = observations.compactMap { observation -> PaperTextBox? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return PaperTextBox(
                text: candidate.string,
                confidence: Double(candidate.confidence),
                minX: Double(box.minX),
                maxX: Double(box.maxX),
                midY: Double(box.midY),
                height: Double(box.height)
            )
        }
        let cells = PointTableReader.cells(from: boxes)
        return cells.isEmpty ? nil : cells
    }
}
#endif
