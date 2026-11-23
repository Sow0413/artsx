import Foundation
import SurveyCore
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif

// ViDoc(viGram)RTK ローバーの位置源。iPhone / iPad の BLE で直結し、標準 NMEA を読む。
//
// 相互運用の鍵（2026-11-22 に社内で解読。Pix4Dcatch の複製ではなく、自社機材の相互運用）:
//   Service 0xFFF0
//     0xFFF1  Notify  … ViDoc の出力。待機中は <STX>df Ver_0.0.4、開始後は NMEA。
//     0xFFF2  Write   … 入力。開始コマンドと、RTK 補正(RTCM3)を流す口。
//   接続のたび FFF2 へ <STX>start<ETX>、FFF1 の電池行（または 2 秒）のあと <STX>nmea<ETX>。
//   NTRIP(ドコモ d-gnss.jp)の RTCM3 を FFF2 に流すと quality が 2(DGPS)→4(RTK Fix) に上がる。
//
// PositionSource に準拠するので、iPhone / CLAS と同じ読み方で画面に入る（README の設計どおり）。
// 補正(RTCM)の供給は NTRIPClient が受け持ち、injectRTCM(_:) でこの口に流し込む。
// 文の解釈は SurveyCore の NMEAParser。実機（iPhone/iPad の BLE 接続・NMEA 受信・RTK Fix）は未確認。

#if canImport(CoreBluetooth)
public final class ViDocPositionSource: NSObject, PositionSource, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    public let receiver: ReceiverKind = .rtk
    public private(set) var stage: PositionStage = .iphone   // Fix/Float 到達で .rtk に上げる
    public let readings: AsyncStream<PositionReading>
    private let continuation: AsyncStream<PositionReading>.Continuation

    // GATT（解読済み）
    private static let serviceUUID = CBUUID(string: "FFF0")
    private static let notifyUUID  = CBUUID(string: "FFF1")
    private static let writeUUID   = CBUUID(string: "FFF2")
    private var notifyChar: CBCharacteristic?
    private var boot = ViDocBoot()
    private var bootGeneration = 0
    private var outbound = ViDocOutbound()
    private var rtcmSchedule = RTCMWriteSchedule()
    private var rtcmDrainScheduled = false
    private var recovery = ViDocRecovery()
    private var peripheralID: UUID?
    private var notifyWatch: DispatchSourceTimer?
    private var pendingDrop: String?

    private let queue = DispatchQueue(label: "arts.vidoc.ble")
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var nmeaBuffer = Data()
    private var nmea = NMEAParser()
    private var running = false

    // 補正の出どころ（NTRIPClient が設定。帳票の「補正元」に出す）
    public var correctionSource: String?
    // 最新の GGA 文（NTRIP へ概略位置として送るのに使う）
    public private(set) var lastGGA: String?
    /// 画面向けの接続段階。Bluetooth のキューからメインへ渡す。
    public var onLink: ((String) -> Void)?
    private var deviceName = ""
    // 最後に RTCM を流した時刻（文に補正遅れが無いときの算出に使う）
    private var lastRTCMAt: Date?

    public override init() {
        let pair = AsyncStream<PositionReading>.makeStream()
        self.readings = pair.stream
        self.continuation = pair.continuation
        super.init()
    }

    // MARK: PositionSource
    public func start() {
        queue.async {
            self.running = true
            if self.central == nil {
                self.central = CBCentralManager(delegate: self, queue: self.queue)
            } else if self.central?.state == .poweredOn {
                self.startScan()
            }
        }
    }

    public func stop() {
        queue.async {
            self.running = false
            self.central?.stopScan()
            self.notifyWatch?.cancel(); self.notifyWatch = nil
            if let p = self.peripheral { self.central?.cancelPeripheralConnection(p) }
            self.stage = .iphone
            self.continuation.yield(PositionReading(position: nil, availability: .waiting))
        }
    }

    /// NTRIPClient から RTCM3 を注入する。180 バイト以下に切り、12 ms 以上あけて FFF2 へ書く。
    public func injectRTCM(_ data: Data) {
        queue.async {
            self.outbound.corrections.append(data, at: Date().timeIntervalSinceReferenceDate)
            self.drainRTCM()
        }
    }

    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        queue.async { self.drainRTCM() }
    }

    private func drainRTCM() {
        guard let peripheral, let writeChar else { return }
        let size = ViDocLink.chunkSize(maximumWriteLength: peripheral.maximumWriteValueLength(for: .withoutResponse))
        let now = Date().timeIntervalSinceReferenceDate
        guard rtcmSchedule.allows(at: now, transportReady: peripheral.canSendWriteWithoutResponse) else {
            if !peripheral.canSendWriteWithoutResponse { return }
            scheduleRTCMDrain(after: max(0, rtcmSchedule.nextAllowed - now))
            return
        }
        let writingCommand = !outbound.commands.isEmpty
        guard let chunk = outbound.nextWrite(maximumChunkBytes: size) else { return }
        peripheral.writeValue(chunk, for: writeChar, type: .withoutResponse)
        rtcmSchedule = rtcmSchedule.advanced(afterSendingAt: now)
        if !writingCommand { lastRTCMAt = Date() }
        scheduleRTCMDrain(after: Double(ViDocLink.rtcmChunkIntervalMs) / 1_000)
    }

    private func scheduleRTCMDrain(after seconds: TimeInterval) {
        guard !rtcmDrainScheduled else { return }
        rtcmDrainScheduled = true
        queue.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            self.rtcmDrainScheduled = false
            self.drainRTCM()
        }
    }

    private func startScan() {
        // 広告の Service Data は FFE1 で、GATT の FFF0 は UUID 一覧に出ないことがある。
        // サービス指定のスキャンだと FFE1 だけの機体を見落とすので、前面では全件を見てから判定する。
        reportState("探索中")
        central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    // MARK: CBCentralManagerDelegate
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if running { startScan() }
        case .unauthorized:
            reportState("Bluetooth が許可されていません")
            continuation.yield(PositionReading(position: nil, availability: .denied))
        case .poweredOff:
            reportState("Bluetooth がオフです")
            continuation.yield(PositionReading(position: nil, availability: .unavailable))
        case .unsupported:
            reportState("この端末では Bluetooth を使えません")
            continuation.yield(PositionReading(position: nil, availability: .unavailable))
        default:
            reportState("Bluetooth を準備しています")
            continuation.yield(PositionReading(position: nil, availability: .unavailable))
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
        let overflow = (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
        let serviceData = (advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data])?.keys.map(\.uuidString) ?? []
        let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        guard ViDocDiscovery.matches(
            localName: name,
            serviceUUIDs: services,
            overflowServiceUUIDs: overflow,
            serviceDataUUIDs: serviceData,
            manufacturerData: manufacturer
        ) else { return }
        if let wanted = peripheralID, peripheral.identifier != wanted { return }
        central.stopScan()
        deviceName = name.isEmpty ? "ViDoc" : name
        reportState("ViDoc を見つけました（\(deviceName)）")
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name ?? deviceName
        deviceName = name.isEmpty ? deviceName : name
        peripheralID = peripheral.identifier
        recovery.remember(peripheral.identifier.uuidString)
        recovery.watch(at: Date().timeIntervalSinceReferenceDate)
        armNotifyWatch()
        reportState("接続しました（\(deviceName)）")
        peripheral.discoverServices([Self.serviceUUID])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard running else { return }
        self.peripheral = nil
        if recovery.health.reconnecting {
            startScan()
        } else {
            finishRecovery("接続できません")
        }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        writeChar = nil
        notifyChar = nil
        stage = .iphone
        continuation.yield(PositionReading(position: nil, availability: .waiting))
        guard running else { return }
        if let reason = pendingDrop {
            pendingDrop = nil
            finishRecovery(reason)
            return
        }
        if recovery.health.reconnecting {
            self.peripheral = nil
            startScan()
            return
        }
        finishRecovery("切断")
    }

    // MARK: CBPeripheralDelegate
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for s in peripheral.services ?? [] where s.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.notifyUUID, Self.writeUUID], for: s)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        var notify: CBCharacteristic?
        for c in service.characteristics ?? [] {
            if c.uuid == Self.notifyUUID { notify = c }
            if c.uuid == Self.writeUUID { writeChar = c }
        }
        notifyChar = notify
        if let notify {
            peripheral.setNotifyValue(true, for: notify)
        }
        beginBoot()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.notifyUUID, error == nil else { return }
        notifyChar = characteristic
        beginBoot()
    }

    /// 再接続のたびに start を1回書き、準備完了か 2 秒で nmea を書く。どちらも RTCM の間の1書き込み。
    private func beginBoot() {
        guard case .needStart = boot.phase else { return }
        guard let notify = notifyChar, notify.isNotifying, writeChar != nil else { return }
        let now = Date().timeIntervalSinceReferenceDate
        recovery.linkUp(at: now)
        reportState("接続しました（\(deviceName)）")
        outbound.enqueueCommand(boot.onConnect(at: now))
        bootGeneration += 1
        let generation = bootGeneration
        queue.asyncAfter(deadline: .now() + ViDocLink.readyTimeoutSeconds) { [weak self] in
            guard let self, self.bootGeneration == generation else { return }
            let now = Date().timeIntervalSinceReferenceDate
            if let command = self.boot.onTimeout(at: now) {
                self.outbound.enqueueCommand(command)
                self.drainRTCM()
            }
        }
        drainRTCM()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.notifyUUID, let data = characteristic.value else { return }
        recovery.notify(at: Date().timeIntervalSinceReferenceDate)
        nmeaBuffer.append(data)
        while let nl = nmeaBuffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = nmeaBuffer.subdata(in: nmeaBuffer.startIndex..<nl)
            nmeaBuffer.removeSubrange(nmeaBuffer.startIndex...nl)
            guard let line = String(data: lineData, encoding: .ascii)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else { continue }
            let now = Date().timeIntervalSinceReferenceDate
            if let command = boot.onNotify(line, at: now) {
                outbound.enqueueCommand(command)
                drainRTCM()
            }
            if line.hasPrefix("$") { handleNMEA(line) }
        }
        if nmeaBuffer.count > 4096 { nmeaBuffer.removeAll(keepingCapacity: true) }
    }

    private func handleNMEA(_ line: String) {
        guard let epoch = nmea.consume(line) else { return }
        lastGGA = epoch.sentence
        let count = epoch.satelliteCount.map(String.init) ?? "—"
        reportState("NMEA 受信中 衛星 \(count) \(Self.qualityLabel(epoch.fixQuality))")
        let age = epoch.correctionAgeSeconds ?? lastRTCMAt.map { Date().timeIntervalSince($0) }
        stage = epoch.stage
        let stationID = epoch.stationID
        let srcLabel = correctionSource.map { stationID.isEmpty ? $0 : "\($0) #\(stationID)" }
            ?? (stationID.isEmpty ? nil : "#\(stationID)")
        let position = GeodeticPosition(
            latitudeDegrees: epoch.latitudeDegrees,
            longitudeDegrees: epoch.longitudeDegrees,
            ellipsoidalHeightMeters: epoch.ellipsoidalHeightMeters,
            horizontalAccuracyMeters: epoch.horizontalAccuracyMeters,
            verticalAccuracyMeters: epoch.verticalAccuracyMeters,
            timestamp: Date(),
            stage: epoch.stage,
            fixQuality: epoch.fixQuality,
            receiver: .rtk,
            frame: .wgs84ITRF,
            satelliteCount: epoch.satelliteCount,
            satellites: nil,
            pdop: epoch.pdop,
            correctionAgeSeconds: age,
            correctionSource: srcLabel,
            courseDegrees: nil,
            headingDegrees: nil
        )
        continuation.yield(PositionReading(position: position, availability: .available))
    }

    private func beginRecovery(_ reason: String) {
        guard running, pendingDrop == nil, !recovery.health.reconnecting else { return }
        if peripheral != nil {
            pendingDrop = reason
            if let peripheral { central?.cancelPeripheralConnection(peripheral) }
            return
        }
        finishRecovery(reason)
    }

    private func finishRecovery(_ reason: String) {
        guard running else { return }
        let now = Date().timeIntervalSinceReferenceDate
        outbound.clearCommands()
        outbound.corrections.dropOlder(than: 2, now: now)
        boot = ViDocBoot()
        bootGeneration += 1
        writeChar = nil
        notifyChar = nil
        let found = peripheralID.flatMap { central?.retrievePeripherals(withIdentifiers: [$0]).first }
        _ = recovery.recover(reason: reason, at: now, retrieved: found != nil)
        reportState("")
        if let found {
            peripheral = found
            found.delegate = self
            central?.connect(found, options: nil)
        } else {
            peripheral = nil
            startScan()
        }
    }

    private func armNotifyWatch() {
        notifyWatch?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, self.running else { return }
            let now = Date().timeIntervalSinceReferenceDate
            if self.recovery.stall.isStalled(at: now, connected: self.recovery.linked) {
                self.beginRecovery("通知が止まった")
            }
        }
        timer.resume()
        notifyWatch = timer
    }

    private func reportState(_ line: String) {
        let time = recovery.health.lastAt.map { LinkClock.text($0) } ?? ""
        if recovery.health.reconnecting {
            report(recovery.health.reconnectingText(time: time))
        } else if line.isEmpty {
            report(recovery.health.settledSuffix(time: time))
        } else {
            report(line + recovery.health.settledSuffix(time: time))
        }
    }

    private func report(_ line: String) {
        let callback = onLink
        DispatchQueue.main.async { callback?(line) }
    }

    private static func qualityLabel(_ quality: FixQuality) -> String {
        switch quality {
        case .rtkFix: return "FIX"
        case .float: return "FLOAT"
        case .dgps: return "DGPS"
        case .clas: return "CLAS"
        case .standalone: return "単独"
        case .none: return "未測位"
        }
    }
}
#endif
