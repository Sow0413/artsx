import Foundation
import SurveyCore
#if !SURVEY_PLAYGROUND && canImport(CoreBluetooth)
import CoreBluetooth
#endif

/// Meshtastic 互換ノードへの BLE。実機の接続は未確認。音声は渡さない。
final class LoRaLink: NSObject {
    var onStatus: ((String) -> Void)?
    var onText: ((String) -> Void)?
    private(set) var connected = false

    #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth)
    private var manager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var toRadio: CBCharacteristic?
    private let service = CBUUID(string: MeshtasticCodec.serviceUUID)
    private let toRadioID = CBUUID(string: MeshtasticCodec.toRadioUUID)
    private let fromRadioID = CBUUID(string: MeshtasticCodec.fromRadioUUID)
    private let fromNumID = CBUUID(string: MeshtasticCodec.fromNumUUID)
    #endif

    func start() {
        #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth)
        if manager == nil {
            manager = CBCentralManager(delegate: self, queue: .main)
        }
        onStatus?("920MHzの技適ノードを探しています。")
        #else
        onStatus?("このビルドでは BLE を組み込んでいません。")
        #endif
    }

    func stop() {
        #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth)
        if let peripheral, let manager {
            manager.cancelPeripheralConnection(peripheral)
        }
        manager?.stopScan()
        #endif
        connected = false
        onStatus?("LoRaを切りました。")
    }

    func send(_ data: Data) {
        guard connected else { return }
        #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth)
        guard let peripheral, let toRadio else { return }
        peripheral.writeValue(data, for: toRadio, type: .withoutResponse)
        #else
        _ = data
        #endif
    }
}

#if !SURVEY_PLAYGROUND && canImport(CoreBluetooth)
extension LoRaLink: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            onStatus?("Bluetoothがオフです。")
            return
        }
        central.scanForPeripherals(withServices: [service], options: nil)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        self.peripheral = peripheral
        central.stopScan()
        central.connect(peripheral, options: nil)
        onStatus?("ノードに接続しています。")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connected = false
        onStatus?("ノードに接続できませんでした。")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let found = peripheral.services?.first(where: { $0.uuid == self.service }) else { return }
        peripheral.discoverCharacteristics([toRadioID, fromRadioID, fromNumID], for: found)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == toRadioID { toRadio = characteristic }
            if characteristic.uuid == fromNumID {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.uuid == fromRadioID {
                peripheral.readValue(for: characteristic)
            }
        }
        connected = toRadio != nil
        onStatus?(connected ? "LoRaノードにつながりました。音声は送りません。" : "書き込み口が見つかりません。")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, !data.isEmpty else { return }
        if characteristic.uuid == fromNumID {
            if let fromRadio = peripheral.services?.flatMap({ $0.characteristics ?? [] }).first(where: { $0.uuid == fromRadioID }) {
                peripheral.readValue(for: fromRadio)
            }
            return
        }
        if let text = MeshtasticCodec.decodeText(data) {
            onText?(text)
        }
    }
}
#endif
