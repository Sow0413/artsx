import Foundation
import SurveyCore
#if canImport(Network)
import Network
#endif

// ドコモ高精度GNSS位置情報サービス(NTRIP)から RTCM3 を受け、ViDoc(FFF2)へ注入して RTK Fix にする。
// 要求の形、GGA、応答の切り分けは SurveyCore の NTRIPExchange。ここは TCP だけ。
// 認証情報はログに出さない。

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

    public struct RoughPosition: Sendable {
        public var latitudeDegrees: Double
        public var longitudeDegrees: Double
        public var ellipsoidalHeightMeters: Double?
        public init(latitudeDegrees: Double, longitudeDegrees: Double, ellipsoidalHeightMeters: Double?) {
            self.latitudeDegrees = latitudeDegrees
            self.longitudeDegrees = longitudeDegrees
            self.ellipsoidalHeightMeters = ellipsoidalHeightMeters
        }
    }

    private let config: Config
    private weak var sink: ViDocPositionSource?
    private let queue = DispatchQueue(label: "arts.ntrip")
    private var connection: NWConnection?
    private var headerDone = false
    private var headerBuffer = Data()
    private var chunked = false
    private var chunks = NTRIPChunkDecoder()
    private var ggaTimer: DispatchSourceTimer?
    private var running = false
    private var plan = NTRIPReconnect()
    private var byteWindow = 0
    private var rateTimer: DispatchSourceTimer?
    private var stallTimer: DispatchSourceTimer?
    private var pendingOpen: DispatchWorkItem?

    public var onStatus: ((String) -> Void)?
    public var onHealth: ((LinkHealth) -> Void)?
    public var onBytesPerSecond: ((Int) -> Void)?
    /// 今の概略位置。ViDoc の GGA が無いときは iPhone の位置でもよい。
    public var roughPosition: (() -> RoughPosition?)?

    public init(config: Config, sink: ViDocPositionSource) {
        self.config = config
        self.sink = sink
    }

    public func start() {
        queue.async {
            self.running = true
            self.plan.correctionsEnabled = true
            self.sink?.correctionSource = "docomo \(self.config.mountpoint)"
            self.post("認証中")
            if let id = self.plan.start() { self.open(id) }
            self.startStallTimer()
        }
    }

    public func stop() {
        queue.async {
            self.running = false
            self.plan.correctionsEnabled = false
            self.pendingOpen?.cancel(); self.pendingOpen = nil
            self.ggaTimer?.cancel(); self.ggaTimer = nil
            self.rateTimer?.cancel(); self.rateTimer = nil
            self.stallTimer?.cancel(); self.stallTimer = nil
            self.connection?.cancel(); self.connection = nil
        }
    }

    /// マウント一覧。流れは始めない。
    public static func fetchMounts(config: Config, completion: @escaping ([String], String?) -> Void) {
        let queue = DispatchQueue(label: "arts.ntrip.list")
        guard let port = NWEndpoint.Port(rawValue: config.port) else {
            completion([], "ポートが数値ではありません")
            return
        }
        let conn = NWConnection(host: NWEndpoint.Host(config.host), port: port, using: .tcp)
        var buffer = Data()
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let wire = NTRIPExchange.request(host: config.host, mount: nil, user: config.user, password: config.password, dialect: .v1, gga: nil)
                conn.send(content: wire.bytes, completion: .contentProcessed { _ in })
                func receive() {
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, done, _ in
                        if let data { buffer.append(data) }
                        if done || buffer.count > 200_000 {
                            conn.cancel()
                            let text = String(data: buffer, encoding: .utf8) ?? ""
                            let names = NTRIPExchange.mounts(in: text)
                            completion(names, names.isEmpty ? "マウント一覧が空でした" : nil)
                        } else {
                            receive()
                        }
                    }
                }
                receive()
            case .failed:
                completion([], "マウント一覧につなげません")
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func open(_ id: Int) {
        guard running, plan.socket.openID == id, connection == nil else { return }
        headerDone = false
        chunked = false
        chunks = NTRIPChunkDecoder()
        headerBuffer.removeAll(keepingCapacity: true)
        guard let port = NWEndpoint.Port(rawValue: config.port) else { return }
        let conn = NWConnection(host: NWEndpoint.Host(config.host), port: port, using: .tcp)
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard let self, self.plan.socket.openID == id else { return }
            switch state {
            case .ready:
                self.sendRequest()
                self.receiveLoop()
                self.startRateTimer()
            case .failed:
                self.handleLoss("Casterにつなげません", dialectHint: !self.plan.everStreamed)
            case .cancelled:
                break
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func handleLoss(_ reason: String, dialectHint: Bool) {
        guard running else { return }
        let now = Date().timeIntervalSinceReferenceDate
        guard let delay = plan.lost(reason: reason, at: now, dialectHint: dialectHint) else { return }
        publish(nil)
        ggaTimer?.cancel(); ggaTimer = nil
        rateTimer?.cancel(); rateTimer = nil
        let closing = plan.socket.closingID
        let old = connection
        connection = nil
        var finished = false
        let proceed = { [weak self] in
            guard let self, !finished else { return }
            finished = true
            if let closing { self.plan.noteClosed(closing) }
            self.scheduleOpen(after: delay)
        }
        if let old {
            old.stateUpdateHandler = { state in
                switch state {
                case .cancelled, .failed:
                    self.queue.async { proceed() }
                default:
                    break
                }
            }
            old.cancel()
        } else {
            proceed()
        }
    }

    private func scheduleOpen(after delay: TimeInterval) {
        pendingOpen?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.running else { return }
            guard let id = self.plan.readyToOpen() else { return }
            self.open(id)
        }
        pendingOpen = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func sendRequest() {
        let gga = currentGGA()
        let wire = NTRIPExchange.request(
            host: config.host,
            mount: config.mountpoint,
            user: config.user,
            password: config.password,
            dialect: plan.dialect,
            gga: gga
        )
        connection?.send(content: wire.bytes, completion: .contentProcessed { _ in })
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self, self.running else { return }
            if let data, !data.isEmpty {
                if self.headerDone {
                    self.deliver(data)
                } else {
                    self.consumeHeader(data)
                }
            }
            if isComplete || error != nil {
                let reason = self.headerDone ? "Casterが閉じました" : "Casterが切断しました"
                self.handleLoss(reason, dialectHint: !self.plan.everStreamed)
            } else if self.running {
                self.receiveLoop()
            }
        }
    }

    private func consumeHeader(_ data: Data) {
        headerBuffer.append(data)
        guard let header = NTRIPExchange.parseHeader(headerBuffer) else {
            if headerBuffer.count > 16384 {
                handleLoss("Casterが切断しました", dialectHint: !plan.everStreamed)
            }
            return
        }
        guard header.reply == .stream else {
            let line = header.reply.statusLine(mount: config.mountpoint)
            handleLoss(line, dialectHint: !plan.everStreamed || header.reply == .unavailable)
            return
        }
        headerDone = true
        chunked = header.chunked
        headerBuffer.removeAll(keepingCapacity: false)
        plan.streamBegan(at: Date().timeIntervalSinceReferenceDate)
        publish("NTRIP 接続 \(config.mountpoint)")
        sendCurrentGGA()
        startGGATimer()
        if !header.body.isEmpty { deliver(header.body) }
    }

    private func deliver(_ data: Data) {
        let payload = chunked ? chunks.feed(data) : data
        guard !payload.isEmpty else { return }
        byteWindow += payload.count
        plan.bytes(at: Date().timeIntervalSinceReferenceDate)
        sink?.injectRTCM(payload)
    }

    private func sendCurrentGGA() {
        guard let gga = currentGGA() else { return }
        let line = gga.hasSuffix("\r\n") ? gga : gga + "\r\n"
        connection?.send(content: Data(line.utf8), completion: .contentProcessed { _ in })
    }

    private func startGGATimer() {
        ggaTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + NTRIPExchange.ggaIntervalSeconds, repeating: NTRIPExchange.ggaIntervalSeconds)
        timer.setEventHandler { [weak self] in
            guard let self, self.headerDone else { return }
            self.sendCurrentGGA()
        }
        timer.resume()
        ggaTimer = timer
    }

    private func startRateTimer() {
        rateTimer?.cancel()
        let rate = DispatchSource.makeTimerSource(queue: queue)
        rate.schedule(deadline: .now() + 1, repeating: 1)
        rate.setEventHandler { [weak self] in
            guard let self else { return }
            let count = self.byteWindow
            self.byteWindow = 0
            if self.headerDone { self.onBytesPerSecond?(count) }
        }
        rate.resume()
        rateTimer = rate
    }

    private func startStallTimer() {
        stallTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, self.running else { return }
            let now = Date().timeIntervalSinceReferenceDate
            if self.plan.stalled(at: now) {
                self.handleLoss("RTCMが止まった", dialectHint: false)
            }
        }
        timer.resume()
        stallTimer = timer
    }

    private func currentGGA() -> String? {
        if let sentence = sink?.lastGGA, sentence.contains("GGA") { return sentence }
        guard let place = roughPosition?() else { return nil }
        return NTRIPExchange.gpgga(
            latitudeDegrees: place.latitudeDegrees,
            longitudeDegrees: place.longitudeDegrees,
            ellipsoidalHeightMeters: place.ellipsoidalHeightMeters
        )
    }

    private func publish(_ live: String?) {
        onHealth?(plan.health)
        let time = plan.health.lastAt.map { LinkClock.text($0) } ?? ""
        if plan.health.reconnecting {
            post(plan.health.reconnectingText(time: time))
        } else if let live {
            post(live + plan.health.settledSuffix(time: time))
        }
    }

    private func post(_ text: String) {
        onStatus?(text)
    }
}
#endif
