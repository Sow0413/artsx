import SwiftUI
import SurveyCore

struct HeightMapSheet: View {
    @ObservedObject var drawing: DrawingSession
    let columnCount: Int
    @Environment(\.dismiss) private var dismiss
    @State private var ground = 0
    @State private var formation = 1

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                columnPicker("GL", selection: $ground)
                columnPicker("FH", selection: $formation)
                Button("入れる") {
                    drawing.applyHeightMap(
                        groundColumn: ground,
                        formationColumn: formation == ground ? nil : formation
                    )
                    dismiss()
                }
                .buttonStyle(SurveyPlainButton())
                Spacer()
            }
            .padding(16)
            .background(SurveyColor.background)
            .navigationTitle("高さ")
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
            ground = 0
            formation = min(1, max(columnCount - 1, 0))
        }
    }

    private func columnPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(0..<max(columnCount, 1), id: \.self) { index in
                Text("\(index + 1)列目").tag(index)
            }
        }
        .pickerStyle(.segmented)
        .frame(minHeight: 44)
    }
}
