import Foundation
import SurveyCore
#if !SURVEY_PLAYGROUND && canImport(CoreBluetooth)
import CoreBluetooth
#endif

enum GNSSRadioBox {
    static func make() -> (link: GNSSLink, available: Bool) {
        #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth)
        return (GNSSLink(radio: CoreBluetoothGNSSRadio()), true)
        #else
        return (GNSSLink(radio: IdleGNSSRadio()), false)
        #endif
    }
}

#if !SURVEY_PLAYGROUND && canImport(CoreBluetooth)
/// 選んだ GNSS の Bluetooth。切れたら GNSSLink がつなぎ直す。背面では待たない。実機は未確認。
final class CoreBluetoothGNSSRadio: NSObject, GNSSRadio, CBCentralManagerDelegate, CBPeripheralDelegate {
    var onConnect: (() -> Void)?
    var onDrop: (() -> Void)?
    var onDiscover: ((GNSSChoice) -> Void)?

    private let defaultsKey = "survey.gnss.peripheral"
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private let queue = DispatchQueue(label: "survey.gnss.bluetooth")

    var hasSavedDevice: Bool {
        UserDefaults.standard.string(forKey: defaultsKey) != nil
    }

    func start() {
        queue.async {
            self.ensureCentral()
            guard self.central?.state == .poweredOn else { return }
            self.connectSaved()
        }
    }

    func scan() {
        queue.async {
            self.ensureCentral()
            guard self.central?.state == .poweredOn else { return }
            self.central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }

    func connect(_ id: String) {
        UserDefaults.standard.set(id, forKey: defaultsKey)
        queue.async {
            self.ensureCentral()
            guard self.central?.state == .poweredOn else { return }
            self.connectSaved()
        }
    }

    func stop() {
        queue.async {
            self.central?.stopScan()
            if let peripheral = self.peripheral {
                self.central?.cancelPeripheralConnection(peripheral)
            }
        }
    }

    private func ensureCentral() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: queue)
        }
    }

    private func connectSaved() {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey), let uuid = UUID(uuidString: raw) else { return }
        let found = central?.retrievePeripherals(withIdentifiers: [uuid]) ?? []
        guard let peripheral = found.first else {
            central?.scanForPeripherals(withServices: nil, options: nil)
            return
        }
        self.peripheral = peripheral
        peripheral.delegate = self
        central?.connect(peripheral, options: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        if hasSavedDevice {
            connectSaved()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "名前の無い機器"
        onDiscover?(GNSSChoice(id: peripheral.identifier.uuidString, name: name))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        central.stopScan()
        self.peripheral = peripheral
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: defaultsKey)
        onConnect?()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onDrop?()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        onDrop?()
    }
}
#endif
