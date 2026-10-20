import SwiftUI
import SurveyCore

struct MeshRelayStatus: View {
    @ObservedObject var field: FieldModel

    var body: some View {
        if !MeshDuty.relaying(field.meshPresence) {
            status(MeshDuty.stoppedLabel, MeshDuty.stoppedReason, SurveyColor.red, SurveyColor.redBackground)
        } else if MeshDuty.sparing(batteryPercent: field.meshBattery, charging: field.meshCharging) {
            status(MeshDuty.sparingLabel, MeshDuty.sparingNote, SurveyColor.amber, SurveyColor.amberBackground)
        }
    }

    private func status(_ title: String, _ detail: String, _ titleColor: Color, _ fill: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(titleColor)
            Text(detail)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SurveyColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(fill)
    }
}

struct MeshPresenceWatcher: ViewModifier {
    @ObservedObject var field: FieldModel
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear { field.noteMeshPresence(Self.presence(scenePhase)) }
            .onChange(of: scenePhase) { _, phase in
                field.noteMeshPresence(Self.presence(phase))
            }
    }

    private static func presence(_ phase: ScenePhase) -> MeshDuty.Presence {
        switch phase {
        case .active: return .active
        case .inactive: return .inactive
        case .background: return .background
        @unknown default: return .background
        }
    }
}
