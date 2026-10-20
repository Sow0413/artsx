import SwiftUI

struct MapTabView: View {
    @ObservedObject var field: FieldModel

    var body: some View {
        ZStack {
            SurveyMapView(field: field)
            VStack(spacing: 0) {
                WorkBar(field: field)
                HStack {
                    Spacer()
                    Text(reachCaption)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(SurveyColor.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(SurveyColor.card.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(.trailing, 12)
                .padding(.top, 6)
                if field.enclosingBook {
                    enclosureBanner
                } else if field.drawing.pick == .mapPoint {
                    mapPickBanner
                }
                Spacer(minLength: 0)
                bottomChrome
            }
        }
        .background(SurveyColor.mapBackdrop)
    }

    private var reachCaption: String {
        let meters = String(format: field.drawing.machinePresetID == nil ? "%.1f" : "%.0f", field.drawing.machineRadiusMeters)
        if let id = field.drawing.machinePresetID, let preset = MachineCatalog.named(id) {
            return "作業半径 \(meters)m（\(preset.label)・目安）"
        }
        return "作業半径 \(meters)m"
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

    private var enclosureBanner: some View {
        HStack(spacing: 12) {
            Text("見えている範囲で座標簿を絞る")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(SurveyColor.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("この範囲") {
                field.confirmBookEnclosure()
            }
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(SurveyColor.green)
            Button("やめる") {
                field.cancelBookEnclosure()
            }
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(SurveyColor.amber)
        }
        .padding(12)
        .background(SurveyColor.card.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var mapPickBanner: some View {
        HStack(spacing: 12) {
            Text("図面の点に対応する場所をタップ")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(SurveyColor.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("戻る") {
                field.cancelDrawingMapPick()
            }
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(SurveyColor.amber)
        }
        .padding(12)
        .background(SurveyColor.amberBackground.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
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
