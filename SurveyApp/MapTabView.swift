import SwiftUI

struct MapTabView: View {
    @ObservedObject var field: FieldModel

    var body: some View {
        ZStack {
            SurveyMapView(field: field)
            VStack(spacing: 0) {
                WorkBar(field: field)
                Spacer(minLength: 0)
                bottomChrome
            }
        }
        .background(SurveyColor.mapBackdrop)
    }

    private var bottomChrome: some View {
        VStack(spacing: 10) {
                HStack(alignment: .top) {
                    AttributionLabel()
                    Spacer(minLength: 8)
                    RecenterButton(following: field.followUser) {
                        field.recenter()
                    }
                }
                if field.selectedControlPoint != nil || field.benchmark != nil {
                    BenchmarkCard(field: field)
                        .frame(maxHeight: 460)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    BenchmarkHint(
                        notice: field.controlPointNotice,
                        loadedCount: field.controlPoints.count,
                        visibleCount: field.visibleControlPoints.count
                    )
                    DownloadBar(
                        message: field.downloadMessage,
                        isDownloading: field.isDownloading,
                        onSave: field.downloadVisibleArea,
                        onCancel: field.cancelDownload
                    )
                    LocationPanel(
                        reading: field.workingReading,
                        note: field.showsCorrectedPosition ? "三角点補正を引いた位置" : nil
                    )
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    captureButton
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: 640)
    }

    private var captureButton: some View {
        Button(action: field.captureObservation) {
            Text("この作業で点を残す")
                .font(.system(size: 16, weight: .heavy))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(SurveyColor.card)
                .foregroundStyle(SurveyColor.text)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
