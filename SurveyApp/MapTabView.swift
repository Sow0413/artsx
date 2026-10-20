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
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: 640)
        }
        .background(SurveyColor.mapBackdrop)
    }
}
