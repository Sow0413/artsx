import Foundation
import Combine
import SurveyCore
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif
#if canImport(Security)
import Security
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
    private var listeners: [Task<Void, Never>] = []
    private var armed = false

    public override init() {
        let pair = AsyncStream<PositionReading>.makeStream()
        self.readings = pair.stream
        self.continuation = pair.continuation
        super.init()
    }

    // MARK: PositionSource
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
        }
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
        }
        activate(vidoc)
        if settings.correctionsEnabled, !settings.user.isEmpty, !password.isEmpty {
            let cfg = NTRIPClient.Config(host: settings.host, port: settings.port,
                                         mountpoint: settings.mountpoint.rawValue,
                                         user: settings.user, password: password)
            let client = NTRIPClient(config: cfg, sink: vidoc)
            client.onStatus = { [weak self] status in
                self?.setMain {
                    self?.message = status
                    self?.ntripConnected = status.hasPrefix("NTRIP 接続")
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
            self.horizontalAccuracyMeters = position.hasValidHorizontalAccuracy ? position.horizontalAccuracyMeters : nil
            self.fix = position.fixQuality
            if self.mode == .rtk {
                self.deviceConnected = true
                self.satelliteCount = position.satelliteCount
                self.correctionAgeSeconds = position.correctionAgeSeconds
                if position.fixQuality == .rtkFix { self.message = "RTK Fix" }
                else if position.fixQuality == .float { self.message = "RTK Float" }
                else if self.ntripConnected { self.message = "補正受信中（収束待ち）" }
            }
        }
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
        let account = user.isEmpty ? "default" : user
        let data = Data(password.utf8)
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var add = base; add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
        #endif
    }
    public static func load(user: String) -> String {
        #if canImport(Security)
        let account = user.isEmpty ? "default" : user
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let text = String(data: data, encoding: .utf8) else { return "" }
        return text
        #else
        return ""
        #endif
    }
}
#endif
