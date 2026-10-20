import Foundation
import SurveyCore
#if canImport(UIKit)
import UIKit
#endif

extension FieldModel {
    func relayRadio(_ packet: RadioPacket) {
        guard drawing.project != nil else { return }
        guard MeshDuty.forwards(.radio, batteryPercent: meshBattery, charging: meshCharging) else { return }
        publishDisaster(
            kind: .radio,
            radioPacket: packet,
            envelopeID: MeshDuty.radioEnvelopeID(packet)
        )
    }

    func readMeshBattery() {
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        if level >= 0 {
            meshBattery = Int((level * 100).rounded())
        } else {
            meshBattery = nil
        }
        meshCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        #endif
    }
}
