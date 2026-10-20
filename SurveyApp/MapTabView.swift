import SwiftUI

struct MapTabView: View {
    @ObservedObject var field: FieldModel

    var body: some View {
        ZStack(alignment: .bottom) {
            SurveyMapView(field: field)
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
                        .frame(maxHeight: 360)
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
                    LocationPanel(reading: field.reading)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: 640)
        }
        .background(SurveyColor.mapBackdrop)
    }
}
