import CoreBluetooth
import Foundation
import Network
import Security
import SwiftUI
import SurveyCore

/// キャスターのパスワード。UserDefaults には置かず、ログにも出さない。
enum NTRIPSecret {
    private static let service = "artsx.ntrip"
    private static let account = "caster"

    static func save(_ password: String) {
        let query = base()
        SecItemDelete(query as CFDictionary)
        guard !password.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(password.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> String {
        var query = base()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    static func exists() -> Bool {
        !load().isEmpty
    }

    private static func base() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct NTRIPSettings: Codable, Equatable {
    var host: String = ""
    var port: Int = 2101
    var mountpoint: String = ""
    var user: String = ""
    var version: NTRIPVersion = .v2
    var enabled: Bool = false

    var account: NTRIPAccount {
        NTRIPAccount(host: host, port: port, mountpoint: mountpoint, user: user, version: version)
    }

    static let storageKey = "survey.ntrip"

    static func load() -> NTRIPSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(NTRIPSettings.self, from: data) else {
            return NTRIPSettings()
        }
        return value
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

/// Drogger などの Nordic UART。RTCM を書き、NMEA を読む。NTRIP のパスワードは接続のあいだだけ使う。
final class ExternalGNSS: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let deviceKey = "survey.rtk.peripheral"
    private let uart = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let rxID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private let txID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    weak var field: FieldModel?
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var rx: CBCharacteristic?
    private var known: [UUID: CBPeripheral] = [:]
    private let queue = DispatchQueue(label: "survey.ntrip")
    private var connection: NWConnection?
    private var ntripBuffer = Data()
    private var nmeaBuffer = Data()
    private var recentSentences: [String] = []
    private var headerDone = false
    private var lastGGA: Date?
    private var ggaTimer: DispatchSourceTimer?
    private var running = false

    func attach(_ field: FieldModel) {
        self.field = field
    }

    func start() {
        running = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
        }
        openNTRIP()
    }

    func stop() {
        running = false
        ggaTimer?.cancel()
        ggaTimer = nil
        connection?.cancel()
        connection = nil
        headerDone = false
        ntripBuffer.removeAll()
        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        rx = nil
        DispatchQueue.main.async { [weak self] in
            self?.field?.receiverLost()
            self?.field?.correctionsLost()
        }
    }

    func applySettings() {
        guard running else { return }
        connection?.cancel()
        connection = nil
        headerDone = false
        ntripBuffer.removeAll()
        openNTRIP()
        if central?.state == .poweredOn {
            scan()
        }
    }

    func scan() {
        guard central?.state == .poweredOn else { return }
        central?.scanForPeripherals(withServices: [uart], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func connect(_ id: String) {
        guard let uuid = UUID(uuidString: id), let found = known[uuid] else { return }
        UserDefaults.standard.set(id, forKey: Self.deviceKey)
        peripheral = found
        found.delegate = self
        central?.stopScan()
        central?.connect(found, options: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard running, central.state == .poweredOn else { return }
        scan()
        if let saved = UserDefaults.standard.string(forKey: Self.deviceKey), let uuid = UUID(uuidString: saved) {
            let knownDevices = central.retrievePeripherals(withIdentifiers: [uuid])
            if let found = knownDevices.first {
                self.known[uuid] = found
                connect(saved)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        known[peripheral.identifier] = peripheral
        let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? advertised ?? "受信機"
        let choice = GNSSChoice(id: peripheral.identifier.uuidString, name: name)
        DispatchQueue.main.async { [weak self] in
            self?.field?.noteReceiverChoice(choice)
        }
        if UserDefaults.standard.string(forKey: Self.deviceKey) == peripheral.identifier.uuidString {
            connect(peripheral.identifier.uuidString)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([uart])
        DispatchQueue.main.async { [weak self] in
            self?.field?.noteReceiverLink("受信機をつなぎました")
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.field?.receiverLost()
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if self.peripheral?.identifier == peripheral.identifier {
            self.peripheral = nil
            rx = nil
        }
        DispatchQueue.main.async { [weak self] in
            self?.field?.receiverLost()
        }
        guard running else { return }
        central.connect(peripheral, options: nil)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == uart }) else { return }
        peripheral.discoverCharacteristics([rxID, txID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == rxID {
                rx = characteristic
            }
            if characteristic.uuid == txID {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == txID, let data = characteristic.value, !data.isEmpty else { return }
        nmeaBuffer.append(data)
        while let newline = nmeaBuffer.firstIndex(of: 0x0A) {
            let chunk = nmeaBuffer.prefix(upTo: newline)
            nmeaBuffer.removeSubrange(0...newline)
            guard let text = String(data: chunk, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  text.hasPrefix("$") else { continue }
            recentSentences.append(text)
            if recentSentences.count > 12 {
                recentSentences.removeFirst(recentSentences.count - 12)
            }
            guard text.contains("GGA"), let position = NMEA.position(from: recentSentences) else { continue }
            DispatchQueue.main.async { [weak self] in
                self?.field?.noteReceiver(position)
            }
        }
    }

    private func openNTRIP() {
        let settings = NTRIPSettings.load()
        guard running, settings.enabled, settings.account.isComplete else { return }
        let password = NTRIPSecret.load()
        guard !password.isEmpty, let port = NWEndpoint.Port(rawValue: UInt16(clamping: settings.port)) else { return }
        let gga = field?.upstreamGGA()
        let header = NTRIPRequest.header(account: settings.account, password: password, gga: gga)
        headerDone = false
        ntripBuffer.removeAll()
        lastGGA = nil
        let connection = NWConnection(host: NWEndpoint.Host(settings.host), port: port, using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.send(Data(header.utf8))
                self.receive()
                self.armGGA()
            case .failed, .cancelled:
                self.failCorrections()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func armGGA() {
        ggaTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + NTRIPRequest.ggaInterval, repeating: NTRIPRequest.ggaInterval)
        timer.setEventHandler { [weak self] in
            self?.sendGGA()
        }
        ggaTimer = timer
        timer.resume()
    }

    private func sendGGA() {
        guard NTRIPRequest.shouldSendGGA(last: lastGGA, now: Date()) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let sentence = self.field?.upstreamGGA() else { return }
            let line = Data((sentence + "\r\n").utf8)
            self.queue.async {
                self.lastGGA = Date()
                self.send(line)
            }
        }
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.ingest(data)
            }
            if isComplete || error != nil {
                self.failCorrections()
                return
            }
            self.receive()
        }
    }

    private func ingest(_ data: Data) {
        ntripBuffer.append(data)
        if !headerDone {
            let intake = NTRIPStream.consume(ntripBuffer)
            if intake.failed {
                ntripBuffer.removeAll()
                failCorrections()
                connection?.cancel()
                return
            }
            guard intake.status == 200 else { return }
            headerDone = true
            ntripBuffer = intake.pending
            deliver(intake.frames)
            return
        }
        let split = RTCM3.frames(in: ntripBuffer)
        ntripBuffer = split.remainder
        deliver(split.frames)
    }

    private func deliver(_ frames: [Data]) {
        guard !frames.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.field?.noteCorrectionData()
        }
        for frame in frames {
            writeRTCM(frame)
        }
    }

    private func writeRTCM(_ data: Data) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let peripheral = self.peripheral, let rx = self.rx else { return }
            let type: CBCharacteristicWriteType = rx.properties.contains(.writeWithoutResponse) ? .withoutResponse : .write
            let limit = max(20, peripheral.maximumWriteValueLength(for: type == .withoutResponse ? .withoutResponse : .withResponse))
            var offset = 0
            let bytes = [UInt8](data)
            while offset < bytes.count {
                let end = min(offset + limit, bytes.count)
                peripheral.writeValue(Data(bytes[offset..<end]), for: rx, type: type)
                offset = end
            }
        }
    }

    private func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    private func failCorrections() {
        DispatchQueue.main.async { [weak self] in
            self?.field?.correctionsLost()
        }
    }
}

struct ExternalReceiverSettings: View {
    @ObservedObject var field: FieldModel
    @State private var host = ""
    @State private var port = "2101"
    @State private var mountpoint = ""
    @State private var user = ""
    @State private var password = ""
    @State private var version: NTRIPVersion = .v2
    @State private var enabled = false
    @State private var passwordSaved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $enabled) {
                    Text("外部受信機を使う")
                        .font(SurveyType(18, .heavy))
                }
                .tint(SurveyColor.blue)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                Text(field.receiverStatus)
                    .font(SurveyType(16, .heavy))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                fieldRow("ホスト") { TextField("caster", text: $host).textInputAutocapitalization(.never).autocorrectionDisabled() }
                fieldRow("ポート") { TextField("2101", text: $port).keyboardType(.numberPad) }
                fieldRow("マウント") { TextField("VRS", text: $mountpoint).textInputAutocapitalization(.never).autocorrectionDisabled() }
                fieldRow("ユーザー") { TextField("user", text: $user).textInputAutocapitalization(.never).autocorrectionDisabled() }
                fieldRow("パスワード") {
                    SecureField(passwordSaved ? "保存済み" : "password", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Picker("NTRIP", selection: $version) {
                    Text("1").tag(NTRIPVersion.v1)
                    Text("2").tag(NTRIPVersion.v2)
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 44)
                Button("保存") { save() }
                    .buttonStyle(SurveyPlainButton())
                Button("受信機を探す") { field.scanReceivers() }
                    .buttonStyle(SurveyPlainButton())
                ForEach(field.receiverChoices) { choice in
                    Button(choice.name) { field.connectReceiver(choice.id) }
                        .buttonStyle(SurveyPlainButton())
                }
            }
            .padding(16)
        }
        .background(SurveyColor.background)
        .navigationTitle("外部受信機")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private func load() {
        let settings = NTRIPSettings.load()
        host = settings.host
        port = String(settings.port)
        mountpoint = settings.mountpoint
        user = settings.user
        version = settings.version
        enabled = settings.enabled
        password = ""
        passwordSaved = NTRIPSecret.exists()
    }

    private func save() {
        var settings = NTRIPSettings()
        settings.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.port = Int(port) ?? 2101
        settings.mountpoint = mountpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.user = user.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.version = version
        settings.enabled = enabled
        settings.save()
        if !password.isEmpty {
            NTRIPSecret.save(password)
            password = ""
            passwordSaved = true
        }
        field.applyExternalReceiver()
    }

    private func fieldRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SurveyType(14, .heavy))
                .foregroundStyle(SurveyColor.muted)
            control()
                .font(SurveyType(18, .heavy))
                .frame(minHeight: 44)
        }
    }
}
