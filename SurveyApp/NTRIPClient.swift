import Foundation
import SurveyCore
#if canImport(Network)
import Network
#endif

// ドコモ高精度GNSS位置情報サービス(NTRIP)から RTCM3 を受け、ViDoc(FFF2)へ注入して RTK Fix にする。
//   接続先 d-gnss.jp:2101 / Basic 認証 / 最寄り局自動選択マウントポイント。
//   マウントポイント: RRSGD2024=測地成果2024（今後の標準） / RRSGD=測地成果2011。混ぜると座標がずれる。
//   移動局の概略位置は ViDoc 自身の GGA を 1 秒ごとにサーバへ返す（最寄り基準点の選択に要る）。
//   認証情報(ID/パスワード)はアプリの設定で入れ、Keychain に置く。ここには埋め込まない。
// 実機の接続・RTK Fix は未確認。

#if canImport(Network) && canImport(CoreBluetooth)
public final class NTRIPClient: @unchecked Sendable {
    public struct Config: Sendable {
        public var host: String
        public var port: UInt16
        public var mountpoint: String
        public var user: String
        public var password: String
        public init(host: String = "d-gnss.jp", port: UInt16 = 2101,
                    mountpoint: String = "RRSGD2024", user: String, password: String) {
            self.host = host; self.port = port; self.mountpoint = mountpoint
            self.user = user; self.password = password
        }
    }

    private let config: Config
    private weak var sink: ViDocPositionSource?
    private let queue = DispatchQueue(label: "arts.ntrip")
    private var connection: NWConnection?
    private var headerDone = false
    private var headerBuffer = Data()
    private var ggaTimer: DispatchSourceTimer?
    private var running = false

    /// 状態の通知（「NTRIP 接続 RRSGD2024」「認証 NG」など）。画面に出す用。
    public var onStatus: ((String) -> Void)?

    public init(config: Config, sink: ViDocPositionSource) {
        self.config = config
        self.sink = sink
    }

    public func start() {
        queue.async {
            self.running = true
            self.sink?.correctionSource = "docomo \(self.config.mountpoint)"
            self.connect()
        }
    }

    public func stop() {
        queue.async {
            self.running = false
            self.ggaTimer?.cancel(); self.ggaTimer = nil
            self.connection?.cancel(); self.connection = nil
        }
    }

    private func connect() {
        headerDone = false
        headerBuffer.removeAll(keepingCapacity: true)
        guard let port = NWEndpoint.Port(rawValue: config.port) else { return }
        let conn = NWConnection(host: NWEndpoint.Host(config.host), port: port, using: .tcp)
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.sendRequest()
                self.receiveLoop()
                self.startGGATimer()
            case .failed, .cancelled:
                self.scheduleReconnect()
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func scheduleReconnect() {
        guard running else { return }
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.running else { return }
            self.connect()
        }
    }

    private func sendRequest() {
        let auth = Data("\(config.user):\(config.password)".utf8).base64EncodedString()
        let req = "GET /\(config.mountpoint) HTTP/1.0\r\n"
            + "User-Agent: NTRIP arts-survey/1.0\r\n"
            + "Authorization: Basic \(auth)\r\n"
            + "Accept: */*\r\nConnection: close\r\n\r\n"
        connection?.send(content: Data(req.utf8), completion: .contentProcessed { _ in })
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                if self.headerDone {
                    self.sink?.injectRTCM(data)        // 本体は全部 RTCM3
                } else {
                    self.consumeHeader(data)
                }
            }
            if isComplete || error != nil {
                self.scheduleReconnect()
            } else {
                self.receiveLoop()
            }
        }
    }

    /// ヘッダ(ICY 200 OK / HTTP 200)を読み飛ばし、境目より後ろを RTCM として注入する。
    private func consumeHeader(_ data: Data) {
        headerBuffer.append(data)
        guard let split = headerBodySplit(headerBuffer) else {
            if headerBuffer.count > 16384 { connection?.cancel() }   // 壊れたヘッダ対策
            return
        }
        let head = String(data: headerBuffer.subdata(in: headerBuffer.startIndex..<split), encoding: .ascii) ?? ""
        let status = head.split(separator: "\r\n").first.map(String.init) ?? head
        guard status.contains("200") else {
            onStatus?("NTRIP 認証/マウントポイント NG: \(status)")
            connection?.cancel()
            return
        }
        onStatus?("NTRIP 接続 \(config.mountpoint)")
        headerDone = true
        let body = headerBuffer.subdata(in: split..<headerBuffer.endIndex)
        headerBuffer.removeAll(keepingCapacity: false)
        if !body.isEmpty { sink?.injectRTCM(body) }
    }

    private func headerBodySplit(_ data: Data) -> Data.Index? {
        if let r = data.range(of: Data("\r\n\r\n".utf8)) { return r.upperBound }
        if let r = data.range(of: Data("ICY 200 OK\r\n".utf8)) { return r.upperBound }
        return nil
    }

    /// ViDoc の最新 GGA を 1 秒以上の間隔でサーバへ返す（最寄り基準点の選択に要る）。
    private func startGGATimer() {
        ggaTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 2)
        t.setEventHandler { [weak self] in
            guard let self, self.headerDone, let gga = self.sink?.lastGGA else { return }
            self.connection?.send(content: Data((gga + "\r\n").utf8), completion: .contentProcessed { _ in })
        }
        t.resume()
        ggaTimer = t
    }
}
#endif
