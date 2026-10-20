import Foundation
import SurveyCore
#if canImport(UIKit)
import UIKit
#endif

extension FieldModel {
    func setRepeaterMode(_ enabled: Bool) {
        guard drawing.project != nil else {
            repeaterMode = false
            disasterMessage = "プロジェクトを開いてから中継専用にします。"
            return
        }
        repeaterMode = enabled
        repeaterDimmed = enabled
        radio.suppressPlayback = enabled
        if enabled {
            lora.start()
            disasterMessage = RepeaterPosture.condition
        } else {
            lora.stop()
            loraStatus = "LoRaは未接続です。"
        }
        storeRepeater()
        applyRepeaterScreen(enabled)
    }

    func setLoRaCertified(_ enabled: Bool) {
        loraCertified = enabled
        storeRepeater()
        loraStatus = enabled ? LoRaPolicy.certifiedNote : "技適の確認を外しました。LoRaへは送りません。"
    }

    func installRepeaterHere() {
        guard repeaterMode else {
            disasterMessage = "中継専用をオンにしてから設置します。"
            return
        }
        guard let position = workingReading.position, position.isPlottable else {
            disasterMessage = "位置がまだありません。"
            return
        }
        repeaterInstall = RepeaterInstall(
            deviceID: crew.deviceID,
            name: crew.displayName,
            latitudeDegrees: position.latitudeDegrees,
            longitudeDegrees: position.longitudeDegrees,
            at: Date()
        )
        storeRepeater()
        sendRepeaterBeacon(force: true)
        disasterMessage = "この場所を中継の設置位置にしました。"
    }

    func relayRadio(_ packet: RadioPacket) {
        guard repeaterMode, drawing.project != nil else { return }
        publishDisaster(kind: .radio, radioPacket: packet)
        if loraCertified {
            loraStatus = LoRaPolicy.voiceNote
        }
    }

    func maintainRepeater(now: Date) {
        loadRepeaterIfNeeded()
        guard repeaterMode else { return }
        readBattery()
        repeaterBoard.age(now: now)
        repeaterLinks = repeaterBoard.links
        sendRepeaterBeacon(force: false, now: now)
        flushLoRa()
    }

    func offerLoRa(
        kind: LoRaMessage.Kind,
        name: String,
        latitude: Double?,
        longitude: Double?,
        text: String?,
        id: UUID = UUID()
    ) {
        switch LoRaPolicy.admit(
            kind: kind,
            name: name,
            latitudeDegrees: latitude,
            longitudeDegrees: longitude,
            text: text,
            certified: loraCertified
        ) {
        case .failure(let reason):
            if reason == .notCertified { return }
            loraStatus = reason == .voice ? LoRaPolicy.voiceNote : "LoRaには短い文だけを載せます。"
        case .success(let admitted):
            var message = admitted
            message.id = id
            if loraOutbox.add(message) {
                flushLoRa()
            }
        }
    }

    func applyRepeaterScreen(_ on: Bool) {
        #if canImport(UIKit)
        let seatAwake = tab == .seat && !batterySaver
        UIApplication.shared.isIdleTimerDisabled = on || seatAwake
        if on {
            if savedBrightness == nil {
                savedBrightness = UIScreen.main.brightness
            }
            UIScreen.main.brightness = 0.02
        } else if let saved = savedBrightness {
            UIScreen.main.brightness = saved
            savedBrightness = nil
            UIApplication.shared.isIdleTimerDisabled = seatAwake
        }
        #endif
    }

    func ingestLoRaLine(_ line: String) {
        guard line.hasPrefix("SVY1 ") else { return }
        loraStatus = "LoRa \(line)"
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 3 else { return }
        if parts[1] == "SOS" {
            disasterMessage = "LoRaから SOS \(parts[2])"
        }
    }

    private func sendRepeaterBeacon(force: Bool, now: Date = Date()) {
        guard let install = repeaterInstall, drawing.project != nil else { return }
        if !force, let last = lastRepeaterBeacon, now.timeIntervalSince(last) < 30 { return }
        lastRepeaterBeacon = now
        let beacon = RepeaterBeacon(
            deviceID: install.deviceID,
            name: install.name,
            latitudeDegrees: install.latitudeDegrees,
            longitudeDegrees: install.longitudeDegrees,
            batteryPercent: repeaterBattery,
            charging: repeaterCharging,
            at: now
        )
        publishDisaster(kind: .beacon, beacon: beacon, hopLimit: 1)
        offerLoRa(
            kind: .position,
            name: install.name,
            latitude: install.latitudeDegrees,
            longitude: install.longitudeDegrees,
            text: nil,
            id: UUID()
        )
    }

    private func flushLoRa() {
        guard loraCertified else { return }
        while let message = loraOutbox.next() {
            lora.send(MeshtasticCodec.encode(message))
        }
    }

    private func readBattery() {
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        if level >= 0 {
            repeaterBattery = Int((level * 100).rounded())
        } else {
            repeaterBattery = nil
        }
        repeaterCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        #endif
    }

    private func loadRepeaterIfNeeded() {
        guard let project = drawing.project else { return }
        guard repeaterLoadedProject != project.name else { return }
        repeaterLoadedProject = project.name
        let record = RepeaterBook.load(projectName: project.name, at: drawing.projectsRoot)
        repeaterMode = record.mode
        loraCertified = record.certified
        repeaterInstall = record.install
        repeaterDimmed = record.mode
        radio.suppressPlayback = record.mode
        if record.mode {
            lora.start()
            applyRepeaterScreen(true)
        }
    }

    private func storeRepeater() {
        guard let project = drawing.project else { return }
        try? RepeaterBook.save(
            RepeaterRecord(mode: repeaterMode, certified: loraCertified, install: repeaterInstall),
            projectName: project.name,
            at: drawing.projectsRoot
        )
    }
}
