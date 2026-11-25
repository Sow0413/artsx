import Foundation
import Combine
import SurveyCore
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif
#if canImport(Security)
import Security
#endif
#if canImport(UIKit)
import UIKit
#endif

// iPhone GPS と ViDoc RTK を実行時に切り替える位置源。FieldModel にはこれを 1 つ渡す。
// 設定画面(RTKSettingsView)が、この口を通して「受信機につなぐ」「補正を入れる」を操作する。
// 位置の読み方は PositionSource のまま（README の設計: iPhone / CLAS / RTK は同じ読み方で画面に入る）。
//
// AsyncStream は1本につき1回しか読めない。切り替えるたびに読み直すと、iPhone に戻したあと位置が止まる。
// それぞれの源は start のときに1回だけ読み、今選んでいる側だけを画面へ流す。

#if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)

public enum RTKLinkMode: String, Sendable { case iphone, rtk }

public final class RTKPositionSession: NSObject, PositionSource, ObservableObject, @unchecked Sendable {
    // 画面に出す状態
    @Published public private(set) var mode: RTKLinkMode = .iphone
    @Published public private(set) var deviceConnected = false
    @Published public private(set) var fix: FixQuality = .standalone
    @Published public private(set) var horizontalAccuracyMeters: Double?
    @Published public private(set) var satelliteCount: Int?
    @Published public private(set) var correctionAgeSeconds: Double?
    @Published public private(set) var ntripConnected = false
    @Published public private(set) var message: String = ""
    @Published public private(set) var vidocLine = "未接続"
    @Published public private(set) var firmwareVersion: String?
    public var onDeviceTilt: ((Double) -> Void)?
    public var onLaserDistance: ((Double) -> Void)?
    public var onLaserFailed: (() -> Void)?
    public var onLaserLamp: ((ViDocCommandPlan.Lamp) -> Void)?
    public var onLaserNeedAim: (() -> Void)?
    @Published public private(set) var ntripLine = "未接続"
    @Published public private(set) var holdGCPUntilFix = false

    // 中身
    private let iphone = CoreLocationPositionSource()
    private let vidoc = ViDocPositionSource()
    private var ntrip: NTRIPClient?

    // PositionSource（FieldModel が消費する一本のストリーム）
    public let readings: AsyncStream<PositionReading>
    private let continuation: AsyncStream<PositionReading>.Continuation
    public var receiver: ReceiverKind { mode == .rtk ? .rtk : .iphoneGPS }
    public var stage: PositionStage { mode == .rtk ? vidoc.stage : .iphone }

    private let gate = DispatchQueue(label: "arts.rtk.session")
    private var activeID: ObjectIdentifier?
    private var rough: NTRIPClient.RoughPosition?
    private var ntripRate = 0
    private var ntripHealth = LinkHealth()
    private var sky = SkyWatch()
    private var listeners: [Task<Void, Never>] = []
    private var armed = false

    public override init() {
        let pair = AsyncStream<PositionReading>.makeStream()
        self.readings = pair.stream
        self.continuation = pair.continuation
        super.init()
        vidoc.onFirmware = { [weak self] version in
            self?.setMain { self?.firmwareVersion = version }
        }
        vidoc.onTilt = { [weak self] degrees in
            self?.setMain { self?.onDeviceTilt?(degrees) }
        }
        vidoc.onLaserMeters = { [weak self] meters in
            self?.setMain { self?.onLaserDistance?(meters) }
        }
        vidoc.onLaserFailed = { [weak self] in
            self?.setMain { self?.onLaserFailed?() }
        }
        vidoc.onLaserLamp = { [weak self] lamp in
            self?.setMain { self?.onLaserLamp?(lamp) }
        }
        vidoc.onLaserNeedAim = { [weak self] in
            self?.setMain { self?.onLaserNeedAim?() }
        }
        vidoc.onLink = { [weak self] line in
            self?.setMain {
                self?.vidocLine = line
                if let version = ViDocFirmware.version(in: line), self?.firmwareVersion?.contains("build") != true {
                    self?.firmwareVersion = version
                }
                self?.deviceConnected = line.hasPrefix("接続しました") || line.hasPrefix("NMEA")
                if line.hasPrefix("再接続中") { self?.holdGCPUntilFix = true }
            }
        }
    }

    // MARK: PositionSource
    public func setObserving(_ on: Bool) { vidoc.setObserving(on) }
    public func setPPKBase(_ url: URL?) { vidoc.setPPKBase(url) }
    public func lightFrontLaser() { vidoc.lightFrontLaser() }
    public func measureFrontLaser() { vidoc.measureFrontLaser() }

    public func lightLowerLaser() {
        vidoc.lightLowerLaser()
    }

    public func measureLowerLaser() {
        vidoc.measureLowerLaser()
    }

    public func start() {
        if !armed {
            armed = true
            listen(iphone)
            listen(vidoc)
        }
        activate(mode == .rtk ? vidoc : iphone)
    }

    public func stop() {
        ntrip?.stop()
        iphone.stop()
        vidoc.stop()
    }

    // MARK: 切り替え
    /// iPhone 単独に戻す。
    public func useiPhone() {
        ntrip?.stop(); ntrip = nil
        vidoc.stop()
        setMain {
            self.mode = .iphone
            self.ntripConnected = false
            self.deviceConnected = false
            self.fix = .standalone
            self.horizontalAccuracyMeters = nil
            self.satelliteCount = nil
            self.correctionAgeSeconds = nil
            self.message = ""
            self.vidocLine = "未接続"
            self.ntripLine = "未接続"
            self.holdGCPUntilFix = false
        }
        setScreenAwake(false)
        activate(iphone)
    }

    /// ViDoc につなぎ、必要なら NTRIP 補正も始める。password は Keychain から。
    public func connectRTK(settings: RTKSettings, password: String) {
        iphone.stop()
        setMain {
            self.mode = .rtk
            self.deviceConnected = false
            self.fix = .none
            self.horizontalAccuracyMeters = nil
            self.message = "ViDoc を探しています"
            self.vidocLine = "探索中"
            self.ntripLine = settings.correctionsEnabled ? "認証中" : "未接続"
        }
        setScreenAwake(true)
        activate(vidoc)
        if settings.correctionsEnabled, !settings.user.isEmpty, !password.isEmpty {
            let cfg = NTRIPClient.Config(host: settings.host, port: settings.port,
                                         mountpoint: settings.activeMount,
                                         user: settings.user, password: password)
            let client = NTRIPClient(config: cfg, sink: vidoc)
            client.roughPosition = { [weak self] in self?.rough }
            client.onBytesPerSecond = { [weak self] rate in
                self?.setMain {
                    self?.ntripRate = rate
                    self?.refreshNTRIPRate()
                }
            }
            client.onHealth = { [weak self] health in
                self?.setMain {
                    self?.ntripHealth = health
                    if health.reconnecting { self?.holdGCPUntilFix = true }
                }
            }
            client.onStatus = { [weak self] status in
                self?.setMain {
                    self?.message = status
                    self?.ntripLine = status
                    self?.ntripConnected = status.hasPrefix("NTRIP 接続") || status.hasPrefix("補正受信中")
                    if self?.ntripConnected == true { self?.refreshNTRIPRate() }
                }
            }
            ntrip = client
            client.start()
        } else {
            ntrip?.stop(); ntrip = nil
            setMain { self.ntripConnected = false }
        }
    }

    public func disconnectRTK() { useiPhone() }

    // MARK: 内部
    private func listen(_ source: any PositionSource) {
        let id = ObjectIdentifier(source)
        let stream = source.readings
        let task = Task { [weak self] in
            for await reading in stream {
                guard let self, self.isActive(id) else { continue }
                self.continuation.yield(reading)
                self.observe(reading)
            }
        }
        listeners.append(task)
    }

    deinit {
        listeners.forEach { $0.cancel() }
    }

    private func activate(_ source: any PositionSource) {
        gate.sync { activeID = ObjectIdentifier(source) }
        source.start()
    }

    private func isActive(_ id: ObjectIdentifier) -> Bool {
        gate.sync { activeID == id }
    }

    private func observe(_ reading: PositionReading) {
        guard let position = reading.position else {
            setMain {
                if self.mode == .rtk { self.deviceConnected = false }
            }
            return
        }
        setMain {
            if position.isPlottable {
                self.rough = NTRIPClient.RoughPosition(
                    latitudeDegrees: position.latitudeDegrees,
                    longitudeDegrees: position.longitudeDegrees,
                    ellipsoidalHeightMeters: position.ellipsoidalHeightMeters
                )
            }
            self.horizontalAccuracyMeters = position.hasValidHorizontalAccuracy ? position.horizontalAccuracyMeters : nil
            self.fix = position.fixQuality
            if self.mode == .rtk {
                self.deviceConnected = true
                self.satelliteCount = position.satelliteCount
                self.correctionAgeSeconds = position.correctionAgeSeconds
                if position.fixQuality == .rtkFix {
                    self.holdGCPUntilFix = false
                    self.message = "RTK Fix"
                }
                _ = self.sky.observe(position.satelliteCount)
                if self.sky.lost, !self.vidocLine.hasPrefix("再接続中"), !self.vidocLine.contains("上空") {
                    self.vidocLine += "　\(self.sky.note)"
                }
                else if position.fixQuality == .float { self.message = "RTK Float" }
                else if self.ntripConnected { self.message = "補正受信中（収束待ち）" }
            }
        }
    }

    private func refreshNTRIPRate() {
        guard ntripConnected, !ntripHealth.reconnecting else { return }
        let age = correctionAgeSeconds.map { String(format: " 補正 %.0f秒", $0) } ?? ""
        let time = ntripHealth.lastAt.map { LinkClock.text($0) } ?? ""
        ntripLine = "補正受信中 \(ntripRate) B/s\(age)" + ntripHealth.settledSuffix(time: time)
    }

    private func setScreenAwake(_ awake: Bool) {
        #if canImport(UIKit)
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = awake
        }
        #endif
    }

    private func setMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }
}

// MARK: - パスワードは Keychain に置く（JSON には残さない）
public enum RTKKeychain {
    private static let service = "arts.survey.ntrip"
    public static func save(user: String, password: String) {
        #if canImport(Security)
        write(account: account(user), password: password)
        write(account: "ntrip", password: password)
        #endif
    }
    public static func load(user: String) -> String {
        #if canImport(Security)
        let named = read(account: account(user))
        return named.isEmpty ? read(account: "ntrip") : named
        #else
        return ""
        #endif
    }

    private static func account(_ user: String) -> String {
        user.isEmpty ? "default" : user
    }

    #if canImport(Security)
    private static func write(account: String, password: String) {
        let data = Data(password.utf8)
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func read(account: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
    #endif
}
#endif
